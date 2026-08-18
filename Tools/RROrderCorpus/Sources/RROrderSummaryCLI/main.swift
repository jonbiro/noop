import Darwin
import Foundation
import RROrderCorpusCore

enum RROrderSummaryCLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidValue(option: String, value: String)
    case unknownOption(String)

    var description: String {
        switch self {
        case .missingValue(let option): return "Missing value for \(option)."
        case .invalidValue(let option, let value): return "Invalid value for \(option): \(value)"
        case .unknownOption(let option): return "Unknown option: \(option)"
        }
    }
}

struct RROrderSummaryCLIOptions {
    var inputPath: String?
    var outputPath: String?
    var format = RROrderCorpusSummaryFormat.markdown
    var bootstrapIterations = 2_000
    var showHelp = false

    static func parse(_ arguments: [String]) throws -> Self {
        var options = Self(), index = 0
        func value(after option: String) throws -> String {
            guard index + 1 < arguments.count else { throw RROrderSummaryCLIError.missingValue(option) }
            index += 1; return arguments[index]
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--input": options.inputPath = try value(after: argument)
            case "--output": options.outputPath = try value(after: argument)
            case "--format":
                let raw = try value(after: argument).lowercased()
                guard let parsed = RROrderCorpusSummaryFormat(rawValue: raw) else { throw RROrderSummaryCLIError.invalidValue(option: argument, value: raw) }
                options.format = parsed
            case "--bootstrap-iterations":
                let raw = try value(after: argument)
                guard let n = Int(raw), n >= 0 && n <= 100_000 else { throw RROrderSummaryCLIError.invalidValue(option: argument, value: raw) }
                options.bootstrapIterations = n
            case "-h", "--help": options.showHelp = true
            default: throw RROrderSummaryCLIError.unknownOption(argument)
            }
            index += 1
        }
        return options
    }
}

@main
struct RROrderSummaryCommand {
    static func main() {
        do {
            let options = try RROrderSummaryCLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
            if options.showHelp { print(helpText); return }
            let input = try read(path: options.inputPath)
            let records = try RROrderCorpusSummaryInput.decodeJSONLines(input)
            let summary = try RROrderCorpusSummary.summarize(records, bootstrapIterations: options.bootstrapIterations)
            try write(try RROrderCorpusSummaryEncoder.encode(summary, format: options.format), path: options.outputPath)
            writeError("R-R summary v\(summary.schemaVersion): \(summary.recordCount) session(s), \(summary.deviceCount) device(s), \(summary.rmssd.delta.distribution?.count ?? 0) paired RMSSD comparison(s), \(summary.downstreamSensitivity.readinessHrv.evaluatedNights) readiness-HRV sensitivity night(s).")
        } catch {
            writeError("rr-order-summary: \(error)")
            writeError("Run rr-order-summary --help for usage.")
            exit(2)
        }
    }

    private static func read(path: String?) throws -> Data {
        guard let path, path != "-" else { return FileHandle.standardInput.readDataToEndOfFile() }
        let expanded = RROrderCorpusDatabasePath.expandHome(path, home: FileManager.default.homeDirectoryForCurrentUser.path)
        return try Data(contentsOf: URL(fileURLWithPath: expanded))
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
    Usage: rr-order-summary [options]

    Reads schema-v2 JSONL from rr-order-corpus and emits an aggregate-only Markdown or JSON report with:
    structural integrity/status flags, permutation severity, all core HRV deltas, cleaning behavior,
    deterministic bootstrap intervals, coverage/effect associations, strata, per-device summaries, and
    downstream HRV signal sensitivity. Raw device IDs and per-session observations are not included.

    Options:
      --input PATH                 Input JSONL. Use '-' or omit for stdin.
      --format markdown|json       Output format. Default: markdown.
      --output PATH                Write atomically to PATH. Use '-' or omit for stdout.
      --bootstrap-iterations N     Deterministic RMSSD-delta bootstrap iterations, 0..100000. Default: 2000.
      -h, --help                   Show this help.

    Examples:
      swift run rr-order-summary --input corpus.jsonl --output summary.md
      cat corpus.jsonl | swift run rr-order-summary --format json --bootstrap-iterations 5000
    """
}
