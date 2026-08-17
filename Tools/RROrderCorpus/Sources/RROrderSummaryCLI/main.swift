import Darwin
import Foundation
import RROrderCorpusCore

enum RROrderSummaryCLIError: Error, CustomStringConvertible {
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

struct RROrderSummaryCLIOptions {
    var inputPath: String?
    var outputPath: String?
    var format = RROrderCorpusSummaryFormat.markdown
    var showHelp = false

    static func parse(_ arguments: [String]) throws -> Self {
        var options = Self()
        var index = 0

        func value(after option: String) throws -> String {
            let valueIndex = index + 1
            guard valueIndex < arguments.count else { throw RROrderSummaryCLIError.missingValue(option) }
            index = valueIndex
            return arguments[valueIndex]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--input":
                options.inputPath = try value(after: argument)
            case "--output":
                options.outputPath = try value(after: argument)
            case "--format":
                let raw = try value(after: argument).lowercased()
                guard let format = RROrderCorpusSummaryFormat(rawValue: raw) else {
                    throw RROrderSummaryCLIError.invalidValue(option: argument, value: raw)
                }
                options.format = format
            case "-h", "--help":
                options.showHelp = true
            default:
                throw RROrderSummaryCLIError.unknownOption(argument)
            }
            index += 1
        }
        return options
    }
}

struct RROrderSummaryCommand {
    static func run() {
        do {
            let options = try RROrderSummaryCLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                print(helpText)
                return
            }

            let input = try read(path: options.inputPath)
            let records = try RROrderCorpusSummaryInput.decodeJSONLines(input)
            let summary = try RROrderCorpusSummary.summarize(records)
            let output = try RROrderCorpusSummaryEncoder.encode(summary, format: options.format)
            try write(output, path: options.outputPath)
            writeError(
                "R-R summary: \(summary.recordCount) session(s), \(summary.deviceCount) device(s), "
                    + "\(summary.hrv.pairedProductionCount) paired production RMSSD comparison(s)."
            )
        } catch {
            writeError("rr-order-summary: \(error)")
            writeError("Run rr-order-summary --help for usage.")
            exit(2)
        }
    }

    private static func read(path: String?) throws -> Data {
        guard let path, path != "-" else {
            return FileHandle.standardInput.readDataToEndOfFile()
        }
        let expanded = RROrderCorpusDatabasePath.expandHome(
            path,
            home: FileManager.default.homeDirectoryForCurrentUser.path
        )
        return try Data(contentsOf: URL(fileURLWithPath: expanded))
    }

    private static func write(_ data: Data, path: String?) throws {
        guard let path, path != "-" else {
            FileHandle.standardOutput.write(data)
            return
        }
        let expanded = RROrderCorpusDatabasePath.expandHome(
            path,
            home: FileManager.default.homeDirectoryForCurrentUser.path
        )
        let url = URL(fileURLWithPath: expanded)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static let helpText = """
    Usage: rr-order-summary [options]

    Reads schema-v1 JSONL from rr-order-corpus and emits an aggregate-only Markdown or JSON summary.
    Duplicate observations fail closed so concatenating the same run cannot silently double-weight a night.
    Raw device IDs and per-session observations are never included in the summary.

    Options:
      --input PATH              Input JSONL path. Use '-' or omit for stdin.
      --format markdown|json    Summary format. Default: markdown.
      --output PATH             Write atomically to PATH. Use '-' or omit for stdout.
      -h, --help                Show this help.

    Examples:
      swift run rr-order-corpus --format jsonl --output corpus.jsonl
      swift run rr-order-summary --input corpus.jsonl --output corpus-summary.md
      cat corpus.jsonl | swift run rr-order-summary --format json
    """
}

RROrderSummaryCommand.run()
