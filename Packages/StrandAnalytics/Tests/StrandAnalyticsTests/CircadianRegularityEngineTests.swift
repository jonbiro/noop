import XCTest
@testable import StrandAnalytics

final class CircadianRegularityEngineTests: XCTestCase {

    // MARK: - Sleep Regularity Index

    func testSriPerfectRepeatedDayIs100() {
        let day = (0..<24).map { hour in hour < 7 || hour >= 23 }
        let states: [Bool?] = (day + day).map { Optional.some($0) }
        let result = CircadianRegularityEngine.sleepRegularityIndex(states: states, epochSeconds: 3_600)!

        XCTAssertEqual(result.score, 100, accuracy: 1e-12)
        XCTAssertEqual(result.comparablePairs, 24)
        XCTAssertEqual(result.possiblePairs, 24)
        XCTAssertEqual(result.coverage, 1, accuracy: 1e-12)
        XCTAssertEqual(result.matchingPairs, 24)
        XCTAssertEqual(result.spanDays, 2, accuracy: 1e-12)
    }

    func testSriOppositeSecondDayIsMinus100() {
        let day = (0..<24).map { hour in hour < 7 || hour >= 23 }
        let inverted = day.map { !$0 }
        let states: [Bool?] = (day + inverted).map { Optional.some($0) }
        let result = CircadianRegularityEngine.sleepRegularityIndex(states: states, epochSeconds: 3_600)!

        XCTAssertEqual(result.score, -100, accuracy: 1e-12)
        XCTAssertEqual(result.matchingPairs, 0)
        XCTAssertEqual(result.comparablePairs, 24)
    }

    func testSriHalfAgreementIsZero() {
        let first = Array(repeating: false, count: 24)
        let second = Array(repeating: false, count: 12) + Array(repeating: true, count: 12)
        let states: [Bool?] = (first + second).map { Optional.some($0) }
        let result = CircadianRegularityEngine.sleepRegularityIndex(states: states, epochSeconds: 3_600)!
        XCTAssertEqual(result.matchingPairs, 12)
        XCTAssertEqual(result.score, 0, accuracy: 1e-12)
    }

    func testSriMissingEpochReducesCoverageWithoutBecomingWake() {
        let day = (0..<24).map { hour in hour < 7 || hour >= 23 }
        var states: [Bool?] = (day + day).map { Optional.some($0) }
        states[2] = nil
        states[26] = nil

        let result = CircadianRegularityEngine.sleepRegularityIndex(states: states, epochSeconds: 3_600)!
        XCTAssertEqual(result.score, 100, accuracy: 1e-12)
        XCTAssertEqual(result.comparablePairs, 23)
        XCTAssertEqual(result.possiblePairs, 24)
        XCTAssertEqual(result.coverage, 23.0 / 24.0, accuracy: 1e-12)
    }

    func testSriRejectsTooShortOrInvalidGrid() {
        let oneDay: [Bool?] = Array(repeating: .some(false), count: 24)
        XCTAssertNil(CircadianRegularityEngine.sleepRegularityIndex(states: oneDay, epochSeconds: 3_600))
        XCTAssertNil(CircadianRegularityEngine.sleepRegularityIndex(states: oneDay + oneDay, epochSeconds: 0))
        XCTAssertNil(CircadianRegularityEngine.sleepRegularityIndex(
            states: oneDay + oneDay, epochSeconds: 3_600, lagSeconds: 1_000))
    }

    func testSriRejectsSpanWithNoComparablePairs() {
        var states: [Bool?] = Array(repeating: nil, count: 48)
        states[0] = true
        XCTAssertNil(CircadianRegularityEngine.sleepRegularityIndex(states: states, epochSeconds: 3_600))
    }

    // MARK: - Circular social jetlag

    func testSocialJetLagWrapsAcrossMidnight() {
        let result = CircadianRegularityEngine.socialJetLag(
            freeDayMidSleepHours: [1.0, 1.0],
            workdayMidSleepHours: [23.5, 23.5]
        )!
        XCTAssertEqual(result.freeDayMidSleepHour, 1.0, accuracy: 1e-12)
        XCTAssertEqual(result.workdayMidSleepHour, 23.5, accuracy: 1e-12)
        XCTAssertEqual(result.signedHours, 1.5, accuracy: 1e-12)
        XCTAssertEqual(result.absoluteHours, 1.5, accuracy: 1e-12)
    }

    func testSocialJetLagPreservesEarlierFreeDayDirection() {
        let result = CircadianRegularityEngine.socialJetLag(
            freeDayMidSleepHours: [23.0, 23.0],
            workdayMidSleepHours: [1.0, 1.0]
        )!
        XCTAssertEqual(result.signedHours, -2.0, accuracy: 1e-12)
        XCTAssertEqual(result.absoluteHours, 2.0, accuracy: 1e-12)
    }

    func testCircularMedianHandlesMidnight() {
        let midpoint = CircadianRegularityEngine.circularMedianHour([23.5, 0.5])!
        XCTAssertEqual(midpoint, 0, accuracy: 1e-12)
    }

    func testSocialJetLagRejectsInsufficientOrDegenerateSamples() {
        XCTAssertNil(CircadianRegularityEngine.socialJetLag(
            freeDayMidSleepHours: [1.0], workdayMidSleepHours: [23.0, 23.0]))
        XCTAssertNil(CircadianRegularityEngine.socialJetLag(
            freeDayMidSleepHours: [0.0, 12.0], workdayMidSleepHours: [6.0, 6.0]))
        XCTAssertNil(CircadianRegularityEngine.socialJetLag(
            freeDayMidSleepHours: [Double.nan, 1.0], workdayMidSleepHours: [23.0, 23.0]))
    }

    // MARK: - Sleep-debt-corrected free-day midpoint

    func testCorrectedMidSleepAppliesHalfOversleepCorrection() {
        let result = CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours: [4.0, 4.0],
            freeDaySleepDurationHours: [9.0, 9.0],
            averageWorkdaySleepDurationHours: 7.5,
            averageWeekSleepDurationHours: 8.0
        )!
        XCTAssertEqual(result.freeDayMidSleepHour, 4.0, accuracy: 1e-12)
        XCTAssertEqual(result.medianFreeDaySleepDurationHours, 9.0, accuracy: 1e-12)
        XCTAssertEqual(result.averageWorkdaySleepDurationHours, 7.5, accuracy: 1e-12)
        XCTAssertEqual(result.oversleepCorrectionHours, 0.5, accuracy: 1e-12)
        XCTAssertEqual(result.correctedMidSleepHour, 3.5, accuracy: 1e-12)
    }

    func testCorrectedMidSleepDoesNotCorrectWhenFreeSleepDoesNotExceedWorkSleep() {
        let result = CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours: [4.0, 4.0],
            freeDaySleepDurationHours: [8.5, 8.5],
            averageWorkdaySleepDurationHours: 9.0,
            averageWeekSleepDurationHours: 8.0
        )!
        XCTAssertEqual(result.oversleepCorrectionHours, 0, accuracy: 1e-12)
        XCTAssertEqual(result.correctedMidSleepHour, 4.0, accuracy: 1e-12)
    }

    func testCorrectedMidSleepUsesCircularMidpointAcrossMidnight() {
        let result = CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours: [23.5, 0.5],
            freeDaySleepDurationHours: [8.0, 8.0],
            averageWorkdaySleepDurationHours: 8.0,
            averageWeekSleepDurationHours: 8.0
        )!
        XCTAssertEqual(result.freeDayMidSleepHour, 0, accuracy: 1e-12)
        XCTAssertEqual(result.correctedMidSleepHour, 0, accuracy: 1e-12)
    }

    func testCorrectedMidSleepFailsClosedOnInvalidInput() {
        XCTAssertNil(CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours: [4.0, 4.0],
            freeDaySleepDurationHours: [8.0],
            averageWorkdaySleepDurationHours: 7.5,
            averageWeekSleepDurationHours: 8.0))
        XCTAssertNil(CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours: [4.0, 4.0],
            freeDaySleepDurationHours: [8.0, 25.0],
            averageWorkdaySleepDurationHours: 7.5,
            averageWeekSleepDurationHours: 8.0))
        XCTAssertNil(CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours: [4.0, 4.0],
            freeDaySleepDurationHours: [8.0, 8.0],
            averageWorkdaySleepDurationHours: Double.infinity,
            averageWeekSleepDurationHours: 8.0))
        XCTAssertNil(CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours: [4.0, 4.0],
            freeDaySleepDurationHours: [8.0, 8.0],
            averageWorkdaySleepDurationHours: 7.5,
            averageWeekSleepDurationHours: Double.infinity))
    }
}
