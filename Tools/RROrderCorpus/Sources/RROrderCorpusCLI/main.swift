import Darwin
import Foundation
import RROrderCorpusCore

enum RROrderCorpusCLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidValue(option: String, value: String)
    case unknownOption(String)
    case conflictingStdout

    var description: String {
        switch self {
        case .missingValue(let option): return "Missing value for \(option)."
        case .invalidValue(let option, let value): return "Invalid value for \(option): \(value)"
        case .unknownOption(let option): return "Unknown option: \(option)"
        case .conflictingStdout: return "Corpus records and summary cannot both be written to stdout. Give either --output or --summary a file path."
        }
    }
}

struct RROrderCorpusCLIOptions {
    var databasePath: String?
    var deviceIDs: [String] = []
    var fromTs = 0
    var toTs = Int.max
    var sessionLimitPerDevice = 10_000
    var minimumDurationSeconds = 120 * 60
    var format = RROrderCorpusFormat.jsonl
    var outputPath: String?
    var includeDeviceID = false
    var summaryPath: String?
    var summaryFormat = RROrderCorpusSummaryFormat.markdown
    var bootstrapIterations = 2_000
    var showHelp = false

    static func parse(_ arguments: [String]) throws -> Self {
        var options = Self(), index = 0
        func value(after option: String) throws -> String {
            guard index + 1 < arguments.count else { throw RROrderCorpusCLIError.missingValue(option) }
            index += 1; return arguments[index]
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--db": options.databasePath = try value(after: argument)
            case "--device-id":
                let id = try value(after: argument).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else { throw RROrderCorpusCLIError.invalidValue(option: argument, value: id) }
                options.deviceIDs.append(id)
            case "--from": options.fromTs = try parseBoundary(try value(after: argument), endOfDay: false, option: argument)
            case "--to": options.toTs = try parseBoundary(try value(after: argument), endOfDay: true, option: argument)
            case "--limit":
                let raw = try value(after: argument)
                guard let n = Int(raw), n > 0 else { throw RROrderCorpusCLIError.invalidValue(option: argument, value: raw) }
                options.sessionLimitPerDevice = n
            case "--min-duration-min":
                let raw = try value(after: argument)
                guard let minutes = Double(raw), minutes.isFinite, minutes >= 0 else {
                    throw RROrderCorpusCLIError.invalidValue(option: argument, value: raw)
                }
                options.minimumDurationSeconds = Int((minutes * 60).rounded(.up))
            case "--format":
                let raw = try value(after: argument).lowercased()
                guard let parsed = RROrderCorpusFormat(rawValue: raw) else { throw RROrderCorpusCLIError.invalidValue(option: argument, value: raw) }
                options.format = parsed
            case "--output": options.outputPath = try value(after: argument)
            case "--include-device-id": options.includeDeviceID = true
            case "--summary": options.summaryPath = try value(after: argument)
            case "--summary-format":
                let raw = try value(after: argument).lowercased()
                guard let parsed = RROrderCorpusSummaryFormat(rawValue: raw) else { throw RROrderCorpusCLIError.invalidValue(option: argument, value: raw) }
                options.summaryFormat = parsed
            case "--bootstrap-iterations":
                let raw = try value(after: argument)
                guard let n = Int(raw), n >= 0 && n <= 100_000 else { throw RROrderCorpusCLIError.invalidValue(option: argument, value: raw) }
                options.bootstrapIterations = n
            case "-h", "--help": options.showHelp = true
            default: throw RROrderCorpusCLIError.unknownOption(argument)
            }
            index += 1
        }
        guard options.fromTs <= options.toTs else { throw RROrderCorpusDatabaseError.invalidRange(from: options.fromTs, to: options.toTs) }
        if options.summaryPath != nil && isStdout(options.outputPath) && isStdout(options.summaryPath) { throw RROrderCorpusCLIError.conflictingStdout }
        return options
    }

    private static func isStdout(_ path: String?) -> Bool { path == nil || path == "-" }

    private static func parseBoundary(_ raw: String, endOfDay: Bool, option: String) throws -> Int {
        if let unix = Int(raw) { return unix }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: raw) else { throw RROrderCorpusCLIError.invalidValue(option: option, value: raw) }
        let start = Int(date.timeIntervalSince1970)
        return endOfDay ? start + 86_399 : start
    }
}

@main
struct RROrderCorpusCommand {
    static func main() {
        do {
            let options = try RROrderCorpusCLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
            if options.showHelp { print(helpText); return }

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
            try write(try RROrderCorpusEncoder.encode(result.records, format: options.format), path: options.outputPath)

            if let summaryPath = options.summaryPath {
                let summary = try RROrderCorpusSummary.summarize(result.records, bootstrapIterations: options.bootstrapIterations)
                try write(try RROrderCorpusSummaryEncoder.encode(summary, format: options.summaryFormat), path: summaryPath)
            }
            writeError("database user_version=\(database.userVersion); \(result.summary.text)")
        } catch {
            writeError("rr-order-corpus: \(error)")
            writeError("Run rr-order-corpus --help for usage.")
            exit(2)
        }
    }

    private static func write(_ data: Data, path: String?) throws {
        guard let path, path != "-" else { FileHandle.standardOutput.write(data); return }
        let expanded = RROrderCorpusDatabasePath.expandHome(path, home: FileManager.default.homeDirectoryForCurrentUser.path)
        let url = URL(fileURLWithPath: expanded)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func writeError(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }

    private static let helpText = """
    Usage: rr-order-corpus [options]

    Runs the R-R ordering integrity audit once per stored NOOP sleep session. SQLite is opened read-only;
    raw R-R sequences are never emitted. Schema-v2 JSONL/CSV includes structural provenance, permutation
    severity, cleaning diagnostics, all core HRV counterfactuals, and scoring-filter exclusion counts.

    Options:
      --db PATH                    NOOP SQLite path. Otherwise uses NOOP_DB_PATH or the standard app path.
      --device-id ID               Analyze one device; repeat for multiple. Default: all eligible devices.
      --from VALUE                 Earliest detected start, unix seconds or UTC YYYY-MM-DD.
      --to VALUE                   Latest detected start, unix seconds or UTC YYYY-MM-DD.
      --limit N                    Maximum sessions per device. Default: 10000.
      --min-duration-min N         Minimum session duration. Default: 120; use 0 to include naps/short sessions.
      --format jsonl|csv           Record format. Default: jsonl.
      --output PATH                Record output. Use '-' or omit for stdout.
      --include-device-id          Include raw database device IDs; default is device-001 pseudonyms only.
      --summary PATH               Also write an aggregate summary in the same run.
      --summary-format markdown|json  Aggregate format. Default: markdown.
      --bootstrap-iterations N     Deterministic RMSSD-delta bootstrap iterations, 0..100000. Default: 2000.
      -h, --help                   Show this help.

    Examples:
      swift run rr-order-corpus --from 2026-07-01 --to 2026-08-16 --output corpus.jsonl --summary summary.md
      swift run rr-order-corpus --min-duration-min 0 --format csv --output all-sessions.csv
    """
}
