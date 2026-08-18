import XCTest
@testable import StrandAnalytics

final class PersistentShiftDetectorTests: XCTestCase {

    private let baseline = [99.0, 100, 101, 99, 100, 101, 100]

    func testUpperShiftProgressesNormalWatchSustainedThenRecovers() {
        let values: [Double?] = (baseline + [106, 106, 106, 100, 100]).map { .some($0) }
        let result = PersistentShiftDetector.evaluate(values: values, direction: .upper)!

        XCTAssertEqual(result[0].state, .calibrating)
        XCTAssertEqual(result[6].state, .calibrating)
        XCTAssertEqual(result[7].state, .normal)
        XCTAssertEqual(result[8].state, .watch)
        XCTAssertEqual(result[9].state, .sustained)
        XCTAssertEqual(result[10].state, .sustained)
        XCTAssertEqual(result[11].state, .normal)
        XCTAssertEqual(result[11].cusum!, 0, accuracy: 1e-12)
        XCTAssertEqual(result[7].baselineMedian!, 100, accuracy: 1e-12)
        XCTAssertEqual(result[7].baselineScale!, PersistentShiftDetector.normalizedMADScale, accuracy: 1e-12)
        XCTAssertEqual(result[7].orientedZ!, 6.0 / PersistentShiftDetector.normalizedMADScale, accuracy: 1e-12)
    }

    func testLowerDirectionOrientsDropAsPositive() {
        let values: [Double?] = (baseline + [94, 94, 94]).map { .some($0) }
        let result = PersistentShiftDetector.evaluate(values: values, direction: .lower)!
        XCTAssertGreaterThan(result[7].orientedZ!, 0)
        XCTAssertEqual(result[8].state, .watch)
        XCTAssertEqual(result[9].state, .sustained)
    }

    func testMissingObservationDoesNotResetAccumulatorOrPersistenceRun() {
        let values: [Double?] = baseline.map { .some($0) } + [.some(106), .some(106), nil, .some(106)]
        let result = PersistentShiftDetector.evaluate(values: values, direction: .upper)!
        XCTAssertEqual(result[8].state, .watch)
        XCTAssertEqual(result[9].state, .missing)
        XCTAssertFalse(result[9].observed)
        XCTAssertNil(result[9].cusum)
        XCTAssertEqual(result[10].state, .sustained)
    }

    func testDegenerateBaselineAbstainsInsteadOfInventingScale() {
        let values: [Double?] = Array(repeating: .some(100.0), count: 7) + [.some(105)]
        let result = PersistentShiftDetector.evaluate(values: values, direction: .upper)!
        XCTAssertEqual(result[7].state, .degenerateBaseline)
        XCTAssertEqual(result[7].baselineMedian!, 100, accuracy: 1e-12)
        XCTAssertNil(result[7].baselineScale)
        XCTAssertNil(result[7].orientedZ)
        XCTAssertNil(result[7].cusum)
    }

    func testSampleSDFallbackHandlesZeroMADButNonconstantBaseline() {
        let values: [Double?] = [100, 100, 100, 100, 100, 100, 101, 105].map { .some($0) }
        let result = PersistentShiftDetector.evaluate(values: values, direction: .upper)!
        XCTAssertEqual(result[7].state, .watch)
        XCTAssertNotNil(result[7].baselineScale)
        XCTAssertGreaterThan(result[7].baselineScale!, 0)
    }

    func testTrailingBaselineWindowUsesOnlyPriorObservedValues() {
        let values: [Double?] = [.some(99), nil, .some(100), .some(101), .some(99), .some(100), .some(101), .some(100), .some(106)]
        let result = PersistentShiftDetector.evaluate(
            values: values,
            direction: .upper,
            minimumBaseline: 7
        )!
        XCTAssertEqual(result[7].state, .calibrating)
        XCTAssertEqual(result[7].baselineCount, 6)
        XCTAssertEqual(result[8].baselineCount, 7)
        XCTAssertNotNil(result[8].orientedZ)
    }

    func testCustomThresholdsAreDeterministicAndConfigurable() {
        let values: [Double?] = (baseline + [104, 104]).map { .some($0) }
        let defaultResult = PersistentShiftDetector.evaluate(values: values, direction: .upper)!
        let sensitive = PersistentShiftDetector.evaluate(
            values: values,
            direction: .upper,
            referenceK: 0,
            decisionH: 1,
            persistObservations: 1
        )!
        XCTAssertEqual(defaultResult[7].state, .normal)
        XCTAssertEqual(sensitive[7].state, .sustained)
    }

    func testInvalidConfigurationOrNonFiniteInputFailsWholeEvaluation() {
        let values: [Double?] = baseline.map { .some($0) }
        XCTAssertNil(PersistentShiftDetector.evaluate(values: values, direction: .upper, baselineWindow: 6, minimumBaseline: 7))
        XCTAssertNil(PersistentShiftDetector.evaluate(values: values, direction: .upper, minimumBaseline: 1))
        XCTAssertNil(PersistentShiftDetector.evaluate(values: values, direction: .upper, referenceK: -1))
        XCTAssertNil(PersistentShiftDetector.evaluate(values: values, direction: .upper, decisionH: 0))
        XCTAssertNil(PersistentShiftDetector.evaluate(values: values, direction: .upper, persistObservations: 0))
        XCTAssertNil(PersistentShiftDetector.evaluate(values: values, direction: .upper, recoveryObservations: 0))
        XCTAssertNil(PersistentShiftDetector.evaluate(values: values + [.some(.nan)], direction: .upper))
    }
}
