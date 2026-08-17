import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore
import XCTest
@testable import RROrderCorpusCore

final class RROrderCorpusCoreTests: XCTestCase {
    func testReadOnlyDatabaseMatchesProductionAuditRead() async throws {
        let path = temporaryDatabasePath()
        defer { removeDatabaseAndSidecars(path) }

        let store = try await WhoopStore(path: path)
        try await store.upsertDevice(id: "dev-a", mac: nil, name: nil)
        _ = try await store.upsertSleepSessions([
            CachedSleepSession(
                startTs: 100,
                endTs: 200,
                efficiency: 0.9,
                restingHr: 50,
                avgHrv: 42,
                stagesJSON: nil,
                stagingSparse: false
            ),
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

        let expected = try await store.rrOrderAuditRows(deviceId: "dev-a", from: 100, to: 200)
        let readOnly = try RROrderCorpusDatabase(path: path)

        XCTAssertEqual(try readOnly.deviceIDs(from: 0, to: 1_000), ["dev-a"])
        XCTAssertEqual(
            try readOnly.rrOrderAuditRows(deviceID: "dev-a", from: 100, to: 200),
            expected,
            "The corpus query must stay byte-for-byte equivalent to the production audit population."
        )

        let sessions = try readOnly.sleepSessions(deviceID: "dev-a", from: 0, to: 1_000, limit: 10)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].cachedAvgHrvMs, 42)
        XCTAssertEqual(sessions[0].stagingSparse, false)
    }

    func testRunnerUsesEditedStartAndPseudonymizesByDefault() async throws {
        let path = temporaryDatabasePath()
        defer { removeDatabaseAndSidecars(path) }

        let store = try await WhoopStore(path: path)
        try await store.upsertDevice(id: "private-device-id", mac: nil, name: nil)
        _ = try await store.upsertSleepSessions([
            CachedSleepSession(
                startTs: 100,
                endTs: 220,
                efficiency: 0.8,
                restingHr: 52,
                avgHrv: 31,
                stagesJSON: nil,
                userEdited: true,
                startTsAdjusted: 120,
                stagingSparse: true
            ),
        ], deviceId: "private-device-id")
        _ = try await store.insert(
            Streams(rr: [
                RRInterval(ts: 110, rrMs: 700), // Before the corrected onset: must not enter the audit.
                RRInterval(ts: 120, rrMs: 812),
                RRInterval(ts: 120, rrMs: 795),
                RRInterval(ts: 121, rrMs: 840),
            ]),
            deviceId: "private-device-id"
        )
        try await store.checkpointWAL()

        let database = try RROrderCorpusDatabase(path: path)
        let result = try RROrderCorpusRunner.run(
            database: database,
            requestedDeviceIDs: ["private-device-id"],
            from: 0,
            to: 1_000,
            sessionLimitPerDevice: 10,
            minimumDurationSeconds: 0,
            includeDeviceID: false
        )

        let record = try XCTUnwrap(result.records.first)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(record.deviceKey, "device-001")
        XCTAssertNil(record.deviceID)
        XCTAssertEqual(record.detectedStartTs, 100)
        XCTAssertEqual(record.effectiveStartTs, 120)
        XCTAssertEqual(record.durationSeconds, 100)
        XCTAssertTrue(record.userEdited)
        XCTAssertEqual(record.stagingSparse, true)
        XCTAssertEqual(record.audit.provenance.totalIntervals, 3)
        XCTAssertEqual(result.summary.totalIntervals, 3)
    }

    func testAggregateOutputDoesNotLeakRawRowsOrDeviceIDWithoutOptIn() throws {
        let session = RROrderCorpusSleepSession(
            detectedStartTs: 1_000,
            endTs: 1_200,
            cachedAvgHrvMs: 40,
            userEdited: false,
            startTsAdjusted: nil,
            stagingSparse: nil
        )
        let rows = [
            RROrderAuditRow(ts: 1_010, rrMs: 812, seq: 0, emissionOrder: 0),
            RROrderAuditRow(ts: 1_010, rrMs: 795, seq: 0, emissionOrder: 1),
        ]
        let hidden = RROrderCorpusRecord(
            deviceKey: "device-001",
            rawDeviceID: "secret-device-id",
            includeDeviceID: false,
            session: session,
            rows: rows
        )
        let json = String(decoding: try RROrderCorpusEncoder.encode([hidden], format: .jsonl), as: UTF8.self)
        XCTAssertFalse(json.contains("secret-device-id"))
        XCTAssertFalse(json.contains("rrMs"), "Only aggregate audit output should be serialized.")
        XCTAssertFalse(json.contains("812"), "The raw interval sequence must not be exported.")

        let visible = RROrderCorpusRecord(
            deviceKey: "device-001",
            rawDeviceID: "device,\"alpha\"",
            includeDeviceID: true,
            session: session,
            rows: rows
        )
        let csv = String(decoding: try RROrderCorpusEncoder.encode([visible], format: .csv), as: UTF8.self)
        XCTAssertTrue(csv.contains("\"device,\"\"alpha\"\"\""), "Opt-in raw IDs must be valid CSV.")
        XCTAssertTrue(csv.hasSuffix("\n"))
    }

    func testRunnerCountsShortAndInvalidSessionsWithoutFabricatingRecords() async throws {
        let path = temporaryDatabasePath()
        defer { removeDatabaseAndSidecars(path) }

        let store = try await WhoopStore(path: path)
        try await store.upsertDevice(id: "dev", mac: nil, name: nil)
        _ = try await store.upsertSleepSessions([
            CachedSleepSession(startTs: 100, endTs: 160, efficiency: nil, restingHr: nil,
                               avgHrv: nil, stagesJSON: nil),
            CachedSleepSession(startTs: 200, endTs: 190, efficiency: nil, restingHr: nil,
                               avgHrv: nil, stagesJSON: nil),
        ], deviceId: "dev")
        _ = try await store.insert(Streams(rr: [RRInterval(ts: 110, rrMs: 800)]), deviceId: "dev")
        try await store.checkpointWAL()

        let result = try RROrderCorpusRunner.run(
            database: RROrderCorpusDatabase(path: path),
            requestedDeviceIDs: ["dev"],
            from: 0,
            to: 1_000,
            sessionLimitPerDevice: 10,
            minimumDurationSeconds: 120,
            includeDeviceID: false
        )
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.summary.sessionsExamined, 2)
        XCTAssertEqual(result.summary.sessionsBelowMinimumDuration, 1)
        XCTAssertEqual(result.summary.invalidSessionWindows, 1)
    }

    func testPathResolverExpandsExplicitHomePath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rr-corpus-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = root.appendingPathComponent("whoop.sqlite")
        FileManager.default.createFile(atPath: database.path, contents: Data())

        let resolved = try RROrderCorpusDatabasePath.resolve(
            explicitPath: "~/whoop.sqlite",
            environment: [:],
            home: root.path
        )
        XCTAssertEqual(resolved, database.path)
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

    private func temporaryDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rr-order-corpus-\(UUID().uuidString).sqlite")
            .path
    }

    private func removeDatabaseAndSidecars(_ path: String) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }
}
