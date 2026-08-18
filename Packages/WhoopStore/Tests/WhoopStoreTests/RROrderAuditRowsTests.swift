import XCTest
import WhoopProtocol
@testable import WhoopStore

final class RROrderAuditRowsTests: XCTestCase {
    func testAuditReadExposesBatchedAndSplitBatchOrder() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        let emission = [812, 795, 840, 801, 833]

        _ = try await store.insert(
            Streams(rr: emission.map { RRInterval(ts: 100, rrMs: $0) }),
            deviceId: "dev1"
        )
        for value in emission {
            _ = try await store.insert(
                Streams(rr: [RRInterval(ts: 200, rrMs: value)]),
                deviceId: "dev1"
            )
        }

        let rows = try await store.rrOrderAuditRows(deviceId: "dev1", from: 0, to: 1_000)
        let batched = rows.filter { $0.ts == 100 }
        let split = rows.filter { $0.ts == 200 }

        XCTAssertEqual(batched.map(\.rrMs), emission)
        XCTAssertEqual(batched.map(\.emissionOrder), [0, 1, 2, 3, 4])
        XCTAssertEqual(split.map(\.rrMs), emission.sorted())
        XCTAssertEqual(split.map(\.emissionOrder), [0, 0, 0, 0, 0])
    }

    func testAuditReadPreservesLegacyUnknownOrder() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        for value in [812, 795, 840, 801, 833] {
            try await store.insertLegacyRrWithoutOrdForTest(deviceId: "dev1", ts: 300, rrMs: value)
        }

        let rows = try await store.rrOrderAuditRows(deviceId: "dev1", from: 300, to: 300)

        XCTAssertEqual(rows.map(\.rrMs), [795, 801, 812, 833, 840])
        XCTAssertEqual(rows.map(\.emissionOrder), [nil, nil, nil, nil, nil])
    }

    func testAuditReadUsesSamePopulationAndOrderAsScoringRead() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        _ = try await store.insert(
            Streams(rr: [
                RRInterval(ts: 400, rrMs: 812),
                RRInterval(ts: 400, rrMs: 795),
                RRInterval(ts: 401, rrMs: 824, srcChannel: .spo2Ibi),
                RRInterval(ts: 401, rrMs: 803, srcChannel: .greenQuality),
                RRInterval(ts: 402, rrMs: 833),
            ]),
            deviceId: "dev1"
        )

        let scoring = try await store.rrIntervals(deviceId: "dev1", from: 390, to: 410, limit: 100)
        let audit = try await store.rrOrderAuditRows(deviceId: "dev1", from: 390, to: 410)

        XCTAssertEqual(scoring.map { "\($0.ts):\($0.rrMs)" }, audit.map { "\($0.ts):\($0.rrMs)" })
        XCTAssertFalse(audit.contains { $0.rrMs == 824 }, "SpO2 IBI duplicate channel must stay out")
        XCTAssertTrue(audit.contains { $0.rrMs == 803 }, "green-quality channel remains the scoring source")
    }

    func testAuditReadRetainsSeqForEqualSameSecondValues() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        _ = try await store.insert(
            Streams(rr: [RRInterval(ts: 500, rrMs: 812), RRInterval(ts: 500, rrMs: 812)]),
            deviceId: "dev1"
        )

        let rows = try await store.rrOrderAuditRows(deviceId: "dev1", from: 500, to: 500)

        XCTAssertEqual(rows.map(\.seq), [0, 1])
        XCTAssertEqual(rows.map(\.emissionOrder), [0, 1])
    }
}
