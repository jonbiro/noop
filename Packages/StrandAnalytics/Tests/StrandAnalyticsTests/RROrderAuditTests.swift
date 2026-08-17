import XCTest
@testable import StrandAnalytics
import WhoopStore

final class RROrderAuditTests: XCTestCase {
    private func row(ts: Int, rrMs: Int, seq: Int = 0, ord: Int?) -> RROrderAuditRow {
        RROrderAuditRow(ts: ts, rrMs: rrMs, seq: seq, emissionOrder: ord)
    }

    func testIssueExampleShowsMagnitudeOrderBiasAndPermutationSeverity() {
        let emission = [812, 795, 840, 801, 833]
        let rows = emission.enumerated().map { offset, value in row(ts: 100, rrMs: value, ord: offset) }
        let report = RROrderAudit.evaluate(rows)

        XCTAssertEqual(report.schemaVersion, 3)
        XCTAssertEqual(report.integrityStatus, .complete)
        XCTAssertEqual(report.currentOrder.rawRmssdMs!, 34.85, accuracy: 0.01)
        XCTAssertEqual(report.magnitudeOrderCounterfactual.rawRmssdMs!, 12.72, accuracy: 0.01)
        XCTAssertGreaterThan(report.rawRmssdCurrentMinusMagnitudeMs!, 20.0)
        XCTAssertEqual(report.currentOrder.actualCleanCount, 5)
        XCTAssertEqual(report.currentOrder.nClean, 0)
        XCTAssertEqual(report.currentOrder.contiguousPairCount, 4)
        XCTAssertFalse(report.currentOrder.meetsProductionBeatGate)
        XCTAssertEqual(report.permutationImpact.valueInversions, 4)
        XCTAssertEqual(report.permutationImpact.possibleValueInversions, 10)
        XCTAssertEqual(report.permutationImpact.normalizedValueInversionFraction!, 0.4, accuracy: 1e-12)
        XCTAssertTrue(report.rawOrderInvariantPreserved)
        XCTAssertTrue(report.flags.contains(.currentBelowProductionBeatGate))
        XCTAssertTrue(report.flags.contains(.counterfactualBelowProductionBeatGate))
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

    func testNativeCoverageDiagnosticsRecognizePlausibleBeatAccurateCapture() {
        let rows = (0..<20).map { second in row(ts: second, rrMs: 1_000, ord: 0) }
        let report = RROrderAudit.evaluate(rows)
        let capture = report.captureDiagnostics

        XCTAssertEqual(capture.coverage, 20.0 / 19.0, accuracy: 1e-12)
        XCTAssertEqual(capture.coverageVerdict, HRVAnalyzer.RrCoverageVerdict.plausible.rawValue)
        XCTAssertTrue(capture.beatSpreadTrustworthy)
        XCTAssertEqual(capture.beatAccurateFraction, 1.0, accuracy: 1e-12)
        XCTAssertTrue(capture.beatValuesTrustworthy)
        XCTAssertEqual(capture.exactDuplicateBeatCount, 0)
        XCTAssertEqual(capture.sameSecondShadowDropped, 0)
        // The upstream 1-second shadow is intentionally aggressive: at a perfectly steady 1 s rhythm it
        // drops legitimate neighbours. Its job is to size an upper bound, never to be a shipped de-dup.
        XCTAssertGreaterThan(capture.crossSecondUpperBoundDropped, 0)
        XCTAssertTrue(report.flags.contains(.crossSecondUpperBoundDropsRows))
        XCTAssertFalse(report.flags.contains(.captureSameSecondOverCount))
        XCTAssertFalse(report.flags.contains(.captureCrossSecondOverCount))
    }

    func testNativeCoverageDiagnosticsRecognizeExactSameSecondOverCount() {
        var rows = (0..<20).map { second in row(ts: second, rrMs: 1_000, seq: 0, ord: 0) }
        rows.append(row(ts: 10, rrMs: 1_000, seq: 1, ord: 1))
        let report = RROrderAudit.evaluate(rows)
        let capture = report.captureDiagnostics

        XCTAssertEqual(capture.exactDuplicateBeatCount, 1)
        XCTAssertEqual(capture.coverageVerdict, HRVAnalyzer.RrCoverageVerdict.sameSecondOverCount.rawValue)
        XCTAssertFalse(capture.beatSpreadTrustworthy)
        XCTAssertEqual(capture.sameSecondShadowDropped, 1)
        XCTAssertTrue(report.flags.contains(.captureSameSecondOverCount))
        XCTAssertTrue(report.flags.contains(.exactDuplicateBeatRows))
        XCTAssertTrue(report.flags.contains(.sameSecondShadowDropsRows))
    }

    func testBankedTimestampShapeFailsBeatTimingTrustEvenWhenOrderIsKnown() {
        let rows = (0..<20).map { offset in row(ts: 100 + offset / 5, rrMs: 800, seq: 0, ord: offset % 5) }
        let report = RROrderAudit.evaluate(rows)
        XCTAssertLessThan(report.captureDiagnostics.beatAccurateFraction, HRVAnalyzer.beatAccuracyMinFraction)
        XCTAssertFalse(report.captureDiagnostics.beatValuesTrustworthy)
        XCTAssertTrue(report.flags.contains(.beatTimingUntrustworthy))
    }

    func testProvenancePartitionsEveryMultiBeatSecondAndAssignsAmbiguousStatus() {
        let rows = [
            row(ts: 1, rrMs: 800, ord: nil),
            row(ts: 2, rrMs: 812, ord: 2), row(ts: 2, rrMs: 795, ord: 7),
            row(ts: 3, rrMs: 801, ord: nil), row(ts: 3, rrMs: 833, ord: nil),
            row(ts: 4, rrMs: 802, ord: nil), row(ts: 4, rrMs: 834, ord: 0),
            row(ts: 5, rrMs: 803, ord: 0), row(ts: 5, rrMs: 835, ord: 0),
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
        XCTAssertEqual(report.integrityStatus, .ambiguous)
        XCTAssertTrue(report.flags.contains(.legacyMultiBeatOrderUnknown))
        XCTAssertTrue(report.flags.contains(.mixedKnownUnknownOrder))
        XCTAssertTrue(report.flags.contains(.duplicateRecordedOrder))
    }

    func testUnknownOrderOnSingleBeatSecondsDoesNotDowngradeStructuralIntegrity() {
        let rows = [row(ts: 10, rrMs: 800, ord: nil), row(ts: 11, rrMs: 810, ord: nil), row(ts: 12, rrMs: 820, ord: nil)]
        let report = RROrderAudit.evaluate(rows)
        XCTAssertEqual(report.integrityStatus, .complete)
        XCTAssertTrue(report.provenance.hasCompleteSameSecondOrder)
        XCTAssertFalse(report.flags.contains(.legacyMultiBeatOrderUnknown))
    }

    func testActualCleanCountSurvivesProductionGateAndReportsRejections() {
        let rows = [
            row(ts: 1, rrMs: 800, ord: 0), row(ts: 2, rrMs: 805, ord: 0),
            row(ts: 3, rrMs: 100, ord: 0), row(ts: 4, rrMs: 810, ord: 0), row(ts: 5, rrMs: 815, ord: 0),
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
            row(ts: 20, rrMs: 900, ord: 2), row(ts: 20, rrMs: 700, ord: 0),
            row(ts: 20, rrMs: 850, ord: 1), row(ts: 21, rrMs: 810, ord: 0),
        ]
        let report = RROrderAudit.evaluate(rows)
        XCTAssertEqual(report.currentOrder.rawMeanNNMs!, report.magnitudeOrderCounterfactual.rawMeanNNMs!, accuracy: 1e-12)
        XCTAssertEqual(report.currentOrder.rawSdnnMs!, report.magnitudeOrderCounterfactual.rawSdnnMs!, accuracy: 1e-12)
        XCTAssertTrue(report.rawOrderInvariantPreserved)
        XCTAssertFalse(report.flags.contains(.rawOrderInvariantFailure))
    }

    func testInputOrderDoesNotChangeReport() {
        let rows = [
            row(ts: 11, rrMs: 840, seq: 0, ord: 2), row(ts: 10, rrMs: 812, seq: 0, ord: 0),
            row(ts: 11, rrMs: 795, seq: 0, ord: 0), row(ts: 10, rrMs: 801, seq: 0, ord: 1),
            row(ts: 11, rrMs: 833, seq: 0, ord: 1),
        ]
        XCTAssertEqual(RROrderAudit.evaluate(rows), RROrderAudit.evaluate(Array(rows.reversed())))
    }

    func testEqualValuesDoNotCountAsMagnitudeAffected() {
        let rows = [row(ts: 20, rrMs: 812, seq: 0, ord: 1), row(ts: 20, rrMs: 812, seq: 1, ord: 0)]
        let report = RROrderAudit.evaluate(rows)
        XCTAssertEqual(report.provenance.trustworthyMultiBeatSeconds, 1)
        XCTAssertEqual(report.provenance.magnitudeReorderedTrustworthySeconds, 0)
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
        XCTAssertTrue(report.rawOrderInvariantPreserved)
        XCTAssertEqual(report.captureDiagnostics.coverageVerdict, HRVAnalyzer.RrCoverageVerdict.unmeasurable.rawValue)
        XCTAssertTrue(report.flags.contains(.noIntervals))
    }
}
