/// Availability-aware facade for the existing opt-in HRV Readiness experiment.
///
/// Existing `HRVReadiness.evaluate` remains unchanged for source compatibility. New consumers that need to
/// explain nil/calibration state can use this wrapper and receive the exact same result plus a stable reason.
public struct HRVReadinessEvaluation: Equatable, Sendable {
    public let result: HRVReadinessResult?
    public let availability: MetricAvailability
    public let validNightCount: Int

    public init(result: HRVReadinessResult?, availability: MetricAvailability, validNightCount: Int) {
        self.result = result
        self.availability = availability
        self.validNightCount = validNightCount
    }
}

public extension HRVReadiness {
    static func evaluateWithAvailability(avgHrv: [Double?]) -> HRVReadinessEvaluation {
        let cfg = Baselines.hrvCfg
        let validNightCount = avgHrv.reduce(into: 0) { count, value in
            if let value, cfg.minVal <= value && value <= cfg.maxVal { count += 1 }
        }
        let result = evaluate(avgHrv: avgHrv)

        if let result {
            // HRV Readiness is explicitly an opt-in, not-yet-validated experiment in the existing engine.
            // Preserve that truth in the availability envelope instead of upgrading it to generic "available".
            return HRVReadinessEvaluation(
                result: result,
                availability: .experimentalUnvalidated("hrv_readiness"),
                validNightCount: validNightCount
            )
        }

        return HRVReadinessEvaluation(
            result: nil,
            availability: .needBaseline(have: validNightCount, need: minNights),
            validNightCount: validNightCount
        )
    }
}
