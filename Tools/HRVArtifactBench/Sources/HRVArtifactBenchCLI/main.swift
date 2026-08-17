import Foundation
import HRVArtifactBenchCore

@main
struct HRVArtifactBenchCommand {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let json = args.contains("--json")
        let help = args.contains("--help") || args.contains("-h")
        let unknown = args.filter { !["--json", "--help", "-h"].contains($0) }
        if help {
            print("""
            Usage: hrv-artifact-bench [--json]

            Runs deterministic synthetic R-R artifact scenarios through NOOP's current HRVAnalyzer and a
            tool-only Lipponen-Tarvainen-style candidate. Default output is Markdown; --json emits sorted JSON.

            This executable does not modify the database and the candidate is not used by production analytics.
            """)
            return
        }
        guard unknown.isEmpty else {
            fputs("Unknown option: \(unknown[0])\n", stderr)
            exit(2)
        }

        let report = HRVArtifactBenchmark.run()
        let data = json ? try HRVArtifactBenchmarkEncoder.json(report) : HRVArtifactBenchmarkEncoder.markdown(report)
        FileHandle.standardOutput.write(data)
    }
}
