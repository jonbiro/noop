import Foundation

// PacedBreathingSpectrum.swift - transparent spectral concentration during guided breathing.
//
// This is deliberately narrower than branded "cardiac coherence" scores. It
// measures how concentrated a cleaned RR/PRV tachogram's spectral power is
// around its dominant paced-breathing-range oscillation. No proprietary or
// invented 0-100 score, emotional-state claim, or clinical interpretation.
public enum PacedBreathingSpectrum {
    public static let searchLowHz: Double = 0.04
    public static let searchHighHz: Double = 0.26
    public static let totalHighHz: Double = 0.40
    public static let peakHalfWidthHz: Double = 0.015
    public static let frequencyStepHz: Double = 0.002
    public static let minimumSpanSeconds: Double = 60
    public static let minimumBeats: Int = 50
    public static let minNNMs: Double = 300
    public static let maxNNMs: Double = 2_000

    public struct Result: Equatable, Sendable {
        public let peakHz: Double
        public let peakBreathsPerMinute: Double
        public let peakBandPower: Double
        public let totalBandPower: Double
        public let peakPowerFraction: Double
        public let peakToRemainderRatio: Double?
        public let targetBreathsPerMinute: Double?
        public let paceErrorBreathsPerMinute: Double?
        /// Full duration represented by all supplied RR intervals.
        public let spanSeconds: Double
        public let beatCount: Int

        public init(peakHz: Double, peakBreathsPerMinute: Double,
                    peakBandPower: Double, totalBandPower: Double,
                    peakPowerFraction: Double, peakToRemainderRatio: Double?,
                    targetBreathsPerMinute: Double?, paceErrorBreathsPerMinute: Double?,
                    spanSeconds: Double, beatCount: Int) {
            self.peakHz = peakHz
            self.peakBreathsPerMinute = peakBreathsPerMinute
            self.peakBandPower = peakBandPower
            self.totalBandPower = totalBandPower
            self.peakPowerFraction = peakPowerFraction
            self.peakToRemainderRatio = peakToRemainderRatio
            self.targetBreathsPerMinute = targetBreathsPerMinute
            self.paceErrorBreathsPerMinute = paceErrorBreathsPerMinute
            self.spanSeconds = spanSeconds
            self.beatCount = beatCount
        }
    }

    /// Spectral concentration of an already-cleaned NN/RR series.
    /// `targetBreathsPerMinute` is optional context only; it never moves the
    /// spectral peak or changes the concentration calculation.
    public static func evaluate(
        cleanedNNMs: [Double],
        targetBreathsPerMinute: Double? = nil
    ) -> Result? {
        guard cleanedNNMs.count >= minimumBeats,
              cleanedNNMs.allSatisfy({ $0.isFinite && $0 >= minNNMs && $0 <= maxNNMs }) else { return nil }
        if let targetBreathsPerMinute {
            guard targetBreathsPerMinute.isFinite,
                  targetBreathsPerMinute > 0,
                  targetBreathsPerMinute <= 60 * searchHighHz else { return nil }
        }

        var times = [Double](repeating: 0, count: cleanedNNMs.count)
        var elapsed = 0.0
        for i in cleanedNNMs.indices {
            times[i] = elapsed
            elapsed += cleanedNNMs[i] / 1000.0
        }
        // `times` records each interval's start time. `elapsed` is the end of
        // the final interval and therefore the full duration represented by the
        // supplied RR series. Using times.last would silently omit the last RR.
        let span = elapsed
        guard span >= minimumSpanSeconds else { return nil }

        let mean = cleanedNNMs.reduce(0, +) / Double(cleanedNNMs.count)
        let y = cleanedNNMs.map { $0 - mean }
        var variance = 0.0
        for value in y { variance += value * value }
        variance /= Double(y.count)
        guard variance.isFinite, variance > 0 else { return nil }

        let resolvableLow = max(searchLowHz, 1.0 / span)
        guard resolvableLow < totalHighHz else { return nil }

        var points: [(f: Double, p: Double)] = []
        var f = resolvableLow
        while f <= totalHighHz + 1e-12 {
            let p = lombScarglePower(times: times, y: y, freqHz: f, variance: variance)
            guard p.isFinite, p >= 0 else { return nil }
            points.append((f, p))
            f += frequencyStepHz
        }
        guard points.count >= 2 else { return nil }

        let searchUpper = min(searchHighHz, totalHighHz)
        let searchPoints = points.filter { $0.f >= searchLowHz && $0.f <= searchUpper }
        guard let peak = searchPoints.max(by: { $0.p < $1.p }) else { return nil }

        let totalPower = integrate(points, low: resolvableLow, high: totalHighHz)
        let peakLow = max(resolvableLow, peak.f - peakHalfWidthHz)
        let peakHigh = min(totalHighHz, peak.f + peakHalfWidthHz)
        let peakPower = integrate(points, low: peakLow, high: peakHigh)
        guard totalPower.isFinite, peakPower.isFinite, totalPower > 0, peakPower >= 0 else { return nil }

        let fraction = min(1.0, max(0.0, peakPower / totalPower))
        let remainder = max(0.0, totalPower - peakPower)
        let ratio = remainder > 0 ? peakPower / remainder : nil
        let peakBpm = peak.f * 60.0
        let paceError = targetBreathsPerMinute.map { abs(peakBpm - $0) }

        return Result(
            peakHz: peak.f,
            peakBreathsPerMinute: peakBpm,
            peakBandPower: peakPower,
            totalBandPower: totalPower,
            peakPowerFraction: fraction,
            peakToRemainderRatio: ratio,
            targetBreathsPerMinute: targetBreathsPerMinute,
            paceErrorBreathsPerMinute: paceError,
            spanSeconds: span,
            beatCount: cleanedNNMs.count
        )
    }

    private static func integrate(_ points: [(f: Double, p: Double)], low: Double, high: Double) -> Double {
        guard high > low else { return 0 }
        var filtered = points.filter { $0.f >= low - 1e-12 && $0.f <= high + 1e-12 }
        guard filtered.count >= 2 else { return 0 }
        filtered.sort { $0.f < $1.f }
        var area = 0.0
        for i in 1..<filtered.count {
            area += 0.5 * (filtered[i - 1].p + filtered[i].p) * (filtered[i].f - filtered[i - 1].f)
        }
        return area
    }

    /// Press/Numerical-Recipes style normalized Lomb-Scargle power. Kept local
    /// so the Kotlin twin has an exact algorithmic contract independent of UI.
    private static func lombScarglePower(times: [Double], y: [Double], freqHz: Double, variance: Double) -> Double {
        let omega = 2.0 * Double.pi * freqHz
        var sin2 = 0.0, cos2 = 0.0
        for t in times {
            let a = 2.0 * omega * t
            sin2 += sin(a)
            cos2 += cos(a)
        }
        let tau = atan2(sin2, cos2) / (2.0 * omega)
        var cTerm = 0.0, cDen = 0.0, sTerm = 0.0, sDen = 0.0
        for i in times.indices {
            let arg = omega * (times[i] - tau)
            let c = cos(arg), s = sin(arg)
            cTerm += y[i] * c; cDen += c * c
            sTerm += y[i] * s; sDen += s * s
        }
        let cosPart = cDen > 0 ? cTerm * cTerm / cDen : 0
        let sinPart = sDen > 0 ? sTerm * sTerm / sDen : 0
        return (cosPart + sinPart) / (2.0 * variance)
    }
}
