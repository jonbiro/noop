import XCTest
@testable import Strand

final class SelfHostedPushTests: XCTestCase {
    private func freshState() -> (SelfHostedPushStateStore, UserDefaults) {
        let suite = "SelfHostedPushTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (SelfHostedPushStateStore(defaults: defaults), defaults)
    }

    func testEndpointPolicyAllowsHTTPSAndLocalHTTPOnly() {
        XCTAssertTrue(SelfHostedPushEndpointPolicy.isAllowed(URL(string: "https://example.com/noop")!))
        XCTAssertTrue(SelfHostedPushEndpointPolicy.isAllowed(URL(string: "http://localhost:8080/noop")!))
        XCTAssertTrue(SelfHostedPushEndpointPolicy.isAllowed(URL(string: "http://192.168.1.8:8080/noop")!))
        XCTAssertTrue(SelfHostedPushEndpointPolicy.isAllowed(URL(string: "http://receiver.local/noop")!))
        XCTAssertFalse(SelfHostedPushEndpointPolicy.isAllowed(URL(string: "http://example.com/noop")!))
        XCTAssertFalse(SelfHostedPushEndpointPolicy.isAllowed(URL(string: "ftp://192.168.1.8/noop")!))
        XCTAssertFalse(SelfHostedPushEndpointPolicy.isAllowed(URL(string: "https://user:pass@example.com/noop")!))
    }

    func testStateDefaultsOffAndWifiOnly() {
        let (state, _) = freshState()
        XCTAssertFalse(state.enabled)
        XCTAssertTrue(state.wifiOnly)
        XCTAssertNil(state.endpointURL)
        XCTAssertNil(state.cursor(for: "hrSample"))
    }

    func testRetryPolicyBacksOffAndCaps() {
        XCTAssertEqual(SelfHostedPushRetryPolicy.delayMs(consecutiveFailures: 0), 0)
        XCTAssertEqual(SelfHostedPushRetryPolicy.delayMs(consecutiveFailures: 1), 30_000)
        XCTAssertEqual(SelfHostedPushRetryPolicy.delayMs(consecutiveFailures: 2), 60_000)
        XCTAssertEqual(SelfHostedPushRetryPolicy.delayMs(consecutiveFailures: 6), 15 * 60_000)
        XCTAssertEqual(SelfHostedPushRetryPolicy.delayMs(consecutiveFailures: 99), 15 * 60_000)
    }

    func testNDJSONHasHeaderThenOneLinePerRecord() throws {
        let batch = SelfHostedPushBatch(
            batchId: "b1", stream: "hrSample", previousCursor: "old", cursor: "new",
            generatedAtMs: 1234,
            records: [
                SelfHostedPushRecord(id: "d1|1", observedAtMs: 1000,
                                     values: ["bpm": .integer(72)]),
                SelfHostedPushRecord(id: "d1|2", observedAtMs: 2000,
                                     values: ["bpm": .integer(73)])
            ])
        let data = try SelfHostedPushCodec.encodeNDJSON(batch)
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)

        let header = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertEqual(header["type"] as? String, "batch")
        XCTAssertEqual(header["protocolVersion"] as? Int, 1)
        XCTAssertEqual(header["recordCount"] as? Int, 2)
        XCTAssertEqual(header["cursor"] as? String, "new")

        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any])
        XCTAssertEqual(record["type"] as? String, "record")
        XCTAssertEqual(record["id"] as? String, "d1|1")
    }

    func testSuccessfulExactAckAdvancesCursor() async {
        let (state, _) = freshState()
        state.enabled = true
        state.endpointString = "https://receiver.example/noop"
        let worker = SelfHostedPushWorker(state: state, nowMs: { 1_000_000 }, tokenProvider: { "secret" })

        let outcome = await worker.run(stream: "hrSample", pageProvider: { stream, cursor, limit in
            XCTAssertEqual(stream, "hrSample")
            XCTAssertNil(cursor)
            XCTAssertEqual(limit, SelfHostedPushProtocol.maxRecordsPerBatch)
            return SelfHostedPushPage(cursor: "d1|100",
                                      records: [SelfHostedPushRecord(id: "d1|100", observedAtMs: 100_000,
                                                                     values: ["bpm": .integer(70)])])
        }, sender: { batch, endpoint, token in
            XCTAssertEqual(endpoint.absoluteString, "https://receiver.example/noop")
            XCTAssertEqual(token, "secret")
            return SelfHostedPushAck(protocolVersion: 1, batchId: batch.batchId,
                                     stream: batch.stream, acceptedCursor: batch.cursor)
        }, wifiAvailable: { true })

        XCTAssertEqual(outcome, .pushed(1))
        XCTAssertEqual(state.cursor(for: "hrSample"), "d1|100")
        XCTAssertEqual(state.consecutiveFailures, 0)
    }

    func testMismatchedAckNeverAdvancesCursor() async {
        let (state, _) = freshState()
        state.enabled = true
        state.endpointString = "https://receiver.example/noop"
        state.setCursor("old", for: "rrInterval")
        let worker = SelfHostedPushWorker(state: state, nowMs: { 2_000_000 }, tokenProvider: { "secret" })

        let outcome = await worker.run(stream: "rrInterval", pageProvider: { _, cursor, _ in
            XCTAssertEqual(cursor, "old")
            return SelfHostedPushPage(cursor: "new",
                                      records: [SelfHostedPushRecord(id: "d1|100|900", observedAtMs: 100_000,
                                                                     values: ["rrMs": .integer(900)])])
        }, sender: { batch, _, _ in
            SelfHostedPushAck(protocolVersion: 1, batchId: batch.batchId,
                              stream: batch.stream, acceptedCursor: "wrong")
        }, wifiAvailable: { true })

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(state.cursor(for: "rrInterval"), "old")
        XCTAssertEqual(state.consecutiveFailures, 1)
        XCTAssertFalse(state.canAttempt(nowMs: 2_000_001))
    }

    func testDisabledWorkerDoesNotCallProviderOrWifi() async {
        let (state, _) = freshState()
        var providerCalled = false
        var wifiCalled = false
        let worker = SelfHostedPushWorker(state: state, tokenProvider: { "secret" })

        let outcome = await worker.run(stream: "hrSample", pageProvider: { _, _, _ in
            providerCalled = true
            return nil
        }, sender: { batch, _, _ in
            SelfHostedPushAck(protocolVersion: 1, batchId: batch.batchId,
                              stream: batch.stream, acceptedCursor: batch.cursor)
        }, wifiAvailable: {
            wifiCalled = true
            return true
        })

        XCTAssertEqual(outcome, .disabled)
        XCTAssertFalse(providerCalled)
        XCTAssertFalse(wifiCalled)
    }

    func testWifiOnlyBlocksBeforeReadingData() async {
        let (state, _) = freshState()
        state.enabled = true
        state.endpointString = "https://receiver.example/noop"
        var providerCalled = false
        let worker = SelfHostedPushWorker(state: state, tokenProvider: { "secret" })

        let outcome = await worker.run(stream: "hrSample", pageProvider: { _, _, _ in
            providerCalled = true
            return nil
        }, wifiAvailable: { false })

        XCTAssertEqual(outcome, .wifiRequired)
        XCTAssertFalse(providerCalled)
    }
}
