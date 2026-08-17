import Darwin
import Foundation
import RROrderCorpusCore

enum RROrderCorpusCLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidValue(option: String, value: String)
    case unknownOption(String)

    var description: String {
        switch self {
        case .missingValue(let option):
            return "Missing value for \(option)."
        case .invalidValue(let option, let value):
            return "Invalid value for \(option): \(value)"
        case .unknownOption(let option):
            return "Unknown option: \(option)"
        }
    }
}

struct RROrderCorpusCLIOptions {
    var databasePath: String?
    var deviceIDs: [String] = []
    var fromTs = 0
    var toTs = Int.max
    var sessionLimitPerDevice = 10_000
    var minimumDurationSeconds = 0
    var format = RROrderCorpusFormat.jsonl
    var outputPath: String?
    var includeDeviceID = false
    var showHelp = false

    static func parse(_ arguments: [String]) throws -> Self {
        var options = Self()
        var index = 0

        func value(after option: String) throws -> String {
            let valueIndex = index + 1
            guard valueIndex < arguments.count else { throw RROrderCorpusCLIError.missingValue(option) }
            index = valueIndex
            return arguments[valueIndex]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--db":
                options.databasePath = try value(after: argument)
            case "--device-id":
                let deviceID = try value(after: argument).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !deviceID.isEmpty else {
                    throw RROrderCorpusCLIError.invalidValue(option: argument, value: deviceID)
                }
                options.deviceIDs.append(deviceID)
            case "--from":
                options.fromTs = try parseBoundary(try value(after: argument), endOfDay: false, option: argument)
            case "--to":
                options.toTs = try parseBoundary(try value(after: argument), endOfDay: true, option: argument)
            case "--limit":
                let raw = try value(after: argument)
                guard let parsed = Int(raw), parsed > 0 else {
                    throw RROrderCorpusCLIError.invalidValue(option: argument, value: raw)
                }
                options.sessionLimitPerDevice = parsed
            case "--min-duration-min":
                let raw = try value(after: argument)
                guard let minutes = Double(raw), minutes.isFinite, minutes >= 0 else {
                    throw RROrderCorpusCLIError.invalidValue(option: argument, value: raw)
                }
                options.minimumDurationSeconds = Int((minutes * 60.0).rounded(.up))
            case "--format":
                let raw = try value(after: argument)
                guard let format = RROrderCorpusFormat(rawValue: raw.lowercased()) else {
                    throw RROrderCorpusCLIError.invalidValue(option: argument, value: raw)
                }
                options.format = format
            case "--output":
                options.outputPath = try value(after: argument)
            case "--include-device-id":
                options.includeDeviceID = true
            case "-h", "--help":
                options.showHelp = true
            default:
                throw RROrderCorpusCLIError.unknownOption(argument)
            }
            index += 1
        }

        guard options.fromTs <= options.toTs else {
            throw RROrderCorpusDatabaseError.invalidRange(from: options.fromTs, to: options.toTs)
        }
        return options
    }

    /// Accept either unix seconds or a UTC `YYYY-MM-DD` date. A date supplied to `--to` includes its full day.
    private static func parseBoundary(_ raw: String, endOfDay: Bool, option: String) throws -> Int {
        if let unix = Int(raw) { return unix }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false

        guard let date = formatter.date(from: raw) else {
            throw RROrderCorpusCLIError.invalidValue(option: option, value: raw)
        }
        let start = Int(date.timeIntervalSince1970)
        return endOfDay ? start + 86_399 : start
    }
}

@main
struct RROrderCorpusCommand {
    static func main() {
        do {
            let options = try RROrderCorpusCLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                print(helpText)
                return
            }

            let databasePath = try RROrderCorpusDatabasePath.resolve(explicitPath: options.databasePath)
            let database = try RROrderCorpusDatabase(path: databasePath)
            let result = try RROrderCorpusRunner.run(
                database: database,
                requestedDeviceIDs: options.deviceIDs,
                from: options.fromTs,
                to: options.toTs,
                sessionLimitPerDevice: options.sessionLimitPerDevice,
                minimumDurationSeconds: options.minimumDurationSeconds,
                includeDeviceID: options.includeDeviceID
            )
            let data = try RROrderCorpusEncoder.encode(result.records, format: options.format)
            try write(data, outputPath: options.outputPath)
            writeError(result.summary.text)
        } catch {
            writeError("rr-order-corpus: \(error)")
            writeError("Run rr-order-corpus --help for usage.")
            exit(2)
        }
    }

    private static func write(_ data: Data, outputPath: String?) throws {
        guard let outputPath, outputPath != "-" else {
            FileHandle.standardOutput.write(data)
            return
        }

        let expanded = RROrderCorpusDatabasePath.expandHome(
            outputPath,
            home: FileManager.default.homeDirectoryForCurrentUser.path
        )
        let url = URL(fileURLWithPath: expanded)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static let helpText = """
    Usage: rr-order-corpus [options]

    Runs the R-R emission-order audit once per stored NOOP sleep session and writes aggregate-only JSONL
    or CSV. The database is opened read-only. Raw R-R sequences are never emitted.

    Options:
      --db PATH                 NOOP SQLite path. Otherwise uses NOOP_DB_PATH or the standard app path.
      --device-id ID            Analyze one device. Repeat for multiple devices. Default: all eligible devices.
      --from VALUE              Earliest detected session start, as unix seconds or UTC YYYY-MM-DD.
      --to VALUE                Latest detected session start, as unix seconds or UTC YYYY-MM-DD.
      --limit N                 Maximum stored sessions per device. Default: 10000.
      --min-duration-min N      Exclude sessions shorter than N minutes. Default: 0.
      --format jsonl|csv        Output format. Default: jsonl.
      --output PATH             Write atomically to PATH. Use '-' or omit for stdout.
      --include-device-id       Include raw database device IDs. Default output uses device-001 pseudonyms only.
      -h, --help                Show this help.

    Examples:
      swift run rr-order-corpus --from 2026-07-01 --to 2026-08-16 --format csv --output rr-order.csv
      NOOP_DB_PATH=/path/to/whoop.sqlite swift run rr-order-corpus --device-id my-whoop
    """
}
