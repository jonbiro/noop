import XCTest
@testable import StrandAnalytics

final class NonparametricCircadianEngineTests: XCTestCase {

    private func optionalize(_ values: [Double]) -> [Double?] {
        values.map { Optional.some($0) }
    }

    private func stepDay() -> [Double] {
        Array(repeating: 0.0, count: 12) + Array(repeating: 10.0, count: 12)
    }

    func testRepeatedStepRhythmPinsStandardMetrics() {
        let day = stepDay()
        let result = NonparametricCircadianEngine.evaluate(
            signal: optionalize(day + day),
            epochsPerDay: 24
        )!

        XCTAssertEqual(result.interdailyStability, 1.0, accuracy: 1e-12)
        XCTAssertEqual(result.intradailyVariability, 48.0 * 300.0 / (47.0 * 1_200.0), accuracy: 1e-12)
        XCTAssertEqual(result.m10, 10.0, accuracy: 1e-12)
        XCTAssertEqual(result.l5, 0.0, accuracy: 1e-12)
        XCTAssertEqual(result.relativeAmplitude, 1.0, accuracy: 1e-12)
        XCTAssertEqual(result.m10StartEpoch, 12)
        XCTAssertEqual(result.l5StartEpoch, 0)
        XCTAssertEqual(result.m10StartHour, 12.0, accuracy: 1e-12)
        XCTAssertEqual(result.l5StartHour, 0.0, accuracy: 1e-12)
        XCTAssertEqual(result.daysObserved, 2)
        XCTAssertEqual(result.epochsPerDay, 24)
    }

    func testCircularM10CanCrossMidnight() {
        var day = Array(repeating: 1.0, count: 24)
        for hour in [20, 21, 22, 23, 0, 1, 2, 3, 4, 5] {
            day[hour] = 10.0
        }
        let result = NonparametricCircadianEngine.evaluate(
            signal: optionalize(day + day),
            epochsPerDay: 24
        )!

        XCTAssertEqual(result.m10, 10.0, accuracy: 1e-12)
        XCTAssertEqual(result.m10StartEpoch, 20)
        XCTAssertEqual(result.m10StartHour, 20.0, accuracy: 1e-12)
        XCTAssertEqual(result.l5, 1.0, accuracy: 1e-12)
        XCTAssertEqual(result.l5StartEpoch, 6)
        XCTAssertEqual(result.relativeAmplitude, 9.0 / 11.0, accuracy: 1e-12)
    }

    func testQuarterHourGridUsesExactFiveAndTenHourWindows() {
        // 96 epochs/day = 15-minute epochs. The low block is 5 h (20 epochs)
        // from 01:00; the high block is 10 h (40 epochs) from 08:00.
        var day = Array(repeating: 2.0, count: 96)
        for i in 4..<24 { day[i] = 0.5 }
        for i in 32..<72 { day[i] = 8.0 }

        let result = NonparametricCircadianEngine.evaluate(
            signal: optionalize(day + day),
            epochsPerDay: 96
        )!
        XCTAssertEqual(result.l5, 0.5, accuracy: 1e-12)
        XCTAssertEqual(result.l5StartEpoch, 4)
        XCTAssertEqual(result.l5StartHour, 1.0, accuracy: 1e-12)
        XCTAssertEqual(result.m10, 8.0, accuracy: 1e-12)
        XCTAssertEqual(result.m10StartEpoch, 32)
        XCTAssertEqual(result.m10StartHour, 8.0, accuracy: 1e-12)
    }

    func testDaysObservedReportsHistoryWithoutInventingMaturityTier() {
        let day = stepDay()
        let signal = optionalize(Array(repeating: day, count: 7).flatMap { $0 })
        let result = NonparametricCircadianEngine.evaluate(signal: signal, epochsPerDay: 24)!

        XCTAssertEqual(result.daysObserved, 7)
        XCTAssertEqual(result.interdailyStability, 1.0, accuracy: 1e-12)
        XCTAssertEqual(result.m10, 10.0, accuracy: 1e-12)
        XCTAssertEqual(result.l5, 0.0, accuracy: 1e-12)
        XCTAssertEqual(result.relativeAmplitude, 1.0, accuracy: 1e-12)
    }

    func testOneDayAndPartialDaysFailClosed() {
        let day = optionalize(stepDay())
        XCTAssertNil(NonparametricCircadianEngine.evaluate(signal: day, epochsPerDay: 24))
        XCTAssertNil(NonparametricCircadianEngine.evaluate(signal: day + day + [.some(1.0)], epochsPerDay: 24))
    }

    func testEpochGridMustDivideDayIntoWholeHours() {
        let signal: [Double?] = Array(repeating: .some(1.0), count: 100)
        XCTAssertNil(NonparametricCircadianEngine.evaluate(signal: signal, epochsPerDay: 50))
        XCTAssertNil(NonparametricCircadianEngine.evaluate(signal: signal, epochsPerDay: 0))
    }

    func testMissingNonFiniteNegativeAndConstantSignalsFailClosed() {
        var missing = optionalize(stepDay() + stepDay())
        missing[5] = nil
        XCTAssertNil(NonparametricCircadianEngine.evaluate(signal: missing, epochsPerDay: 24))

        var nonFinite = optionalize(stepDay() + stepDay())
        nonFinite[5] = .some(Double.nan)
        XCTAssertNil(NonparametricCircadianEngine.evaluate(signal: nonFinite, epochsPerDay: 24))

        var negative = optionalize(stepDay() + stepDay())
        negative[5] = .some(-1.0)
        XCTAssertNil(NonparametricCircadianEngine.evaluate(signal: negative, epochsPerDay: 24))

        let constant: [Double?] = Array(repeating: .some(5.0), count: 48)
        XCTAssertNil(NonparametricCircadianEngine.evaluate(signal: constant, epochsPerDay: 24))
    }
}
