import XCTest
@testable import StrandAnalytics
import WhoopStore

final class RROrderAuditTests: XCTestCase {
    private func row(ts: Int, rrMs: Int, seq: Int = 0, ord: Int?) -> RROrderAuditRow {
        RROrderAuditRow(ts: ts, rrMs: rrMs, seq: seq, emissionOrder: ord)
    }

    func testIssueExampleShowsMagnitudeOrderBiasAndPermutationSeverity() {
        let emission = [812, 795, 840, 801, 833]
        let rows = emission.enumerated().map { offset, value in
            row(ts: 100, rrMs: value, ord: offset)
        }

        let report = RROrderAudit.evaluate(rows)

        XCTAssertEqual(report.schemaVersion, 2)
        XCTAssertEqual(report.integrityStatus, .complete)
        XCTAssertEqual(report.currentOrder.rawRmssdMs!, 34.85, accuracy: 0.01)
        XCTAssertEqual(report.magnitudeOrderCounterfactual.rawRmssdMs!, 12.72, accuracy: 0.01)
        XCTAssertGreaterThan(report.rawRmssdCurrentMinusMagnitudeMs!, 20.0)
        XCTAssertEqual(report.currentOrder.actualCleanCount, 5)
        XCTAssertEqual(report.currentOrder.nClean, 0, "production result stays behind the 20-beat gate")
        XCTAssertEqual(report.currentOrder.contiguousPairCount, 4)
        XCTAssertFalse(report.currentOrder.meetsProductionBeatGate)
        XCTAssertEqual(report.provenance.trustworthyMultiBeatSeconds, 1)
        XCTAssertEqual(report.provenance.magnitudeReorderedTrustworthySeconds, 1)
        XCTAssertEqual(report.permutationImpact.valueInversions, 4)
        XCTAssertEqual(report.permutationImpact.possibleValueInversions, 10)
        XCTAssertEqual(report.permutationImpact.normalizedValueInversionFraction!, 0.4, accuracy: 1e-12)
        XCTAssertTrue(report.rawOrderInvariantPreserved)
        XCTAssertTrue(report.flags.contains(.currentBelowProductionBeatGate))
        XCTAssertTrue(report.flags.contains(.counterfactualBelowProductionBeatGate))
        // Five beats are intentionally below the production 20-beat gate; raw RMSSD remains measurable.
        XCTAssertNil(report.currentOrder.rmssdMs)
        XCTAssertNil(report.magnitudeOrderCounterfactual.rmssdMs)
    }

    func testProductionPipelineCounterfactualCoversAllCoreMetrics() {
        let emission = [812, 795, 840, 801, 833]
        var rows: [RROrderAuditRow] = []
        for second in 0..<4 {
            rows.append(contentsOf: emission.enumerated().map { offset, value in
                row(ts: 1_000 + second, rrMs: value, ord: offset)
            })
        }

        let report = RROrderAudit.evaluate(rows)

        XCTAssertEqual(report.currentOrder.nInput, 20)
        XCTAssertEqual(report.currentOrder.nClean, 20)
        XCTAssertEqual(report.currentOrder.actualCleanCount, 20)
        XCTAssertEqual(report.currentOrder.rejectedCount, 0)
        XCTAssertEqual(report.currentOrder.contiguousPairCount, 19)
        XCTAssertTrue(report.currentOrder.meetsProductionBeatGate)
        XCTAssertNotNil(report.currentOrder.rmssdMs)
        XCTAssertNotNil(report.magnitudeOrderCounterfactual.rmssdMs)
        XCTAssertNotNil(report.currentOrder.sdnnMs)
        XCTAssertNotNil(report.currentOrder.meanNNMs)
        XCTAssertNotNil(report.currentOrder.pnn50Pct)
        XCTAssertTrue(report.currentOrder.rmssdMs! > report.magnitudeOrderCounterfactual.rmssdMs!)
        XCTAssertGreaterThan(report.rmssdCurrentMinusMagnitudeMs!, 10.0)
        XCTAssertNotNil(report.pnn50CurrentMinusMagnitudePercentagePoints)
        XCTAssertEqual(report.provenance.trustworthyMultiBeatSeconds, 4)
        XCTAssertTrue(report.provenance.hasCompleteSameSecondOrder)
        XCTAssertTrue(report.rawOrderInvariantPreserved)
        XCTAssertTrue(report.flags.contains(.magnitudeOrderChangesProductionHrv))
    }

    func testProvenancePartitionsEveryMultiBeatSecondAndAssignsAmbiguousStatus() {
        let rows = [
            row(ts: 1, rrMs: 800, ord: nil),                                      // single
            row(ts: 2, rrMs: 812, ord: 2), row(ts: 2, rrMs: 795, ord: 7),         // trustworthy, gaps OK
            row(ts: 3, rrMs: 801, ord: nil), row(ts: 3, rrMs: 833, ord: nil),     // all unknown
            row(ts: 4, rrMs: 802, ord: nil), row(ts: 4, rrMs: 834, ord: 0),       // mixed
            row(ts: 5, rrMs: 803, ord: 0), row(ts: 5, rrMs: 835, ord: 0),         // split-batch ambiguous
        ]

        let report = RROrderAudit.evaluate(rows)
        let p = report.provenance

        XCTAssertEqual(p.totalIntervals, 9)
        XCTAssertEqual(p.intervalsWithRecordedOrder, 5)
        XCTAssertEqual(p.intervalsWithUnknownOrder, 4)
        XCTAssertEqual(p.firstTs, 1)
        XCTAssertEqual(p.lastTs, 5)
        XCTAssertEqual(p.spanSeconds, 4)
        XCTAssertEqual(p.distinctSeconds, 5)
        XCTAssertEqual(p.maxIntervalsPerSecond, 2)
        XCTAssertEqual(p.singleBeatSeconds, 1)
        XCTAssertEqual(p.multiBeatSeconds, 4)
        XCTAssertEqual(p.multiBeatIntervals, 8)
        XCTAssertEqual(p.trustworthyMultiBeatSeconds, 1)
        XCTAssertEqual(p.trustworthyMultiBeatIntervals, 2)
        XCTAssertEqual(p.allUnknownMultiBeatSeconds, 1)
        XCTAssertEqual(p.allUnknownMultiBeatIntervals, 2)
        XCTAssertEqual(p.mixedOrderMultiBeatSeconds, 1)
        XCTAssertEqual(p.mixedOrderMultiBeatIntervals, 2)
        XCTAssertEqual(p.ambiguousRecordedOrderMultiBeatSeconds, 1)
        XCTAssertEqual(p.ambiguousRecordedOrderMultiBeatIntervals, 2)
        XCTAssertEqual(p.magnitudeReorderedTrustworthySeconds, 1)
        XCTAssertEqual(p.magnitudeReorderedTrustworthyIntervals, 2)
        XCTAssertEqual(p.recordedOrderFraction!, 5.0 / 9.0, accuracy: 1e-12)
        XCTAssertEqual(p.trustworthyMultiBeatIntervalFraction!, 0.25, accuracy: 1e-12)
        XCTAssertFalse(p.hasCompleteSameSecondOrder)
        XCTAssertEqual(p.integrityStatus, .ambiguous)
        XCTAssertEqual(report.integrityStatus, .ambiguous)
        XCTAssertTrue(report.flags.contains(.legacyMultiBeatOrderUnknown))
        XCTAssertTrue(report.flags.contains(.mixedKnownUnknownOrder))
        XCTAssertTrue(report.flags.contains(.duplicateRecordedOrder))
    }

    func testUnknownOrderOnSingleBeatSecondsDoesNotDowngradeStructuralIntegrity() {
        let rows = [
            row(ts: 10, rrMs: 800, ord: nil),
            row(ts: 11, rrMs: 810, ord: nil),
            row(ts: 12, rrMs: 820, ord: nil),
        ]
        let report = RROrderAudit.evaluate(rows)
        XCTAssertEqual(report.integrityStatus, .complete)
        XCTAssertTrue(report.provenance.hasCompleteSameSecondOrder)
        XCTAssertFalse(report.flags.contains(.legacyMultiBeatOrderUnknown))
    }

    func testActualCleanCountSurvivesProductionGateAndReportsRejections() {
        let rows = [
            row(ts: 1, rrMs: 800, ord: 0),
            row(ts: 2, rrMs: 805, ord: 0),
            row(ts: 3, rrMs: 100, ord: 0),   // out of physiological range
            row(ts: 4, rrMs: 810, ord: 0),
            row(ts: 5, rrMs: 815, ord: 0),
        ]
        let report = RROrderAudit.evaluate(rows)
        XCTAssertEqual(report.currentOrder.nClean, 0)
        XCTAssertEqual(report.currentOrder.actualCleanCount, 4)
        XCTAssertEqual(report.currentOrder.rejectedCount, 1)
        XCTAssertEqual(report.currentOrder.rejectedFraction!, 0.2, accuracy: 1e-12)
        XCTAssertFalse(report.currentOrder.meetsProductionBeatGate)
        XCTAssertTrue(report.flags.contains(.cleaningRejectedIntervals))
    }

    func testRawMeanAndSdnnStayInvariantUnderReordering() {
        let rows = [
            row(ts: 20, rrMs: 900, ord: 2),
            row(ts: 20, rrMs: 700, ord: 0),
            row(ts: 20, rrMs: 850, ord: 1),
            row(ts: 21, rrMs: 810, ord: 0),
        ]
        let report = RROrderAudit.evaluate(rows)
        XCTAssertEqual(report.currentOrder.rawMeanNNMs!, report.magnitudeOrderCounterfactual.rawMeanNNMs!, accuracy: 1e-12)
        XCTAssertEqual(report.currentOrder.rawSdnnMs!, report.magnitudeOrderCounterfactual.rawSdnnMs!, accuracy: 1e-12)
        XCTAssertTrue(report.rawOrderInvariantPreserved)
        XCTAssertFalse(report.flags.contains(.rawOrderInvariantFailure))
    }

    func testInputOrderDoesNotChangeReport() {
        let rows = [
            row(ts: 11, rrMs: 840, seq: 0, ord: 2),
            row(ts: 10, rrMs: 812, seq: 0, ord: 0),
            row(ts: 11, rrMs: 795, seq: 0, ord: 0),
            row(ts: 10, rrMs: 801, seq: 0, ord: 1),
            row(ts: 11, rrMs: 833, seq: 0, ord: 1),
        ]
        XCTAssertEqual(RROrderAudit.evaluate(rows), RROrderAudit.evaluate(Array(rows.reversed())))
    }

    func testEqualValuesDoNotCountAsMagnitudeAffected() {
        let rows = [
            row(ts: 20, rrMs: 812, seq: 0, ord: 1),
            row(ts: 20, rrMs: 812, seq: 1, ord: 0),
        ]
        let report = RROrderAudit.evaluate(rows)
        let p = report.provenance
        XCTAssertEqual(p.trustworthyMultiBeatSeconds, 1)
        XCTAssertEqual(p.magnitudeReorderedTrustworthySeconds, 0)
        XCTAssertEqual(p.magnitudeReorderedTrustworthyIntervals, 0)
        XCTAssertEqual(report.permutationImpact.valueInversions, 0)
        XCTAssertEqual(report.permutationImpact.possibleValueInversions, 0)
        XCTAssertNil(report.permutationImpact.normalizedValueInversionFraction)
    }

    func testEmptyAuditHasExplicitNoDataStatusAndFlags() {
        let report = RROrderAudit.evaluate([])
        XCTAssertEqual(report.provenance.totalIntervals, 0)
        XCTAssertEqual(report.integrityStatus, .noData)
        XCTAssertNil(report.provenance.recordedOrderFraction)
        XCTAssertNil(report.provenance.trustworthyMultiBeatIntervalFraction)
        XCTAssertNil(report.provenance.spanSeconds)
        XCTAssertTrue(report.provenance.hasCompleteSameSecondOrder)
        XCTAssertNil(report.currentOrder.rawRmssdMs)
        XCTAssertNil(report.currentOrder.rmssdMs)
        XCTAssertNil(report.rawRmssdCurrentMinusMagnitudeMs)
        XCTAssertTrue(report.rawOrderInvariantPreserved)
        XCTAssertTrue(report.flags.contains(.noIntervals))
    }
}
