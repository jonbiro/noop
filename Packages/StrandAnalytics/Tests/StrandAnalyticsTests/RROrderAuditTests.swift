import XCTest
@testable import StrandAnalytics
import WhoopStore

final class RROrderAuditTests: XCTestCase {
    private func row(ts: Int, rrMs: Int, seq: Int = 0, ord: Int?) -> RROrderAuditRow {
        RROrderAuditRow(ts: ts, rrMs: rrMs, seq: seq, emissionOrder: ord)
    }

    func testIssueExampleShowsMagnitudeOrderBiasInRawRmssd() {
        let emission = [812, 795, 840, 801, 833]
        let rows = emission.enumerated().map { offset, value in
            row(ts: 100, rrMs: value, ord: offset)
        }

        let report = RROrderAudit.evaluate(rows)

        XCTAssertEqual(report.currentOrder.rawRmssdMs!, 34.85, accuracy: 0.01)
        XCTAssertEqual(report.magnitudeOrderCounterfactual.rawRmssdMs!, 12.72, accuracy: 0.01)
        XCTAssertGreaterThan(report.rawRmssdCurrentMinusMagnitudeMs!, 20.0)
        XCTAssertEqual(report.provenance.trustworthyMultiBeatSeconds, 1)
        XCTAssertEqual(report.provenance.magnitudeReorderedTrustworthySeconds, 1)
        // Five beats are intentionally below the production 20-beat gate; raw RMSSD remains measurable.
        XCTAssertNil(report.currentOrder.rmssdMs)
        XCTAssertNil(report.magnitudeOrderCounterfactual.rmssdMs)
    }

    func testProductionPipelineCounterfactualUsesTwentyBeatGateAndCleaning() {
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
        XCTAssertNotNil(report.currentOrder.rmssdMs)
        XCTAssertNotNil(report.magnitudeOrderCounterfactual.rmssdMs)
        XCTAssertGreaterThan(
            report.currentOrder.rmssdMs!,
            report.magnitudeOrderCounterfactual.rmssdMs!
        )
        XCTAssertGreaterThan(report.rmssdCurrentMinusMagnitudeMs!, 10.0)
        XCTAssertEqual(report.provenance.trustworthyMultiBeatSeconds, 4)
        XCTAssertTrue(report.provenance.hasCompleteSameSecondOrder)
    }

    func testProvenancePartitionsEveryMultiBeatSecond() {
        let rows = [
            row(ts: 1, rrMs: 800, ord: nil),                                      // single
            row(ts: 2, rrMs: 812, ord: 2), row(ts: 2, rrMs: 795, ord: 7),         // trustworthy, gaps OK
            row(ts: 3, rrMs: 801, ord: nil), row(ts: 3, rrMs: 833, ord: nil),     // all unknown
            row(ts: 4, rrMs: 802, ord: nil), row(ts: 4, rrMs: 834, ord: 0),       // mixed
            row(ts: 5, rrMs: 803, ord: 0), row(ts: 5, rrMs: 835, ord: 0),         // split-batch ambiguous
        ]

        let p = RROrderAudit.evaluate(rows).provenance

        XCTAssertEqual(p.totalIntervals, 9)
        XCTAssertEqual(p.intervalsWithRecordedOrder, 5)
        XCTAssertEqual(p.intervalsWithUnknownOrder, 4)
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
        let p = RROrderAudit.evaluate(rows).provenance
        XCTAssertEqual(p.trustworthyMultiBeatSeconds, 1)
        XCTAssertEqual(p.magnitudeReorderedTrustworthySeconds, 0)
        XCTAssertEqual(p.magnitudeReorderedTrustworthyIntervals, 0)
    }

    func testEmptyAuditHasNoFractionsOrHrv() {
        let report = RROrderAudit.evaluate([])
        XCTAssertEqual(report.provenance.totalIntervals, 0)
        XCTAssertNil(report.provenance.recordedOrderFraction)
        XCTAssertNil(report.provenance.trustworthyMultiBeatIntervalFraction)
        XCTAssertTrue(report.provenance.hasCompleteSameSecondOrder)
        XCTAssertNil(report.currentOrder.rawRmssdMs)
        XCTAssertNil(report.currentOrder.rmssdMs)
        XCTAssertNil(report.rawRmssdCurrentMinusMagnitudeMs)
    }
}
