import Foundation
import StrandAnalytics
import WhoopStore
import XCTest
@testable import RROrderCorpusCore

final class RROrderCorpusCaptureReportTests: XCTestCase {
    func testCaptureAggregateCountsNativeVerdictsDuplicatesAndShadows() throws {
        let plausible = makeRecord(
            deviceKey: "device-001",
            rawDeviceID: "secret-plausible",
            start: 1_000,
            rows: (0..<20).map { RROrderAuditRow(ts: 1_010 + $0, rrMs: 1_000, seq: 0, emissionOrder: 0) }
        )

        var duplicateRows = (0..<20).map {
            RROrderAuditRow(ts: 100_010 + $0, rrMs: 1_000, seq: 0, emissionOrder: 0)
        }
        duplicateRows.append(RROrderAuditRow(ts: 100_020, rrMs: 1_000, seq: 1, emissionOrder: 1))
        let duplicate = makeRecord(
            deviceKey: "device-002",
            rawDeviceID: "secret-duplicate",
            start: 100_000,
            rows: duplicateRows
        )

        let report = try RROrderCorpusAnalysisReport.analyze([plausible, duplicate], bootstrapIterations: 0)
        let capture = report.capture

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.corpus.auditSchemaVersion, RROrderAuditReport.currentSchemaVersion)
        XCTAssertEqual(capture.verdictCounts[HRVAnalyzer.RrCoverageVerdict.plausible.rawValue], 1)
        XCTAssertEqual(capture.verdictCounts[HRVAnalyzer.RrCoverageVerdict.sameSecondOverCount.rawValue], 1)
        XCTAssertEqual(capture.exactDuplicateBeatRows, 1)
        XCTAssertEqual(capture.sessionsWithExactDuplicateBeatRows, 1)
        XCTAssertEqual(capture.sameSecondShadowDroppedRows, 1)
        XCTAssertEqual(capture.sessionsWithSameSecondShadowDrops, 1)
        XCTAssertGreaterThan(capture.crossSecondUpperBoundDroppedRows, 0)
        XCTAssertEqual(capture.sessionsWithCrossSecondUpperBoundDrops, 2)
        XCTAssertEqual(capture.verdictStrata.count, 2)

        let markdown = String(decoding: try RROrderCorpusAnalysisEncoder.encode(report, format: .markdown), as: UTF8.self)
        XCTAssertTrue(markdown.contains("Capture quality and over-count shadows"))
        XCTAssertTrue(markdown.contains("sameSecondOverCount"))
        XCTAssertTrue(markdown.contains("aggressive upper bound"))
        XCTAssertFalse(markdown.contains("secret-plausible"))
        XCTAssertFalse(markdown.contains("secret-duplicate"))

        let json = String(decoding: try RROrderCorpusAnalysisEncoder.encode(report, format: .json), as: UTF8.self)
        XCTAssertTrue(json.contains("\"capture\""))
        XCTAssertTrue(json.contains("\"verdictCounts\""))
        XCTAssertFalse(json.contains("secret-plausible"))
        XCTAssertFalse(json.contains("secret-duplicate"))
        XCTAssertFalse(json.contains("observationKey"))
    }

    func testFlatCsvCarriesCaptureDiagnosticsAlongsideOrderAndHrv() throws {
        var rows = (0..<20).map {
            RROrderAuditRow(ts: 2_000 + $0, rrMs: 1_000, seq: 0, emissionOrder: 0)
        }
        rows.append(RROrderAuditRow(ts: 2_010, rrMs: 1_000, seq: 1, emissionOrder: 1))
        let record = makeRecord(deviceKey: "device-001", rawDeviceID: "secret-device", start: 1_990, rows: rows)

        let csv = String(decoding: try RROrderCorpusEncoder.encode([record], format: .csv), as: UTF8.self)
        XCTAssertTrue(csv.contains("rr_coverage"))
        XCTAssertTrue(csv.contains("coverage_verdict"))
        XCTAssertTrue(csv.contains("beat_accurate_fraction"))
        XCTAssertTrue(csv.contains("exact_duplicate_beat_count"))
        XCTAssertTrue(csv.contains("same_second_shadow_dropped"))
        XCTAssertTrue(csv.contains("cross_second_upper_bound_dropped"))
        XCTAssertTrue(csv.contains("sameSecondOverCount"))
        XCTAssertFalse(csv.contains("secret-device"), "Raw IDs remain absent unless the caller explicitly opts in.")
    }

    func testEmptyCaptureReportIsDeterministicAndWellFormed() throws {
        let a = try RROrderCorpusAnalysisReport.analyze([], bootstrapIterations: 100)
        let b = try RROrderCorpusAnalysisReport.analyze([], bootstrapIterations: 100)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.capture.verdictCounts.isEmpty)
        XCTAssertNil(a.capture.coverage)
        XCTAssertNil(a.capture.beatAccurateFraction)
        XCTAssertEqual(a.capture.exactDuplicateBeatRows, 0)
        XCTAssertEqual(a.capture.crossSecondUpperBoundDroppedRows, 0)
        XCTAssertEqual(try RROrderCorpusAnalysisEncoder.encode(a, format: .json),
                       try RROrderCorpusAnalysisEncoder.encode(b, format: .json))
    }

    private func makeRecord(deviceKey: String, rawDeviceID: String, start: Int,
                            rows: [RROrderAuditRow]) -> RROrderCorpusRecord {
        let session = RROrderCorpusSleepSession(
            detectedStartTs: start,
            endTs: start + 8 * 3_600,
            cachedAvgHrvMs: nil,
            userEdited: false,
            startTsAdjusted: nil,
            stagingSparse: false
        )
        let window = RROrderCorpusAuditWindow(
            rows: rows,
            inputCounts: RROrderCorpusInputCounts(
                totalRowsInWindow: rows.count,
                scoringRows: rows.count,
                spo2IbiRows: 0,
                suspectTimestampRows: 0
            )
        )
        return RROrderCorpusRecord(
            deviceKey: deviceKey,
            rawDeviceID: rawDeviceID,
            includeDeviceID: false,
            session: session,
            window: window
        )
    }
}
