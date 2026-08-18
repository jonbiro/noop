import XCTest
@testable import StrandAnalytics

final class PacedBreathingSpectrumTests: XCTestCase {
    private func syntheticRR(seconds: Double, components: [(hz: Double, amplitudeMs: Double)]) -> [Double] {
        var out: [Double] = []
        var t = 0.0
        while t < seconds {
            var rr = 1_000.0
            for component in components {
                rr += component.amplitudeMs * sin(2.0 * Double.pi * component.hz * t)
            }
            out.append(rr)
            t += rr / 1_000.0
        }
        return out
    }

    func testSingleSixBreathsPerMinuteRhythmFindsExpectedPeak() {
        let rr = syntheticRR(seconds: 180, components: [(0.10, 80)])
        let result = PacedBreathingSpectrum.evaluate(cleanedNNMs: rr, targetBreathsPerMinute: 6)!

        XCTAssertEqual(result.peakHz, 0.10, accuracy: 0.004)
        XCTAssertEqual(result.peakBreathsPerMinute, 6.0, accuracy: 0.24)
        XCTAssertLessThan(result.paceErrorBreathsPerMinute!, 0.25)
        XCTAssertGreaterThan(result.peakPowerFraction, 0.20)
        XCTAssertGreaterThan(result.totalBandPower, 0)
        XCTAssertGreaterThan(result.peakBandPower, 0)
        XCTAssertEqual(result.spanSeconds, rr.reduce(0, +) / 1_000.0, accuracy: 1e-12)
        XCTAssertEqual(result.beatCount, rr.count)
    }

    func testTargetContextDoesNotMoveSpectrum() {
        let rr = syntheticRR(seconds: 180, components: [(0.10, 80)])
        let plain = PacedBreathingSpectrum.evaluate(cleanedNNMs: rr)!
        let targeted = PacedBreathingSpectrum.evaluate(cleanedNNMs: rr, targetBreathsPerMinute: 6)!

        XCTAssertEqual(plain.peakHz, targeted.peakHz, accuracy: 1e-12)
        XCTAssertEqual(plain.peakBandPower, targeted.peakBandPower, accuracy: 1e-12)
        XCTAssertEqual(plain.totalBandPower, targeted.totalBandPower, accuracy: 1e-12)
        XCTAssertEqual(plain.peakPowerFraction, targeted.peakPowerFraction, accuracy: 1e-12)
        XCTAssertNil(plain.targetBreathsPerMinute)
        XCTAssertNil(plain.paceErrorBreathsPerMinute)
    }

    func testTwoFrequencySignalIsLessConcentratedThanSinglePeak() {
        let single = syntheticRR(seconds: 180, components: [(0.10, 80)])
        let mixed = syntheticRR(seconds: 180, components: [(0.10, 60), (0.20, 60)])
        let singleResult = PacedBreathingSpectrum.evaluate(cleanedNNMs: single)!
        let mixedResult = PacedBreathingSpectrum.evaluate(cleanedNNMs: mixed)!

        XCTAssertGreaterThan(singleResult.peakPowerFraction, mixedResult.peakPowerFraction)
    }

    func testOffPaceTargetReportsAbsoluteErrorOnly() {
        let rr = syntheticRR(seconds: 180, components: [(0.10, 80)])
        let result = PacedBreathingSpectrum.evaluate(cleanedNNMs: rr, targetBreathsPerMinute: 5)!
        XCTAssertEqual(result.targetBreathsPerMinute, 5)
        XCTAssertEqual(result.paceErrorBreathsPerMinute!, abs(result.peakBreathsPerMinute - 5), accuracy: 1e-12)
    }

    func testShortConstantDirtyAndInvalidTargetFailClosed() {
        let short = syntheticRR(seconds: 50, components: [(0.10, 80)])
        XCTAssertNil(PacedBreathingSpectrum.evaluate(cleanedNNMs: short))
        XCTAssertNil(PacedBreathingSpectrum.evaluate(cleanedNNMs: Array(repeating: 1_000.0, count: 180)))

        var dirty = syntheticRR(seconds: 180, components: [(0.10, 80)])
        dirty[5] = .nan
        XCTAssertNil(PacedBreathingSpectrum.evaluate(cleanedNNMs: dirty))

        var outOfRange = syntheticRR(seconds: 180, components: [(0.10, 80)])
        outOfRange[5] = 250
        XCTAssertNil(PacedBreathingSpectrum.evaluate(cleanedNNMs: outOfRange))

        let valid = syntheticRR(seconds: 180, components: [(0.10, 80)])
        XCTAssertNil(PacedBreathingSpectrum.evaluate(cleanedNNMs: valid, targetBreathsPerMinute: 0))
        XCTAssertNil(PacedBreathingSpectrum.evaluate(cleanedNNMs: valid, targetBreathsPerMinute: 20))
    }
}
