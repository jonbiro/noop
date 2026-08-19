import XCTest
import WhoopProtocol
@testable import WhoopStore

final class SelfHostedPushTests: XCTestCase {
    func testAppendCursorUsesInsertionOrderSoLateBackfillIsNotSkipped() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)

        _ = try await store.insert(Streams(hr: [HRSample(ts: 200, bpm: 70)]), deviceId: "dev1")
        let firstCandidate = try await store.nextSelfHostedPushAppendBatch(.hrSample, generatedAtMs: 1_000)
        let first = try XCTUnwrap(firstCandidate)
        XCTAssertEqual(first.cursorFromExclusive, 0)
        XCTAssertEqual(first.records.count, 1)
        let firstCursor = try XCTUnwrap(first.cursorToInclusive)
        try await store.setSelfHostedPushCursor(.hrSample, firstCursor)

        // This row is physiologically OLDER but was inserted LATER. A timestamp high-water would lose it.
        _ = try await store.insert(Streams(hr: [HRSample(ts: 100, bpm: 60)]), deviceId: "dev1")
        let secondCandidate = try await store.nextSelfHostedPushAppendBatch(.hrSample, generatedAtMs: 2_000)
        let second = try XCTUnwrap(secondCandidate)
        XCTAssertEqual(second.cursorFromExclusive, firstCursor)
        XCTAssertEqual(second.records.count, 1)
        XCTAssertEqual(second.records[0]["ts"], .int(100))
        XCTAssertEqual(second.records[0]["bpm"], .int(60))
        XCTAssertGreaterThan(try XCTUnwrap(second.cursorToInclusive), firstCursor)
    }

    func testAppendCursorDoesNotAdvanceWhenBatchIsRead() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        _ = try await store.insert(Streams(hr: [HRSample(ts: 100, bpm: 60)]), deviceId: "dev1")

        let firstCandidate = try await store.nextSelfHostedPushAppendBatch(.hrSample)
        let retryCandidate = try await store.nextSelfHostedPushAppendBatch(.hrSample)
        let first = try XCTUnwrap(firstCandidate)
        let retry = try XCTUnwrap(retryCandidate)
        XCTAssertEqual(first, retry)
        let cursor = try await store.selfHostedPushCursor(.hrSample)
        XCTAssertEqual(cursor, 0)
    }

    func testAppendCursorAnchorFailsSafeAfterRowIDReuse() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        _ = try await store.insert(Streams(hr: [HRSample(ts: 100, bpm: 60)]), deviceId: "dev1")

        let first = try XCTUnwrap(try await store.nextSelfHostedPushAppendBatch(.hrSample))
        let acknowledgedRowID = try XCTUnwrap(first.cursorToInclusive)
        try await store.setSelfHostedPushCursor(.hrSample, acknowledgedRowID)
        XCTAssertEqual(try await store.selfHostedPushCursor(.hrSample), acknowledgedRowID)

        // Removing the acknowledged row and inserting a different row can reuse its implicit rowid.
        // This is the same failure shape as rowid renumbering: the numeric cursor exists but now names
        // a different logical record. The saved natural-key anchor must force an idempotent replay.
        try await store.deleteAllData(deviceId: "dev1")
        _ = try await store.insert(Streams(hr: [HRSample(ts: 200, bpm: 61)]), deviceId: "dev1")

        XCTAssertEqual(try await store.selfHostedPushCursor(.hrSample), 0)
        let replay = try XCTUnwrap(try await store.nextSelfHostedPushAppendBatch(.hrSample))
        XCTAssertEqual(replay.cursorFromExclusive, 0)
        XCTAssertEqual(replay.records.count, 1)
        XCTAssertEqual(replay.records[0]["ts"], .int(200))
    }

    func testPushCursorNamespaceDoesNotCollideWithLegacyHighwater() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        _ = try await store.insert(Streams(hr: [HRSample(ts: 100, bpm: 60)]), deviceId: "dev1")
        let batch = try XCTUnwrap(try await store.nextSelfHostedPushAppendBatch(.hrSample))
        let rowID = try XCTUnwrap(batch.cursorToInclusive)

        try await store.setHighwater("hrSample", 999)
        try await store.setSelfHostedPushCursor(.hrSample, rowID)

        let legacy = try await store.highwater("hrSample")
        let push = try await store.selfHostedPushCursor(.hrSample)
        XCTAssertEqual(legacy, 999)
        XCTAssertEqual(push, rowID)
    }

    func testInternalSyncedColumnNeverAppearsOnWire() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        _ = try await store.insert(Streams(hr: [HRSample(ts: 100, bpm: 61)]), deviceId: "dev1")

        let candidate = try await store.nextSelfHostedPushAppendBatch(.hrSample, generatedAtMs: 7)
        let batch = try XCTUnwrap(candidate)
        XCTAssertNil(batch.records[0]["synced"])
        XCTAssertNil(batch.records[0]["_noopPushRowID"])

        let lines = try jsonLines(batch.ndjson())
        XCTAssertEqual(lines.count, 2)
        let header = try XCTUnwrap(lines[0] as? [String: Any])
        XCTAssertEqual(header["protocol"] as? Int, 1)
        XCTAssertEqual(header["stream"] as? String, "hrSample")
        XCTAssertEqual(header["mode"] as? String, "append")
        XCTAssertEqual(header["rowCount"] as? Int, 1)
        let rowEnvelope = try XCTUnwrap(lines[1] as? [String: Any])
        let row = try XCTUnwrap(rowEnvelope["data"] as? [String: Any])
        XCTAssertNil(row["synced"])
        XCTAssertEqual(row["ts"] as? Int, 100)
        XCTAssertEqual(row["bpm"] as? Int, 61)
    }

    func testAppendLimitProducesStableRetryBoundary() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        _ = try await store.insert(
            Streams(hr: [
                HRSample(ts: 100, bpm: 60),
                HRSample(ts: 200, bpm: 61),
                HRSample(ts: 300, bpm: 62),
            ]),
            deviceId: "dev1"
        )

        let firstCandidate = try await store.nextSelfHostedPushAppendBatch(.hrSample, limit: 2)
        let first = try XCTUnwrap(firstCandidate)
        XCTAssertEqual(first.records.count, 2)
        try await store.setSelfHostedPushCursor(.hrSample, try XCTUnwrap(first.cursorToInclusive))
        let secondCandidate = try await store.nextSelfHostedPushAppendBatch(.hrSample, limit: 2)
        let second = try XCTUnwrap(secondCandidate)
        XCTAssertEqual(second.records.count, 1)
        XCTAssertEqual(second.records[0]["ts"], .int(300))
    }

    func testEmptyAppendStreamReturnsNil() async throws {
        let store = try await WhoopStore.inMemory()
        let batch = try await store.nextSelfHostedPushAppendBatch(.hrSample)
        XCTAssertNil(batch)
    }

    func testMutableDailyWindowRepeatsLatestAuthoritativeRow() async throws {
        let store = try await WhoopStore.inMemory()
        let calendar = utcCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-17T12:00:00Z"))

        _ = try await store.upsertDailyMetrics([
            daily("2026-07-01", hrv: 20),
            daily("2026-08-10", hrv: 40),
        ], deviceId: "dev1")
        // Recompute/edit the same natural key. The rolling snapshot must carry the latest value.
        _ = try await store.upsertDailyMetrics([daily("2026-08-10", hrv: 55)], deviceId: "dev1")

        let candidate = try await store.selfHostedPushMutableBatch(
            .dailyMetric, windowDays: 14, now: now, calendar: calendar, generatedAtMs: 1234
        )
        let batch = try XCTUnwrap(candidate)
        XCTAssertEqual(batch.mode, .upsertWindow)
        XCTAssertNil(batch.cursorFromExclusive)
        XCTAssertNil(batch.cursorToInclusive)
        XCTAssertEqual(batch.window, .init(field: .day, from: "2026-08-04", through: "2026-08-17"))
        XCTAssertEqual(batch.records.count, 1)
        XCTAssertEqual(batch.records[0]["day"], .string("2026-08-10"))
        XCTAssertEqual(batch.records[0]["avgHrv"], .double(55))

        let header = try XCTUnwrap(try jsonLines(batch.ndjson()).first as? [String: Any])
        XCTAssertEqual(header["mode"] as? String, "upsertWindow")
        let key = try XCTUnwrap(header["naturalKey"] as? [String])
        XCTAssertEqual(key, ["deviceId", "day"])
    }

    func testMutableStreamNeverAcceptsAppendCursor() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.setSelfHostedPushCursor(.dailyMetric, 999)
        let cursor = try await store.selfHostedPushCursor(.dailyMetric)
        XCTAssertEqual(cursor, 0)
    }

    func testProtocolStreamModesAndNaturalKeysAreStable() {
        XCTAssertEqual(SelfHostedPush.protocolVersion, 1)
        XCTAssertEqual(SelfHostedPush.Stream.dailyMetric.mode, .upsertWindow)
        XCTAssertEqual(SelfHostedPush.Stream.sleepSession.naturalKey, ["deviceId", "startTs"])
        XCTAssertEqual(SelfHostedPush.Stream.workout.naturalKey, ["deviceId", "startTs", "sport"])
        XCTAssertEqual(SelfHostedPush.Stream.journal.naturalKey, ["deviceId", "day", "question"])
        XCTAssertEqual(SelfHostedPush.Stream.rrInterval.naturalKey, ["deviceId", "ts", "rrMs"])
        XCTAssertEqual(SelfHostedPush.Stream.event.naturalKey, ["deviceId", "ts", "kind"])
        XCTAssertEqual(SelfHostedPush.Stream.hrSample.naturalKey, ["deviceId", "ts"])
    }

    private func daily(_ day: String, hrv: Double) -> DailyMetric {
        DailyMetric(
            day: day,
            totalSleepMin: nil,
            efficiency: nil,
            deepMin: nil,
            remMin: nil,
            lightMin: nil,
            disturbances: nil,
            restingHr: nil,
            avgHrv: hrv,
            recovery: nil,
            strain: nil,
            exerciseCount: nil
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func jsonLines(_ data: Data) throws -> [Any] {
        try String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { line in
                try JSONSerialization.jsonObject(with: Data(line.utf8))
            }
    }
}
