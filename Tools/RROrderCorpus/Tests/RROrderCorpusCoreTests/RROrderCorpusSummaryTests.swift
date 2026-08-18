import Foundation
import StrandAnalytics
import WhoopStore
import XCTest
@testable import RROrderCorpusCore

final class RROrderCorpusSummaryTests: XCTestCase {
    func testR7DistributionSummary() throws {
        let summary = try XCTUnwrap(RROrderDistributionSummary([0, 10, 20, 30]))
        XCTAssertEqual(summary.count, 4)
        XCTAssertEqual(summary.minimum, 0)
        XCTAssertEqual(summary.p10, 3, accuracy: 1e-12)
        XCTAssertEqual(summary.p25, 7.5, accuracy: 1e-12)
        XCTAssertEqual(summary.median, 15, accuracy: 1e-12)
        XCTAssertEqual(summary.p75, 22.5, accuracy: 1e-12)
        XCTAssertEqual(summary.p90, 27, accuracy: 1e-12)
        XCTAssertEqual(summary.maximum, 30)
        XCTAssertEqual(summary.mean, 15)
    }

    func testSummaryAggregatesIntegrityPermutationCleaningAndPrivacy() throws {
        let records = [
            makeRecord(deviceKey: "device-002", rawDeviceID: "secret-ring", start: 10_000,
                       pattern: [812, 795, 840, 801, 833], order: .recorded, duration: 3 * 3_600, sparse: true),
            makeRecord(deviceKey: "device-001", rawDeviceID: "secret-strap", start: 20_000,
                       pattern: [812, 795, 840, 801, 833], order: .legacyUnknown, duration: 7 * 3_600, sparse: false),
            makeRecord(deviceKey: "device-001", rawDeviceID: "secret-strap", start: 30_000,
                       pattern: [795, 801, 812, 833, 840], order: .recorded, duration: 9 * 3_600, sparse: nil),
        ]

        let summary = try RROrderCorpusSummary.summarize(records, bootstrapIterations: 200)
        XCTAssertEqual(summary.schemaVersion, 2)
        XCTAssertEqual(summary.recordCount, 3)
        XCTAssertEqual(summary.deviceCount, 2)
        XCTAssertEqual(summary.integrityCounts["complete"], 2)
        XCTAssertEqual(summary.integrityCounts["partial"], 1)
        XCTAssertGreaterThan(summary.permutation.trustworthyGroups, 0)
        XCTAssertGreaterThan(summary.permutation.valueInversions, 0)
        XCTAssertNotNil(summary.rmssd.delta.distribution)
        XCTAssertNotNil(summary.cleaning.currentRejectedFraction)
        XCTAssertEqual(summary.rawInvariantFailures, 0)
        XCTAssertEqual(summary.inputFilters.totalRows, 75)
        XCTAssertEqual(summary.inputFilters.scoringRows, 75)
        XCTAssertEqual(Set(summary.durationStrata.map(\.name)), Set(["duration:<4h", "duration:6-8h", "duration:8h+"]))
        XCTAssertEqual(Set(summary.stagingStrata.map(\.name)), Set(["staging:sparse", "staging:dense", "staging:unknown"]))

        let markdown = RROrderCorpusSummaryEncoder.markdown(summary)
        XCTAssertTrue(markdown.contains("Structural order integrity"))
        XCTAssertTrue(markdown.contains("Permutation severity"))
        XCTAssertTrue(markdown.contains("Downstream HRV sensitivity"))
        XCTAssertFalse(markdown.contains("secret-ring"))
        XCTAssertFalse(markdown.contains("secret-strap"))

        let json = String(decoding: try RROrderCorpusSummaryEncoder.encode(summary, format: .json), as: UTF8.self)
        XCTAssertFalse(json.contains("secret-ring"))
        XCTAssertFalse(json.contains("secret-strap"))
        XCTAssertFalse(json.contains("observationKey"), "Aggregate JSON must not contain per-session observations.")
    }

    func testBootstrapIsDeterministicAndBoundsObservedEffect() throws {
        var records: [RROrderCorpusRecord] = []
        for i in 0..<12 {
            let pattern = i.isMultiple(of: 3)
                ? [795, 801, 812, 833, 840]
                : [812, 795, 840, 801, 833]
            records.append(makeRecord(deviceKey: "device-001", rawDeviceID: "hidden", start: 10_000 + i * 90_000,
                                      pattern: pattern, order: .recorded, duration: 8 * 3_600, sparse: false))
        }
        let a = try RROrderCorpusSummary.summarize(records, bootstrapIterations: 500)
        let b = try RROrderCorpusSummary.summarize(records, bootstrapIterations: 500)
        XCTAssertEqual(a.rmssdDeltaBootstrap95, b.rmssdDeltaBootstrap95)
        let interval = try XCTUnwrap(a.rmssdDeltaBootstrap95.mean95)
        XCTAssertLessThanOrEqual(interval.lower, interval.upper)
        XCTAssertEqual(a.rmssdDeltaBootstrap95.iterations, 500)
    }

    func testAssociationsDetectMonotonicInversionSeverity() throws {
        let records = [
            makeRecord(deviceKey: "device-001", rawDeviceID: "h", start: 1_000,
                       pattern: [795, 801, 812, 833, 840], order: .recorded, duration: 8 * 3_600, sparse: false),
            makeRecord(deviceKey: "device-001", rawDeviceID: "h", start: 100_000,
                       pattern: [795, 833, 801, 812, 840], order: .recorded, duration: 8 * 3_600, sparse: false),
            makeRecord(deviceKey: "device-001", rawDeviceID: "h", start: 200_000,
                       pattern: [801, 833, 795, 840, 812], order: .recorded, duration: 8 * 3_600, sparse: false),
        ]
        let summary = try RROrderCorpusSummary.summarize(records, bootstrapIterations: 0)
        XCTAssertEqual(summary.associations.inversionPairCount, 3)
        XCTAssertEqual(try XCTUnwrap(summary.associations.inversionFractionVsAbsoluteRmssdDeltaSpearman), 1.0, accuracy: 1e-12)
    }

    func testReadinessAndChargeSensitivityUsePriorBaselineOnly() throws {
        var records: [RROrderCorpusRecord] = []
        for i in 0..<7 {
            records.append(makeRecord(deviceKey: "device-001", rawDeviceID: "hidden", start: 1_000 + i * 90_000,
                                      pattern: [812, 795, 840, 801, 833], order: .recorded,
                                      duration: 8 * 3_600, sparse: false))
        }
        records.append(makeRecord(deviceKey: "device-001", rawDeviceID: "hidden", start: 1_000 + 7 * 90_000,
                                  pattern: [812, 795, 840, 801, 833], order: .recorded,
                                  duration: 8 * 3_600, sparse: false))

        let summary = try RROrderCorpusSummary.summarize(records, bootstrapIterations: 0)
        let readiness = summary.downstreamSensitivity.readinessHrv
        XCTAssertEqual(readiness.evaluatedNights, 1)
        XCTAssertEqual(readiness.changedFlagNights, 1)
        XCTAssertEqual(readiness.transitionCounts["neutral->bad"], 1)
        XCTAssertLessThan(try XCTUnwrap(readiness.zDelta.distribution?.median), 5.0)
        XCTAssertGreaterThan(try XCTUnwrap(readiness.zDelta.distribution?.median), 0.0)

        let charge = summary.downstreamSensitivity.chargeHrv
        XCTAssertEqual(charge.evaluatedNights, 1)
        XCTAssertEqual(charge.minimumHrvWeightShare, 0.5, accuracy: 1e-12)
        XCTAssertEqual(charge.maximumHrvWeightShare, 1.0, accuracy: 1e-12)
        XCTAssertGreaterThan(try XCTUnwrap(charge.fullDriverSetScoreDelta.distribution?.median), 0)
        XCTAssertGreaterThan(try XCTUnwrap(charge.hrvOnlyScoreDelta.distribution?.median),
                             try XCTUnwrap(charge.fullDriverSetScoreDelta.distribution?.median))
    }

    func testJSONLinesRoundTripAndDuplicateFailsClosed() throws {
        let record = makeRecord(deviceKey: "device-001", rawDeviceID: "hidden", start: 1_000,
                                pattern: [812, 795, 840, 801, 833], order: .recorded,
                                duration: 8 * 3_600, sparse: false)
        let encoded = try RROrderCorpusEncoder.encode([record], format: .jsonl)
        let padded = Data(("\n" + String(decoding: encoded, as: UTF8.self) + "\n").utf8)
        XCTAssertEqual(try RROrderCorpusSummaryInput.decodeJSONLines(padded), [record])

        let duplicate = Data((String(decoding: encoded, as: UTF8.self) + String(decoding: encoded, as: UTF8.self)).utf8)
        XCTAssertThrowsError(try RROrderCorpusSummaryInput.decodeJSONLines(duplicate)) { error in
            guard case RROrderCorpusSummaryError.duplicateObservation(let key) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(key, record.observationKey)
        }
    }

    func testFutureRecordAndAuditSchemasFailClosed() throws {
        let record = makeRecord(deviceKey: "device-001", rawDeviceID: "hidden", start: 1_000,
                                pattern: [812, 795, 840, 801, 833], order: .recorded,
                                duration: 8 * 3_600, sparse: false)
        let data = try RROrderCorpusEncoder.encode([record], format: .jsonl)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 99
        let futureRecord = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try RROrderCorpusSummaryInput.decodeJSONLines(futureRecord))

        object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["auditSchemaVersion"] = 99
        let futureAudit = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try RROrderCorpusSummaryInput.decodeJSONLines(futureAudit))
    }

    func testEmptyCorpusIsDeterministic() throws {
        let a = try RROrderCorpusSummary.summarize([], bootstrapIterations: 100)
        let b = try RROrderCorpusSummary.summarize([], bootstrapIterations: 100)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.recordCount, 0)
        XCTAssertNil(a.rmssd.delta.distribution)
        XCTAssertNil(a.rmssdDeltaBootstrap95.mean95)
        XCTAssertEqual(a.downstreamSensitivity.readinessHrv.evaluatedNights, 0)
        XCTAssertEqual(try RROrderCorpusSummaryEncoder.encode(a, format: .json),
                       try RROrderCorpusSummaryEncoder.encode(b, format: .json))
    }

    private enum OrderShape { case recorded, legacyUnknown, duplicateRecorded }

    private func makeRecord(deviceKey: String, rawDeviceID: String, start: Int, pattern: [Int],
                            order: OrderShape, duration: Int, sparse: Bool?) -> RROrderCorpusRecord {
        var rows: [RROrderAuditRow] = []
        for secondOffset in 0..<5 {
            for (offset, rrMs) in pattern.enumerated() {
                let ord: Int?
                switch order {
                case .recorded: ord = offset
                case .legacyUnknown: ord = nil
                case .duplicateRecorded: ord = 0
                }
                rows.append(RROrderAuditRow(ts: start + 10 + secondOffset, rrMs: rrMs, seq: 0, emissionOrder: ord))
            }
        }
        let session = RROrderCorpusSleepSession(detectedStartTs: start, endTs: start + duration,
                                                cachedAvgHrvMs: nil, userEdited: false,
                                                startTsAdjusted: nil, stagingSparse: sparse)
        let window = RROrderCorpusAuditWindow(
            rows: rows,
            inputCounts: RROrderCorpusInputCounts(totalRowsInWindow: rows.count, scoringRows: rows.count,
                                                  spo2IbiRows: 0, suspectTimestampRows: 0))
        return RROrderCorpusRecord(deviceKey: deviceKey, rawDeviceID: rawDeviceID, includeDeviceID: true,
                                   session: session, window: window)
    }
}
