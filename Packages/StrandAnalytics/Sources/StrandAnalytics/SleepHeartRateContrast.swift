import Foundation

// SleepHeartRateContrast.swift - descriptive primary-sleep vs wake HR contrast.
//
// This is NOT another resting-heart-rate definition. NOOP already has a shipped
// floor-style RHR and a separately collected primary-session mean candidate.
// This engine compares explicitly supplied fixed-grid wake and primary-sleep HR
// windows and leaves those upstream RHR definitions untouched.
//
// The result is descriptive wellness context only. It deliberately provides no
// "dipper", "non-dipper", "riser", cardiovascular-risk, or diagnostic label.
public enum SleepHeartRateContrast {

    public static let validMinBpm: Double = 30
    public static let validMaxBpm: Double = 220
    public static let defaultMinimumValidSamples: Int = 30

    public struct Result: Equatable, Sendable {
        /// Arithmetic mean across valid fixed-grid wake epochs.
        public let wakeMeanBpm: Double
        /// Arithmetic mean across valid fixed-grid primary-sleep epochs.
        public let sleepMeanBpm: Double
        /// sleepMeanBpm - wakeMeanBpm. Negative means HR is lower during sleep.
        public let sleepMinusWakeBpm: Double
        /// 100 * (wakeMeanBpm - sleepMeanBpm) / wakeMeanBpm.
        /// Positive means lower HR during sleep; negative means higher HR.
        public let sleepReductionPercent: Double

        public let wakeValidSamples: Int
        public let wakeTotalSamples: Int
        public let wakeCoverage: Double
        public let sleepValidSamples: Int
        public let sleepTotalSamples: Int
        public let sleepCoverage: Double

        public init(
            wakeMeanBpm: Double,
            sleepMeanBpm: Double,
            sleepMinusWakeBpm: Double,
            sleepReductionPercent: Double,
            wakeValidSamples: Int,
            wakeTotalSamples: Int,
            wakeCoverage: Double,
            sleepValidSamples: Int,
            sleepTotalSamples: Int,
            sleepCoverage: Double
        ) {
            self.wakeMeanBpm = wakeMeanBpm
            self.sleepMeanBpm = sleepMeanBpm
            self.sleepMinusWakeBpm = sleepMinusWakeBpm
            self.sleepReductionPercent = sleepReductionPercent
            self.wakeValidSamples = wakeValidSamples
            self.wakeTotalSamples = wakeTotalSamples
            self.wakeCoverage = wakeCoverage
            self.sleepValidSamples = sleepValidSamples
            self.sleepTotalSamples = sleepTotalSamples
            self.sleepCoverage = sleepCoverage
        }
    }

    /// Compare fixed-grid wake and primary-sleep HR windows.
    ///
    /// Each array represents expected equal-duration epochs in the caller's
    /// chosen window. `nil` is an unobserved epoch, so valid/total is a real
    /// coverage fraction rather than a sample-cadence guess. Values outside
    /// 30...220 bpm are treated as invalid/unobserved for this metric.
    ///
    /// The engine uses an unweighted arithmetic mean across valid epochs. That
    /// is equivalent to a time-weighted mean only because the contract requires
    /// a fixed grid. Callers with irregular raw samples should first aggregate
    /// them onto a declared fixed cadence and retain that provenance.
    ///
    /// The minimum-valid-sample gate is intentionally parameterized. The
    /// default mirrors the provisional 30-valid-sample floor used by NOOP's
    /// primary-session mean RHR experiment, but this engine does not claim that
    /// 30 samples is a clinically validated coverage threshold.
    public static func evaluate(
        wakeHR: [Double?],
        primarySleepHR: [Double?],
        minimumValidSamples: Int = defaultMinimumValidSamples
    ) -> Result? {
        guard minimumValidSamples > 0,
              !wakeHR.isEmpty,
              !primarySleepHR.isEmpty else { return nil }

        let wake = summarize(wakeHR)
        let sleep = summarize(primarySleepHR)
        guard wake.validCount >= minimumValidSamples,
              sleep.validCount >= minimumValidSamples,
              wake.mean > 0 else { return nil }

        let delta = sleep.mean - wake.mean
        let reduction = 100.0 * (wake.mean - sleep.mean) / wake.mean
        guard delta.isFinite, reduction.isFinite else { return nil }

        return Result(
            wakeMeanBpm: wake.mean,
            sleepMeanBpm: sleep.mean,
            sleepMinusWakeBpm: delta,
            sleepReductionPercent: reduction,
            wakeValidSamples: wake.validCount,
            wakeTotalSamples: wakeHR.count,
            wakeCoverage: Double(wake.validCount) / Double(wakeHR.count),
            sleepValidSamples: sleep.validCount,
            sleepTotalSamples: primarySleepHR.count,
            sleepCoverage: Double(sleep.validCount) / Double(primarySleepHR.count)
        )
    }

    private struct Summary {
        let mean: Double
        let validCount: Int
    }

    private static func summarize(_ values: [Double?]) -> Summary {
        var sum = 0.0
        var count = 0
        for item in values {
            guard let value = item,
                  value.isFinite,
                  value >= validMinBpm,
                  value <= validMaxBpm else { continue }
            sum += value
            count += 1
        }
        return Summary(mean: count > 0 ? sum / Double(count) : 0, validCount: count)
    }
}
