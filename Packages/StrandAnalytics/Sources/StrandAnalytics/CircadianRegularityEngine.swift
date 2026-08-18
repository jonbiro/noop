import Foundation

// CircadianRegularityEngine.swift - deterministic sleep-timing regularity and
// social-clock metrics. Additive to CircadianEngine: this file does not change
// body-clock phase estimation, Vitality, Readiness, or any headline score.
//
// Independent implementations of published, transparent methods:
//   * Phillips-style Sleep Regularity Index (SRI): sleep/wake agreement at
//     timestamps separated by 24 h, scaled so random timing is 0 and perfect
//     day-to-day agreement is 100.
//   * Social jetlag: shortest signed circular difference between free-day and
//     work-day mid-sleep (Wittmann/Roenneberg framework).
//   * Sleep-debt-corrected free-day mid-sleep: the mathematical substrate of
//     MCTQ MSFsc. Full MCTQ chronotyping additionally requires an unconstrained
//     free-day wake (for example no alarm constraint), which this pure engine
//     cannot infer from wearable timing alone.
//
// WELLNESS / BEHAVIOURAL AWARENESS ONLY. These are schedule descriptors, not
// diagnoses. Missing epochs are never treated as wake: SRI reports only pairs
// where both states are observed and exposes the resulting coverage.
public enum CircadianRegularityEngine {

    public static let secondsPerDay: Int = 86_400
    public static let defaultSriLagSeconds: Int = secondsPerDay
    public static let minimumNightsPerSocialSide: Int = 2
    private static let circularResultantEpsilon: Double = 1e-9

    // MARK: - Sleep Regularity Index

    public struct SleepRegularityResult: Equatable, Sendable {
        /// Phillips SRI. Perfect agreement is 100; chance-level agreement in a
        /// random sleep/wake schedule is 0. The theoretical lower bound is -100.
        public let score: Double
        /// Pairs where both endpoints were observed and therefore comparable.
        public let comparablePairs: Int
        /// All pairs the supplied span could have contributed if fully observed.
        public let possiblePairs: Int
        /// comparablePairs / possiblePairs, 0...1. This is data coverage, not
        /// physiological confidence.
        public let coverage: Double
        /// Number of equal-state pairs among comparablePairs.
        public let matchingPairs: Int
        /// Span represented by the epoch array, in days.
        public let spanDays: Double

        public init(score: Double, comparablePairs: Int, possiblePairs: Int,
                    coverage: Double, matchingPairs: Int, spanDays: Double) {
            self.score = score
            self.comparablePairs = comparablePairs
            self.possiblePairs = possiblePairs
            self.coverage = coverage
            self.matchingPairs = matchingPairs
            self.spanDays = spanDays
        }
    }

    /// Sleep Regularity Index over an epoch-aligned sleep/wake series.
    ///
    /// `states` uses true = asleep, false = awake, nil = unobserved. The lag
    /// defaults to 24 h and must be an integer number of epochs. A result is
    /// returned only when at least one pair is genuinely comparable; missing
    /// endpoints reduce coverage rather than being imputed.
    ///
    /// SRI = -100 + 200 * matchingPairs / comparablePairs.
    public static func sleepRegularityIndex(
        states: [Bool?],
        epochSeconds: Int,
        lagSeconds: Int = defaultSriLagSeconds
    ) -> SleepRegularityResult? {
        guard epochSeconds > 0,
              lagSeconds > 0,
              lagSeconds % epochSeconds == 0 else { return nil }
        let lagEpochs = lagSeconds / epochSeconds
        guard lagEpochs > 0, states.count > lagEpochs else { return nil }

        let possible = states.count - lagEpochs
        var comparable = 0
        var matching = 0
        for i in 0..<possible {
            guard let a = states[i], let b = states[i + lagEpochs] else { continue }
            comparable += 1
            if a == b { matching += 1 }
        }
        guard comparable > 0 else { return nil }

        let agreement = Double(matching) / Double(comparable)
        let score = -100.0 + 200.0 * agreement
        let coverage = Double(comparable) / Double(possible)
        let spanDays = Double(states.count) * Double(epochSeconds) / Double(secondsPerDay)
        return SleepRegularityResult(
            score: score,
            comparablePairs: comparable,
            possiblePairs: possible,
            coverage: coverage,
            matchingPairs: matching,
            spanDays: spanDays
        )
    }

    // MARK: - Social jetlag

    public struct SocialJetLagResult: Equatable, Sendable {
        /// Signed shortest arc, free-day minus work-day mid-sleep, in
        /// (-12, +12]. Positive means free days run later.
        public let signedHours: Double
        public let absoluteHours: Double
        public let freeDayMidSleepHour: Double
        public let workdayMidSleepHour: Double
        public let freeDayNights: Int
        public let workdayNights: Int

        public init(signedHours: Double, absoluteHours: Double,
                    freeDayMidSleepHour: Double, workdayMidSleepHour: Double,
                    freeDayNights: Int, workdayNights: Int) {
            self.signedHours = signedHours
            self.absoluteHours = absoluteHours
            self.freeDayMidSleepHour = freeDayMidSleepHour
            self.workdayMidSleepHour = workdayMidSleepHour
            self.freeDayNights = freeDayNights
            self.workdayNights = workdayNights
        }
    }

    /// Social jetlag from LOCAL clock-time mid-sleep hours.
    ///
    /// The representative midpoint on each side is a circular median, not a
    /// linear median, so 23:50 and 00:10 remain close across midnight. Returns
    /// nil when either side has too few nights, contains a non-finite value, or
    /// has no meaningful circular direction (for example an exactly antipodal
    /// sample).
    public static func socialJetLag(
        freeDayMidSleepHours: [Double],
        workdayMidSleepHours: [Double],
        minimumNightsPerSide: Int = minimumNightsPerSocialSide
    ) -> SocialJetLagResult? {
        guard minimumNightsPerSide > 0,
              freeDayMidSleepHours.count >= minimumNightsPerSide,
              workdayMidSleepHours.count >= minimumNightsPerSide,
              freeDayMidSleepHours.allSatisfy({ $0.isFinite }),
              workdayMidSleepHours.allSatisfy({ $0.isFinite }),
              let free = circularMedianHour(freeDayMidSleepHours),
              let work = circularMedianHour(workdayMidSleepHours) else { return nil }

        let signed = signedCircularDifference(free, work)
        return SocialJetLagResult(
            signedHours: signed,
            absoluteHours: abs(signed),
            freeDayMidSleepHour: free,
            workdayMidSleepHour: work,
            freeDayNights: freeDayMidSleepHours.count,
            workdayNights: workdayMidSleepHours.count
        )
    }

    // MARK: - Sleep-debt-corrected free-day midpoint

    public struct CorrectedMidSleepResult: Equatable, Sendable {
        /// Circular-median free-day mid-sleep before sleep-debt correction.
        public let freeDayMidSleepHour: Double
        /// Sleep-debt-corrected free-day mid-sleep, wrapped to [0, 24).
        public let correctedMidSleepHour: Double
        /// Median free-day sleep duration used by this deterministic summary.
        public let medianFreeDaySleepDurationHours: Double
        public let averageWorkdaySleepDurationHours: Double
        public let averageWeekSleepDurationHours: Double
        /// Amount subtracted from free-day mid-sleep. Per the standard MSFsc
        /// rule, this is zero unless free-day sleep exceeds workday sleep.
        public let oversleepCorrectionHours: Double
        public let freeDayNights: Int

        public init(freeDayMidSleepHour: Double, correctedMidSleepHour: Double,
                    medianFreeDaySleepDurationHours: Double,
                    averageWorkdaySleepDurationHours: Double,
                    averageWeekSleepDurationHours: Double,
                    oversleepCorrectionHours: Double, freeDayNights: Int) {
            self.freeDayMidSleepHour = freeDayMidSleepHour
            self.correctedMidSleepHour = correctedMidSleepHour
            self.medianFreeDaySleepDurationHours = medianFreeDaySleepDurationHours
            self.averageWorkdaySleepDurationHours = averageWorkdaySleepDurationHours
            self.averageWeekSleepDurationHours = averageWeekSleepDurationHours
            self.oversleepCorrectionHours = oversleepCorrectionHours
            self.freeDayNights = freeDayNights
        }
    }

    /// Sleep-debt-corrected mid-sleep on free days, the timing substrate used by
    /// MCTQ MSFsc.
    ///
    /// Mid-sleep is summarized circularly. Sleep duration is linear. Standard
    /// MSFsc logic applies a correction only when free-day sleep duration exceeds
    /// workday sleep duration. In that case, half of the excess of free-day
    /// sleep over average weekly sleep is subtracted from free-day mid-sleep.
    ///
    /// This pure timing API does not claim a chronotype diagnosis. A full MCTQ
    /// chronotype interpretation also requires knowing that free-day wake timing
    /// was not constrained by an alarm or equivalent schedule requirement.
    public static func correctedFreeDayMidSleep(
        freeDayMidSleepHours: [Double],
        freeDaySleepDurationHours: [Double],
        averageWorkdaySleepDurationHours: Double,
        averageWeekSleepDurationHours: Double,
        minimumFreeDays: Int = minimumNightsPerSocialSide
    ) -> CorrectedMidSleepResult? {
        guard minimumFreeDays > 0,
              freeDayMidSleepHours.count >= minimumFreeDays,
              freeDayMidSleepHours.count == freeDaySleepDurationHours.count,
              freeDayMidSleepHours.allSatisfy({ $0.isFinite }),
              freeDaySleepDurationHours.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 24 }),
              averageWorkdaySleepDurationHours.isFinite,
              averageWorkdaySleepDurationHours > 0,
              averageWorkdaySleepDurationHours <= 24,
              averageWeekSleepDurationHours.isFinite,
              averageWeekSleepDurationHours > 0,
              averageWeekSleepDurationHours <= 24,
              let midpoint = circularMedianHour(freeDayMidSleepHours),
              let freeDuration = median(freeDaySleepDurationHours) else { return nil }

        let correction: Double
        if freeDuration > averageWorkdaySleepDurationHours {
            correction = max(0, (freeDuration - averageWeekSleepDurationHours) / 2.0)
        } else {
            correction = 0
        }
        return CorrectedMidSleepResult(
            freeDayMidSleepHour: midpoint,
            correctedMidSleepHour: wrap24(midpoint - correction),
            medianFreeDaySleepDurationHours: freeDuration,
            averageWorkdaySleepDurationHours: averageWorkdaySleepDurationHours,
            averageWeekSleepDurationHours: averageWeekSleepDurationHours,
            oversleepCorrectionHours: correction,
            freeDayNights: freeDayMidSleepHours.count
        )
    }

    // MARK: - Circular helpers

    /// Circular mean direction of clock-hours. Internal for parity tests.
    static func circularMeanHour(_ hours: [Double]) -> Double? {
        guard !hours.isEmpty, hours.allSatisfy({ $0.isFinite }) else { return nil }
        var sx = 0.0
        var sy = 0.0
        for hour in hours {
            let angle = wrap24(hour) * Double.pi / 12.0
            sx += cos(angle)
            sy += sin(angle)
        }
        guard hypot(sx, sy) >= circularResultantEpsilon else { return nil }
        return wrap24(atan2(sy, sx) * 12.0 / Double.pi)
    }

    /// Circular median = ordinary median after unwrapping the sample around its
    /// circular mean direction, then wrapping the result back to the clock.
    static func circularMedianHour(_ hours: [Double]) -> Double? {
        guard let anchor = circularMeanHour(hours) else { return nil }
        let unwrapped = hours.map { anchor + signedCircularDifference($0, anchor) }
        guard let m = median(unwrapped) else { return nil }
        return wrap24(m)
    }

    /// Shortest signed arc `a - b` in (-12, +12].
    static func signedCircularDifference(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 24.0)
        if d < 0 { d += 24.0 }
        if d > 12.0 { d -= 24.0 }
        return d
    }

    static func wrap24(_ hour: Double) -> Double {
        var h = hour.truncatingRemainder(dividingBy: 24.0)
        if h < 0 { h += 24.0 }
        return h
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }
}
