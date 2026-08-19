import Foundation

// NonparametricCircadianEngine.swift - fixed-grid circadian rhythm descriptors.
//
// Additive to CircadianEngine and CircadianRegularityEngine. This engine does
// not change phase estimation, sleep staging, Vitality, Readiness, or any
// headline score.
//
// Implements the standard nonparametric rest-activity rhythm family:
//   * IS: interdaily stability, coupling of the signal to time of day.
//   * IV: intradaily variability, fragmentation across successive epochs.
//   * M10: mean of the most-active 10 contiguous hours of the average day.
//   * L5: mean of the least-active 5 contiguous hours of the average day.
//   * RA: relative amplitude = (M10 - L5) / (M10 + L5).
//
// The strongest validation literature is for actigraphy/activity. The math is
// signal-generic, but callers that use heart rate as the input must label that
// substrate honestly rather than presenting it as actigraphy-equivalent.
public enum NonparametricCircadianEngine {

    public static let minimumDays: Int = 2

    public struct Result: Equatable, Sendable {
        public let interdailyStability: Double
        public let intradailyVariability: Double
        public let m10: Double
        public let l5: Double
        public let relativeAmplitude: Double
        public let m10StartEpoch: Int
        public let l5StartEpoch: Int
        public let m10StartHour: Double
        public let l5StartHour: Double
        /// Number of complete nominal days represented by the fixed grid.
        /// Consumers decide how much history they require for a particular use;
        /// this pure engine does not invent an "established" threshold.
        public let daysObserved: Int
        public let epochsPerDay: Int

        public init(
            interdailyStability: Double,
            intradailyVariability: Double,
            m10: Double,
            l5: Double,
            relativeAmplitude: Double,
            m10StartEpoch: Int,
            l5StartEpoch: Int,
            m10StartHour: Double,
            l5StartHour: Double,
            daysObserved: Int,
            epochsPerDay: Int
        ) {
            self.interdailyStability = interdailyStability
            self.intradailyVariability = intradailyVariability
            self.m10 = m10
            self.l5 = l5
            self.relativeAmplitude = relativeAmplitude
            self.m10StartEpoch = m10StartEpoch
            self.l5StartEpoch = l5StartEpoch
            self.m10StartHour = m10StartHour
            self.l5StartHour = l5StartHour
            self.daysObserved = daysObserved
            self.epochsPerDay = epochsPerDay
        }
    }

    /// Compute nonparametric circadian metrics over consecutive complete days.
    ///
    /// - Parameters:
    ///   - signal: Epoch-binned activity-like values in chronological order.
    ///     `nil` means unobserved. This first production primitive refuses to
    ///     impute missing epochs because the published IS/IV formulas assume a
    ///     complete fixed grid.
    ///   - epochsPerDay: Number of equal epochs in each nominal 24 h day. Must
    ///     be divisible by 24 so the 5 h and 10 h windows are exact integers.
    ///
    /// Returns nil for partial days, fewer than two complete days, missing or
    /// non-finite values, negative values, or a constant/zero-variance signal.
    /// DST-short/long local days must be normalized by the caller onto a
    /// declared 24 h grid rather than silently compressed here.
    public static func evaluate(signal: [Double?], epochsPerDay: Int) -> Result? {
        guard epochsPerDay > 0,
              epochsPerDay.isMultiple(of: 24),
              signal.count >= minimumDays * epochsPerDay,
              signal.count.isMultiple(of: epochsPerDay) else { return nil }

        var x: [Double] = []
        x.reserveCapacity(signal.count)
        for item in signal {
            guard let value = item, value.isFinite, value >= 0 else { return nil }
            x.append(value)
        }

        let n = x.count
        let days = n / epochsPerDay
        let grandMean = x.reduce(0, +) / Double(n)

        var totalSS = 0.0
        for value in x {
            let d = value - grandMean
            totalSS += d * d
        }
        guard totalSS > 0, totalSS.isFinite else { return nil }

        // Average day profile. The fixed-grid contract guarantees equal counts
        // for every epoch-of-day slot.
        var profile = [Double](repeating: 0, count: epochsPerDay)
        for i in 0..<n {
            profile[i % epochsPerDay] += x[i]
        }
        for i in 0..<epochsPerDay {
            profile[i] /= Double(days)
        }

        // Interdaily stability: between-time-of-day variance relative to total
        // variance. A perfectly repeated daily profile evaluates to 1.
        var profileSS = 0.0
        for value in profile {
            let d = value - grandMean
            profileSS += d * d
        }
        let rawIS = Double(n) * profileSS / (Double(epochsPerDay) * totalSS)
        let isValue = min(1.0, max(0.0, rawIS))

        // Intradaily variability: successive-difference variance relative to
        // overall variance. Do not clamp the upper bound: IV can exceed 2 for
        // strongly alternating/non-Gaussian sequences.
        var successiveSS = 0.0
        for i in 1..<n {
            let d = x[i] - x[i - 1]
            successiveSS += d * d
        }
        let ivValue = Double(n) * successiveSS / (Double(n - 1) * totalSS)
        guard ivValue.isFinite, ivValue >= 0 else { return nil }

        let m10Epochs = epochsPerDay * 10 / 24
        let l5Epochs = epochsPerDay * 5 / 24
        let m10Window = bestCircularWindow(profile: profile, length: m10Epochs, maximize: true)
        let l5Window = bestCircularWindow(profile: profile, length: l5Epochs, maximize: false)

        let denominator = m10Window.mean + l5Window.mean
        guard denominator > 0 else { return nil }
        let rawRA = (m10Window.mean - l5Window.mean) / denominator
        let raValue = min(1.0, max(0.0, rawRA))
        let hoursPerEpoch = 24.0 / Double(epochsPerDay)

        return Result(
            interdailyStability: isValue,
            intradailyVariability: ivValue,
            m10: m10Window.mean,
            l5: l5Window.mean,
            relativeAmplitude: raValue,
            m10StartEpoch: m10Window.start,
            l5StartEpoch: l5Window.start,
            m10StartHour: Double(m10Window.start) * hoursPerEpoch,
            l5StartHour: Double(l5Window.start) * hoursPerEpoch,
            daysObserved: days,
            epochsPerDay: epochsPerDay
        )
    }

    private struct Window {
        let mean: Double
        let start: Int
    }

    /// Deterministic circular best-window search. Ties keep the earliest epoch
    /// index so Swift/Kotlin output is stable and chart annotations do not jump.
    private static func bestCircularWindow(profile: [Double], length: Int, maximize: Bool) -> Window {
        precondition(!profile.isEmpty && length > 0 && length <= profile.count)
        var bestMean: Double?
        var bestStart = 0
        for start in 0..<profile.count {
            var sum = 0.0
            for offset in 0..<length {
                sum += profile[(start + offset) % profile.count]
            }
            let mean = sum / Double(length)
            if bestMean == nil || (maximize ? mean > bestMean! : mean < bestMean!) {
                bestMean = mean
                bestStart = start
            }
        }
        return Window(mean: bestMean!, start: bestStart)
    }
}
