import StrandAnalytics

// Tool-local adapter to the shipped NOOP raw-RR API. Keeping this shim in the
// benchmark target makes the comparison explicit without adding any alias to
// production StrandAnalytics.
extension HRVAnalyzer {
    static func analyzeRaw(_ rawRR: [Double]) -> HRVResult {
        analyze(rawRR: rawRR)
    }
}
