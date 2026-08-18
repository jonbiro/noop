import XCTest
@testable import StrandAnalytics

final class MetricAvailabilityTests: XCTestCase {
    func testAvailableHasValueWithoutReason() {
        XCTAssertEqual(MetricAvailability.available.state, .available)
        XCTAssertTrue(MetricAvailability.available.hasValue)
        XCTAssertNil(MetricAvailability.available.reason)
        XCTAssertNil(MetricAvailability.available.wireReason)
    }

    func testBaselineReasonIsStableAndMachineReadable() {
        let value = MetricAvailability.needBaseline(have: 5, need: 14)
        XCTAssertEqual(value.state, .calibrating)
        XCTAssertFalse(value.hasValue)
        XCTAssertEqual(value.reason?.code, .needBaseline)
        XCTAssertEqual(value.wireReason, "need_baseline:have=5;need=14")
    }

    func testCoverageUsesDeterministicDecimalFormatting() {
        let value = MetricAvailability.insufficientCoverage(have: 0.42, need: 0.8)
        XCTAssertEqual(value.state, .insufficientData)
        XCTAssertEqual(value.wireReason, "insufficient_coverage:have=0.42;need=0.8")
    }

    func testItemsAreSortedDeduplicatedAndEmptyItemsRemoved() {
        let value = MetricAvailability.missingInputs(["rhr", "", "hrv", "rhr"])
        XCTAssertEqual(value.reason?.items, ["hrv", "rhr"])
        XCTAssertEqual(value.wireReason, "missing_inputs:items=hrv,rhr")
    }

    func testQualityAndSourceStatesDoNotClaimValue() {
        XCTAssertFalse(MetricAvailability.withheldQuality(["rr_order_unknown"]).hasValue)
        XCTAssertFalse(MetricAvailability.unsupportedSource("whoop4_spo2").hasValue)
        XCTAssertFalse(MetricAvailability.stale(lastDay: "2026-01-01", expectedDay: "2026-01-02").hasValue)
    }

    func testExperimentalStateExplicitlyCarriesValue() {
        let value = MetricAvailability.experimentalUnvalidated("hrv_readiness")
        XCTAssertEqual(value.state, .experimentalAvailable)
        XCTAssertTrue(value.hasValue)
        XCTAssertEqual(value.wireReason, "experimental_unvalidated:items=hrv_readiness")
    }

    func testHrvReadinessCalibratingExplainsValidNightCount() {
        let input: [Double?] = [60, 61, nil, 500, 62, 63]
        let evaluation = HRVReadiness.evaluateWithAvailability(avgHrv: input)
        XCTAssertNil(evaluation.result)
        XCTAssertEqual(evaluation.validNightCount, 4)
        XCTAssertEqual(evaluation.availability.state, .calibrating)
        XCTAssertEqual(evaluation.availability.wireReason, "need_baseline:have=4;need=14")
        XCTAssertEqual(HRVReadiness.evaluate(avgHrv: input), evaluation.result)
    }

    func testHrvReadinessAvailableResultRemainsExplicitlyExperimental() {
        let input: [Double?] = (0..<14).map { Double(55 + $0) }
        let legacy = HRVReadiness.evaluate(avgHrv: input)
        let evaluation = HRVReadiness.evaluateWithAvailability(avgHrv: input)

        XCTAssertNotNil(legacy)
        XCTAssertEqual(evaluation.result, legacy)
        XCTAssertEqual(evaluation.validNightCount, 14)
        XCTAssertEqual(evaluation.availability.state, .experimentalAvailable)
        XCTAssertTrue(evaluation.availability.hasValue)
        XCTAssertEqual(evaluation.availability.wireReason, "experimental_unvalidated:items=hrv_readiness")
    }
}
