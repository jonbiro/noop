import Foundation
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
        XCTAssertEqual(try XCTUnwrap(summary.sampleStdDev), 12.909944487358056, accuracy: 1e-12)
    }

    func testSummaryAggregatesProvenanceAndHrvWithoutRawIdentifiers() throws {
        let records = [
            makeRecord(
                deviceKey: "device-002",
                rawDeviceID: "secret-ring-id",
                start: 10_000,
                pattern: [812, 795, 840, 801, 833],
                order: .recorded,
                cachedHrv: 40
            ),
            makeRecord(
                deviceKey: "device-001",
                rawDeviceID: "secret-strap-id",
                start: 20_000,
                pattern: [812, 795, 840, 801, 833],
                order: .legacyUnknown,
                cachedHrv: 35
            ),
            makeRecord(
                deviceKey: "device-001",
                rawDeviceID: "secret-strap-id",
                start: 30_000,
                pattern: [795, 801, 812, 833, 840],
                order: .recorded,
                cachedHrv: nil
            ),
        ]

        let summary = try RROrderCorpusSummary.summarize(records)
        XCTAssertEqual(summary.recordCount, 3)
        XCTAssertEqual(summary.deviceCount, 2)
        XCTAssertEqual(summary.devices.map(\.deviceKey), ["device-001", "device-002"])
        XCTAssertEqual(summary.provenance.totalIntervals, 75)
        XCTAssertEqual(summary.provenance.intervalsWithRecordedOrder, 50)
        XCTAssertEqual(summary.provenance.intervalsWithUnknownOrder, 25)
        XCTAssertEqual(
            try XCTUnwrap(summary.provenance.weightedRecordedOrderFraction),
            2.0 / 3.0,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(summary.provenance.weightedTrustworthyMultiBeatIntervalFraction),
            2.0 / 3.0,
            accuracy: 1e-12
        )
        XCTAssertEqual(summary.provenance.sessionsWithCompleteSameSecondOrder, 2)
        XCTAssertEqual(summary.provenance.sessionsWithLegacyUnknownGroups, 1)
        XCTAssertEqual(summary.hrv.pairedProductionCount, 3)
        XCTAssertEqual(summary.hrv.currentMinusMagnitudeMs.positiveCount, 1)
        XCTAssertEqual(summary.hrv.currentMinusMagnitudeMs.zeroCount, 2)
        XCTAssertEqual(summary.hrv.currentMinusMagnitudeMs.negativeCount, 0)
        XCTAssertEqual(summary.hrv.cachedAvailableCount, 2)
        XCTAssertEqual(summary.hrv.pairedCurrentAndCachedCount, 2)
        XCTAssertGreaterThan(summary.hrv.absoluteDeltaMsExceedance[0].count, 0)

        let markdown = RROrderCorpusSummaryEncoder.markdown(summary)
        XCTAssertTrue(markdown.contains("# R-R order corpus summary"))
        XCTAssertTrue(markdown.contains("device-001"))
        XCTAssertTrue(markdown.contains("device-002"))
        XCTAssertFalse(markdown.contains("secret-ring-id"))
        XCTAssertFalse(markdown.contains("secret-strap-id"))

        let json = String(
            decoding: try RROrderCorpusSummaryEncoder.encode(summary, format: .json),
            as: UTF8.self
        )
        XCTAssertFalse(json.contains("secret-ring-id"))
        XCTAssertFalse(json.contains("secret-strap-id"))
        XCTAssertFalse(json.contains("detectedStartTs"), "Summary JSON must not contain per-session observations.")
        XCTAssertFalse(json.contains("rrMs"), "Summary JSON must not contain raw interval rows.")
    }

    func testJSONLinesRoundTripIgnoresBlankLines() throws {
        let records = [
            makeRecord(deviceKey: "device-001", rawDeviceID: "hidden", start: 1_000,
                       pattern: [812, 795, 840, 801, 833], order: .recorded, cachedHrv: nil),
            makeRecord(deviceKey: "device-001", rawDeviceID: "hidden", start: 2_000,
                       pattern: [795, 801, 812, 833, 840], order: .recorded, cachedHrv: nil),
        ]
        let encoded = try RROrderCorpusEncoder.encode(records, format: .jsonl)
        let padded = Data(("\n" + String(decoding: encoded, as: UTF8.self) + "\n").utf8)
        XCTAssertEqual(try RROrderCorpusSummaryInput.decodeJSONLines(padded), records)
    }

    func testDuplicateObservationFailsClosed() throws {
        let record = makeRecord(
            deviceKey: "device-001",
            rawDeviceID: "hidden",
            start: 1_000,
            pattern: [812, 795, 840, 801, 833],
            order: .recorded,
            cachedHrv: nil
        )
        let once = String(
            decoding: try RROrderCorpusEncoder.encode([record], format: .jsonl),
            as: UTF8.self
        )
        let duplicate = Data((once + once).utf8)

        XCTAssertThrowsError(try RROrderCorpusSummaryInput.decodeJSONLines(duplicate)) { error in
            guard case RROrderCorpusSummaryError.duplicateObservation(
                let deviceKey,
                let detectedStartTs,
                _
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(deviceKey, "device-001")
            XCTAssertEqual(detectedStartTs, 1_000)
        }
    }

    func testMalformedAndFutureSchemaLinesFailClearly() throws {
        XCTAssertThrowsError(
            try RROrderCorpusSummaryInput.decodeJSONLines(Data("{not-json}\n".utf8))
        ) { error in
            guard case RROrderCorpusSummaryError.invalidJSONLine(let line, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(line, 1)
        }

        let record = makeRecord(
            deviceKey: "device-001",
            rawDeviceID: "hidden",
            start: 1_000,
            pattern: [812, 795, 840, 801, 833],
            order: .recorded,
            cachedHrv: nil
        )
        let current = String(
            decoding: try RROrderCorpusEncoder.encode([record], format: .jsonl),
            as: UTF8.self
        )
        let future = current.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")
        XCTAssertNotEqual(current, future, "Fixture must actually change the schema version.")
        XCTAssertThrowsError(
            try RROrderCorpusSummaryInput.decodeJSONLines(Data(future.utf8))
        ) { error in
            XCTAssertEqual(error as? RROrderCorpusSummaryError,
                           .unsupportedRecordSchema(line: 1, version: 2))
        }
    }

    func testEmptyCorpusProducesDeterministicAggregateOnlyReport() throws {
        let summary = try RROrderCorpusSummary.summarize([])
        XCTAssertEqual(summary.recordCount, 0)
        XCTAssertEqual(summary.deviceCount, 0)
        XCTAssertNil(summary.durationSeconds)
        XCTAssertEqual(summary.hrv.pairedProductionCount, 0)
        XCTAssertTrue(summary.devices.isEmpty)

        let first = try RROrderCorpusSummaryEncoder.encode(summary, format: .json)
        let second = try RROrderCorpusSummaryEncoder.encode(summary, format: .json)
        XCTAssertEqual(first, second)
        let markdown = RROrderCorpusSummaryEncoder.markdown(summary)
        XCTAssertTrue(markdown.contains("Sessions: 0"))
        XCTAssertTrue(markdown.contains("| n/a | 0 |"))
    }

    private enum OrderShape {
        case recorded
        case legacyUnknown
        case duplicateRecorded
    }

    private func makeRecord(
        deviceKey: String,
        rawDeviceID: String,
        start: Int,
        pattern: [Int],
        order: OrderShape,
        cachedHrv: Double?
    ) -> RROrderCorpusRecord {
        var rows: [RROrderAuditRow] = []
        for secondOffset in 0..<5 {
            for (offset, rrMs) in pattern.enumerated() {
                let emissionOrder: Int?
                switch order {
                case .recorded: emissionOrder = offset
                case .legacyUnknown: emissionOrder = nil
                case .duplicateRecorded: emissionOrder = 0
                }
                rows.append(RROrderAuditRow(
                    ts: start + 10 + secondOffset,
                    rrMs: rrMs,
                    seq: 0,
                    emissionOrder: emissionOrder
                ))
            }
        }
        let session = RROrderCorpusSleepSession(
            detectedStartTs: start,
            endTs: start + 3_600,
            cachedAvgHrvMs: cachedHrv,
            userEdited: start.isMultiple(of: 2),
            startTsAdjusted: nil,
            stagingSparse: start.isMultiple(of: 3) ? true : false
        )
        return RROrderCorpusRecord(
            deviceKey: deviceKey,
            rawDeviceID: rawDeviceID,
            includeDeviceID: true,
            session: session,
            rows: rows
        )
    }
}
