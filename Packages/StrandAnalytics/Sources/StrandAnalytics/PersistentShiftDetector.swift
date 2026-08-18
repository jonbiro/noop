import Foundation

// PersistentShiftDetector.swift - generic one-sided longitudinal baseline-shift detector.
//
// Pure, deterministic, domain-neutral CUSUM over a robust personal baseline.
// It does not name illness, overtraining, stress, or any other cause. A caller
// chooses whether an upward or downward shift is meaningful for its metric and
// combines this temporal evidence with the domain's existing context/confounders.
public enum PersistentShiftDetector {

    public static let defaultBaselineWindow: Int = 28
    public static let defaultMinimumBaseline: Int = 7
    public static let defaultReferenceK: Double = 0.5
    public static let defaultDecisionH: Double = 4.0
    public static let defaultPersistObservations: Int = 2
    public static let defaultRecoveryZ: Double = 0.5
    public static let defaultRecoveryObservations: Int = 2
    /// Makes MAD comparable to standard deviation for a normal distribution.
    public static let normalizedMADScale: Double = 1.482602218505602

    public enum Direction: String, Equatable, Sendable {
        case upper
        case lower
    }

    public enum State: String, Equatable, Sendable {
        case missing
        case calibrating
        case degenerateBaseline
        case normal
        case watch
        case sustained
    }

    public struct Point: Equatable, Sendable {
        public let index: Int
        public let state: State
        /// Standardized deviation oriented so positive always means movement
        /// in the requested shift direction.
        public let orientedZ: Double?
        public let cusum: Double?
        public let baselineMedian: Double?
        public let baselineScale: Double?
        public let baselineCount: Int
        public let observed: Bool

        public init(index: Int, state: State, orientedZ: Double?, cusum: Double?,
                    baselineMedian: Double?, baselineScale: Double?,
                    baselineCount: Int, observed: Bool) {
            self.index = index
            self.state = state
            self.orientedZ = orientedZ
            self.cusum = cusum
            self.baselineMedian = baselineMedian
            self.baselineScale = baselineScale
            self.baselineCount = baselineCount
            self.observed = observed
        }
    }

    /// Run a one-sided Page-style CUSUM over a time-ordered optional series.
    ///
    /// `nil` is a missing observation. It emits `.missing` and neither advances
    /// nor resets the detector. Non-nil non-finite values poison the input and
    /// return nil rather than being silently treated as missing.
    ///
    /// The trailing baseline uses the median plus normalized MAD. If MAD is
    /// exactly zero, sample SD is used as a fallback. If both are zero, the
    /// point is `.degenerateBaseline` and does not accumulate a fabricated z.
    public static func evaluate(
        values: [Double?],
        direction: Direction,
        baselineWindow: Int = defaultBaselineWindow,
        minimumBaseline: Int = defaultMinimumBaseline,
        referenceK: Double = defaultReferenceK,
        decisionH: Double = defaultDecisionH,
        persistObservations: Int = defaultPersistObservations,
        recoveryZ: Double = defaultRecoveryZ,
        recoveryObservations: Int = defaultRecoveryObservations
    ) -> [Point]? {
        guard baselineWindow >= minimumBaseline,
              minimumBaseline >= 2,
              referenceK.isFinite, referenceK >= 0,
              decisionH.isFinite, decisionH > 0,
              persistObservations > 0,
              recoveryZ.isFinite,
              recoveryObservations > 0,
              values.allSatisfy({ $0 == nil || $0!.isFinite }) else { return nil }

        var out: [Point] = []
        out.reserveCapacity(values.count)
        var cusum = 0.0
        var alertRun = 0
        var recoveryRun = 0

        for i in values.indices {
            let lo = max(0, i - baselineWindow)
            var baseline: [Double] = []
            baseline.reserveCapacity(i - lo)
            if lo < i {
                for j in lo..<i {
                    if let value = values[j] { baseline.append(value) }
                }
            }

            guard let current = values[i] else {
                out.append(Point(index: i, state: .missing,
                                 orientedZ: nil, cusum: nil,
                                 baselineMedian: nil, baselineScale: nil,
                                 baselineCount: baseline.count, observed: false))
                continue
            }

            guard baseline.count >= minimumBaseline else {
                out.append(Point(index: i, state: .calibrating,
                                 orientedZ: nil, cusum: nil,
                                 baselineMedian: nil, baselineScale: nil,
                                 baselineCount: baseline.count, observed: true))
                continue
            }

            let location = median(baseline)
            let absoluteDeviations = baseline.map { abs($0 - location) }
            var scale = normalizedMADScale * median(absoluteDeviations)
            if scale <= 0 {
                scale = sampleSD(baseline)
            }
            guard scale.isFinite, scale > 0 else {
                out.append(Point(index: i, state: .degenerateBaseline,
                                 orientedZ: nil, cusum: nil,
                                 baselineMedian: location, baselineScale: nil,
                                 baselineCount: baseline.count, observed: true))
                continue
            }

            let rawZ = (current - location) / scale
            let z = direction == .upper ? rawZ : -rawZ
            cusum = max(0, cusum + z - referenceK)

            // Recovery is based on the oriented standardized deviation returning
            // near/below baseline for consecutive observed points. Missing and
            // unevaluable points never count toward recovery.
            if z < recoveryZ {
                recoveryRun += 1
                if recoveryRun >= recoveryObservations {
                    cusum = 0
                    alertRun = 0
                }
            } else {
                recoveryRun = 0
            }

            let state: State
            if cusum > decisionH {
                alertRun += 1
                state = alertRun >= persistObservations ? .sustained : .watch
            } else {
                alertRun = 0
                state = .normal
            }

            out.append(Point(index: i, state: state,
                             orientedZ: z, cusum: cusum,
                             baselineMedian: location, baselineScale: scale,
                             baselineCount: baseline.count, observed: true))
        }
        return out
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    private static func sampleSD(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let ss = values.reduce(0) { partial, value in
            let d = value - mean
            return partial + d * d
        }
        return (ss / Double(values.count - 1)).squareRoot()
    }
}
