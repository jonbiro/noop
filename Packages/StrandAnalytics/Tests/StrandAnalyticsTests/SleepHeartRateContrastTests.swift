import XCTest
@testable import StrandAnalytics

final class SleepHeartRateContrastTests: XCTestCase {

    func testLowerSleepHRProducesPositiveReduction() {
        let wake: [Double?] = Array(repeating: .some(70.0), count: 60)
        let sleep: [Double?] = Array(repeating: .some(60.0), count: 60)
        let result = SleepHeartRateContrast.evaluate(wakeHR: wake, primarySleepHR: sleep)!

        XCTAssertEqual(result.wakeMeanBpm, 70, accuracy: 1e-12)
        XCTAssertEqual(result.sleepMeanBpm, 60, accuracy: 1e-12)
        XCTAssertEqual(result.sleepMinusWakeBpm, -10, accuracy: 1e-12)
        XCTAssertEqual(result.sleepReductionPercent, 100.0 / 7.0, accuracy: 1e-12)
        XCTAssertEqual(result.wakeCoverage, 1, accuracy: 1e-12)
        XCTAssertEqual(result.sleepCoverage, 1, accuracy: 1e-12)
    }

    func testHigherSleepHRProducesNegativeReductionWithoutClassification() {
        let wake: [Double?] = Array(repeating: .some(60.0), count: 40)
        let sleep: [Double?] = Array(repeating: .some(66.0), count: 40)
        let result = SleepHeartRateContrast.evaluate(wakeHR: wake, primarySleepHR: sleep)!

        XCTAssertEqual(result.sleepMinusWakeBpm, 6, accuracy: 1e-12)
        XCTAssertEqual(result.sleepReductionPercent, -10, accuracy: 1e-12)
    }

    func testMissingAndInvalidEpochsAreExcludedAndReduceCoverage() {
        var wake: [Double?] = Array(repeating: .some(70.0), count: 40)
        var sleep: [Double?] = Array(repeating: .some(60.0), count: 40)
        wake[0] = nil
        wake[1] = .some(29)
        wake[2] = .some(221)
        wake[3] = .some(Double.nan)
        sleep[0] = nil
        sleep[1] = .some(10)
        sleep[2] = .some(500)
        sleep[3] = .some(Double.infinity)

        let result = SleepHeartRateContrast.evaluate(
            wakeHR: wake,
            primarySleepHR: sleep,
            minimumValidSamples: 30
        )!
        XCTAssertEqual(result.wakeValidSamples, 36)
        XCTAssertEqual(result.sleepValidSamples, 36)
        XCTAssertEqual(result.wakeCoverage, 0.9, accuracy: 1e-12)
        XCTAssertEqual(result.sleepCoverage, 0.9, accuracy: 1e-12)
        XCTAssertEqual(result.wakeMeanBpm, 70, accuracy: 1e-12)
        XCTAssertEqual(result.sleepMeanBpm, 60, accuracy: 1e-12)
    }

    func testValidityRangeEdgesAreIncluded() {
        let wake: [Double?] = Array(repeating: .some(30.0), count: 30)
        let sleep: [Double?] = Array(repeating: .some(220.0), count: 30)
        let result = SleepHeartRateContrast.evaluate(wakeHR: wake, primarySleepHR: sleep)!
        XCTAssertEqual(result.wakeMeanBpm, 30, accuracy: 1e-12)
        XCTAssertEqual(result.sleepMeanBpm, 220, accuracy: 1e-12)
    }

    func testMinimumValidSampleGateAppliesIndependentlyToBothWindows() {
        let enough: [Double?] = Array(repeating: .some(60.0), count: 30)
        let short: [Double?] = Array(repeating: .some(60.0), count: 29)
        XCTAssertNil(SleepHeartRateContrast.evaluate(wakeHR: short, primarySleepHR: enough))
        XCTAssertNil(SleepHeartRateContrast.evaluate(wakeHR: enough, primarySleepHR: short))
        XCTAssertNotNil(SleepHeartRateContrast.evaluate(wakeHR: short, primarySleepHR: short, minimumValidSamples: 29))
    }

    func testEmptyAndInvalidConfigurationFailClosed() {
        let enough: [Double?] = Array(repeating: .some(60.0), count: 30)
        XCTAssertNil(SleepHeartRateContrast.evaluate(wakeHR: [], primarySleepHR: enough))
        XCTAssertNil(SleepHeartRateContrast.evaluate(wakeHR: enough, primarySleepHR: []))
        XCTAssertNil(SleepHeartRateContrast.evaluate(wakeHR: enough, primarySleepHR: enough, minimumValidSamples: 0))
    }

    func testUnequalWindowLengthsAreAllowedAndCoverageIsPerWindow() {
        var wake: [Double?] = Array(repeating: .some(72.0), count: 120)
        var sleep: [Double?] = Array(repeating: .some(60.0), count: 60)
        for i in 0..<30 { wake[i] = nil }
        for i in 0..<15 { sleep[i] = nil }

        let result = SleepHeartRateContrast.evaluate(wakeHR: wake, primarySleepHR: sleep)!
        XCTAssertEqual(result.wakeValidSamples, 90)
        XCTAssertEqual(result.wakeTotalSamples, 120)
        XCTAssertEqual(result.wakeCoverage, 0.75, accuracy: 1e-12)
        XCTAssertEqual(result.sleepValidSamples, 45)
        XCTAssertEqual(result.sleepTotalSamples, 60)
        XCTAssertEqual(result.sleepCoverage, 0.75, accuracy: 1e-12)
    }
}
