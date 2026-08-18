import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore
import XCTest
@testable import RROrderCorpusCore

final class RROrderCorpusCoreTests: XCTestCase {
    func testReadOnlyDatabaseMatchesProductionAuditReadAndCountsExcludedRows() async throws {
        let path = temporaryDatabasePath()
        defer { removeDatabaseAndSidecars(path) }

        let store = try await WhoopStore(path: path)
        try await store.upsertDevice(id: "dev-a", mac: nil, name: nil)
        _ = try await store.upsertSleepSessions([
            CachedSleepSession(startTs: 100, endTs: 220, efficiency: 0.9, restingHr: 50,
                               avgHrv: 42, stagesJSON: nil, stagingSparse: false),
        ], deviceId: "dev-a")
        _ = try await store.insert(
            Streams(rr: [
                RRInterval(ts: 110, rrMs: 812),
                RRInterval(ts: 110, rrMs: 795),
                RRInterval(ts: 111, rrMs: 840),
            ]),
            deviceId: "dev-a"
        )
        try await store.checkpointWAL()

        let expected = try await store.rrOrderAuditRows(deviceId: "dev-a", from: 100, to: 220)
        let readOnly = try RROrderCorpusDatabase(path: path)
        let auditWindow = try readOnly.rrOrderAuditWindow(deviceID: "dev-a", from: 100, to: 220)

        XCTAssertEqual(auditWindow.rows, expected)
        XCTAssertEqual(auditWindow.inputCounts.totalRowsInWindow, expected.count)
        XCTAssertEqual(auditWindow.inputCounts.scoringRows, expected.count)
        XCTAssertEqual(auditWindow.inputCounts.excludedRows, 0)
        XCTAssertEqual(auditWindow.inputCounts.scoringFraction, 1)
        XCTAssertGreaterThanOrEqual(readOnly.userVersion, 0)
        XCTAssertEqual(try readOnly.deviceIDs(from: 0, to: 1_000), ["dev-a"])
    }

    func testRunnerUsesEditedStartPseudonymizesAndEmitsSchemaV2() async throws {
        let path = temporaryDatabasePath()
        defer { removeDatabaseAndSidecars(path) }
        let store = try await WhoopStore(path: path)
        try await store.upsertDevice(id: "private-device-id", mac: nil, name: nil)
        _ = try await store.upsertSleepSessions([
            CachedSleepSession(startTs: 100, endTs: 400, efficiency: 0.8, restingHr: 52,
                               avgHrv: 31, stagesJSON: nil, userEdited: true,
                               startTsAdjusted: 120, stagingSparse: true),
        ], deviceId: "private-device-id")
        _ = try await store.insert(
            Streams(rr: [
                RRInterval(ts: 110, rrMs: 700),
                RRInterval(ts: 120, rrMs: 812),
                RRInterval(ts: 120, rrMs: 795),
                RRInterval(ts: 121, rrMs: 840),
            ]), deviceId: "private-device-id")
        try await store.checkpointWAL()

        let result = try RROrderCorpusRunner.run(
            database: RROrderCorpusDatabase(path: path), requestedDeviceIDs: ["private-device-id"],
            from: 0, to: 1_000, sessionLimitPerDevice: 10, minimumDurationSeconds: 0,
            includeDeviceID: false)

        let record = try XCTUnwrap(result.records.first)
        XCTAssertEqual(record.schemaVersion, 2)
        XCTAssertEqual(record.auditSchemaVersion, RROrderAuditReport.currentSchemaVersion)
        XCTAssertEqual(record.observationKey, "device-001:100:400")
        XCTAssertEqual(record.deviceKey, "device-001")
        XCTAssertNil(record.deviceID)
        XCTAssertEqual(record.effectiveStartTs, 120)
        XCTAssertEqual(record.durationSeconds, 280)
        XCTAssertEqual(record.audit.provenance.totalIntervals, 3)
        XCTAssertEqual(record.inputCounts.scoringRows, 3)
        XCTAssertEqual(result.summary.recordsWritten, 1)
        XCTAssertEqual(result.summary.integrity.complete + result.summary.integrity.partial
                       + result.summary.integrity.ambiguous + result.summary.integrity.noData, 1)
    }

    func testJSONAndCSVNeverContainRawIntervalSequence() throws {
        let record = makeRecord(includeDeviceID: false)
        let json = String(decoding: try RROrderCorpusEncoder.encode([record], format: .jsonl), as: UTF8.self)
        XCTAssertFalse(json.contains("secret-device-id"))
        XCTAssertFalse(json.contains("\"rrMs\""), "Raw interval rows must never be serialized.")
        XCTAssertTrue(json.contains("\"integrityStatus\""))
        XCTAssertTrue(json.contains("\"permutationImpact\""))
        XCTAssertTrue(json.contains("\"actualCleanCount\""))

        let visible = makeRecord(includeDeviceID: true, rawDeviceID: "device,\"alpha\"")
        let csv = String(decoding: try RROrderCorpusEncoder.encode([visible], format: .csv), as: UTF8.self)
        XCTAssertTrue(csv.contains("\"device,\"\"alpha\"\"\""))
        XCTAssertTrue(csv.contains("integrity_status"))
        XCTAssertTrue(csv.contains("normalized_inversion_fraction"))
        XCTAssertTrue(csv.contains("current_actual_clean_count"))
        XCTAssertTrue(csv.hasSuffix("\n"))
    }

    func testRunnerAccountsForShortAndInvalidSessions() async throws {
        let path = temporaryDatabasePath()
        defer { removeDatabaseAndSidecars(path) }
        let store = try await WhoopStore(path: path)
        try await store.upsertDevice(id: "dev", mac: nil, name: nil)
        _ = try await store.upsertSleepSessions([
            CachedSleepSession(startTs: 100, endTs: 160, efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil),
            CachedSleepSession(startTs: 200, endTs: 190, efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil),
        ], deviceId: "dev")
        _ = try await store.insert(Streams(rr: [RRInterval(ts: 110, rrMs: 800)]), deviceId: "dev")
        try await store.checkpointWAL()

        let result = try RROrderCorpusRunner.run(
            database: RROrderCorpusDatabase(path: path), requestedDeviceIDs: ["dev"], from: 0, to: 1_000,
            sessionLimitPerDevice: 10, minimumDurationSeconds: 120, includeDeviceID: false)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.summary.sessionsExamined, 2)
        XCTAssertEqual(result.summary.sessionsBelowMinimumDuration, 1)
        XCTAssertEqual(result.summary.invalidSessionWindows, 1)
    }

    func testReadOnlyOpenDoesNotMutateDatabaseOrSidecarState() async throws {
        let path = temporaryDatabasePath()
        defer { removeDatabaseAndSidecars(path) }
        let store = try await WhoopStore(path: path)
        try await store.upsertDevice(id: "dev", mac: nil, name: nil)
        try await store.checkpointWAL()

        let beforeDatabase = try Data(contentsOf: URL(fileURLWithPath: path))
        let beforeSidecars = sidecarSnapshot(path)
        _ = try RROrderCorpusDatabase(path: path)
        let afterDatabase = try Data(contentsOf: URL(fileURLWithPath: path))
        let afterSidecars = sidecarSnapshot(path)

        XCTAssertEqual(beforeDatabase, afterDatabase)
        XCTAssertEqual(beforeSidecars, afterSidecars,
                       "Read-only corpus access must not create, remove, or resize WAL/SHM/journal files.")
    }

    func testMissingSchemaFailsClearly() throws {
        let path = temporaryDatabasePath()
        defer { removeDatabaseAndSidecars(path) }
        FileManager.default.createFile(atPath: path, contents: Data())
        XCTAssertThrowsError(try RROrderCorpusDatabase(path: path)) { error in
            guard case RROrderCorpusDatabaseError.incompatibleSchema(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("missing required table"))
        }
    }

    private func makeRecord(includeDeviceID: Bool, rawDeviceID: String = "secret-device-id") -> RROrderCorpusRecord {
        let session = RROrderCorpusSleepSession(detectedStartTs: 1_000, endTs: 4_600, cachedAvgHrvMs: 40,
                                                userEdited: false, startTsAdjusted: nil, stagingSparse: false)
        var rows: [RROrderAuditRow] = []
        let pattern = [812, 795, 840, 801, 833]
        for second in 0..<5 {
            for (offset, value) in pattern.enumerated() {
                rows.append(RROrderAuditRow(ts: 1_010 + second, rrMs: value, seq: 0, emissionOrder: offset))
            }
        }
        let window = RROrderCorpusAuditWindow(
            rows: rows,
            inputCounts: RROrderCorpusInputCounts(totalRowsInWindow: rows.count, scoringRows: rows.count,
                                                  spo2IbiRows: 0, suspectTimestampRows: 0))
        return RROrderCorpusRecord(deviceKey: "device-001", rawDeviceID: rawDeviceID,
                                   includeDeviceID: includeDeviceID, session: session, window: window)
    }

    private func temporaryDatabasePath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("rr-order-corpus-\(UUID().uuidString).sqlite").path
    }

    private func sidecarSnapshot(_ path: String) -> [String: UInt64?] {
        Dictionary(uniqueKeysWithValues: ["-wal", "-shm", "-journal"].map { suffix in
            let file = path + suffix
            let attributes = try? FileManager.default.attributesOfItem(atPath: file)
            return (suffix, (attributes?[.size] as? NSNumber)?.uint64Value)
        })
    }

    private func removeDatabaseAndSidecars(_ path: String) {
        for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: path + suffix) }
    }
}
