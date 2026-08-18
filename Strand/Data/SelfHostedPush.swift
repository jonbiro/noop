import Foundation
import Security

/// Experimental, one-way export to a user-owned HTTP(S) receiver (#1314).
///
/// This file deliberately owns only the transport contract and failure policy. It does not know how
/// any WhoopStore table is paged and it is not invoked from the strap offload path. A later adapter can
/// supply pages after an offload has fully completed without changing these safety semantics.
enum SelfHostedPushProtocol {
    static let version = 1
    static let contentType = "application/x-ndjson"
    static let maxRecordsPerBatch = 500
}

// MARK: - Endpoint policy

enum SelfHostedPushEndpointPolicy {
    /// Public destinations must use HTTPS. Plain HTTP is accepted only for loopback, `.local`, link-local,
    /// and RFC1918/ULA addresses so a user-owned receiver on the same LAN can work without weakening ATS
    /// for arbitrary Internet hosts.
    static func isAllowed(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if scheme == "https" { return true }
        return scheme == "http" && isLocalHost(host)
    }

    static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" { return true }
        if host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") { return true }

        let parts = host.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        if parts[0] == 127 || parts[0] == 10 { return true }
        if parts[0] == 169 && parts[1] == 254 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }
}

// MARK: - Versioned wire values

enum SelfHostedPushJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int64.self) { self = .integer(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

struct SelfHostedPushRecord: Codable, Equatable, Sendable {
    /// Stable receiver-side id, normally the source row's complete primary key encoded by the adapter.
    let id: String
    /// Optional event/sample time in Unix milliseconds. It is descriptive only, never the delivery cursor.
    let observedAtMs: Int64?
    let values: [String: SelfHostedPushJSONValue]
}

struct SelfHostedPushPage: Equatable, Sendable {
    /// Opaque adapter-owned cursor for the last record represented by this page. Composite primary keys are
    /// allowed; the push layer never parses this value.
    let cursor: String
    let records: [SelfHostedPushRecord]
}

struct SelfHostedPushBatch: Equatable, Sendable {
    let batchId: String
    let stream: String
    let previousCursor: String?
    let cursor: String
    let generatedAtMs: Int64
    let records: [SelfHostedPushRecord]
}

struct SelfHostedPushAck: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let batchId: String
    let stream: String
    let acceptedCursor: String
}

private struct SelfHostedPushBatchHeader: Codable {
    let type = "batch"
    let protocolVersion: Int
    let batchId: String
    let stream: String
    let previousCursor: String?
    let cursor: String
    let generatedAtMs: Int64
    let recordCount: Int
}

private struct SelfHostedPushRecordLine: Codable {
    let type = "record"
    let id: String
    let observedAtMs: Int64?
    let values: [String: SelfHostedPushJSONValue]
}

enum SelfHostedPushCodec {
    /// Request body is NDJSON: one batch header followed by one line per record. Sorted keys make fixtures
    /// deterministic without assigning semantic meaning to JSON key order.
    static func encodeNDJSON(_ batch: SelfHostedPushBatch) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let header = SelfHostedPushBatchHeader(
            protocolVersion: SelfHostedPushProtocol.version,
            batchId: batch.batchId,
            stream: batch.stream,
            previousCursor: batch.previousCursor,
            cursor: batch.cursor,
            generatedAtMs: batch.generatedAtMs,
            recordCount: batch.records.count)

        var lines: [Data] = [try encoder.encode(header)]
        lines.reserveCapacity(batch.records.count + 1)
        for record in batch.records {
            lines.append(try encoder.encode(SelfHostedPushRecordLine(
                id: record.id, observedAtMs: record.observedAtMs, values: record.values)))
        }
        var body = Data()
        for line in lines {
            body.append(line)
            body.append(0x0A)
        }
        return body
    }

    static func decodeAck(_ data: Data) throws -> SelfHostedPushAck {
        try JSONDecoder().decode(SelfHostedPushAck.self, from: data)
    }

    static func ackMatches(_ ack: SelfHostedPushAck, batch: SelfHostedPushBatch) -> Bool {
        ack.protocolVersion == SelfHostedPushProtocol.version
            && ack.batchId == batch.batchId
            && ack.stream == batch.stream
            && ack.acceptedCursor == batch.cursor
    }
}

// MARK: - Durable client state

/// UserDefaults stores only non-secret configuration and opaque per-stream delivery cursors. The bearer
/// token is kept separately in Keychain. No per-row `synced` columns are read or written (#1314 decision).
struct SelfHostedPushStateStore {
    private let defaults: UserDefaults
    private let prefix = "selfHostedPush."

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var enabled: Bool {
        get { defaults.bool(forKey: prefix + "enabled") }
        nonmutating set { defaults.set(newValue, forKey: prefix + "enabled") }
    }

    var endpointString: String? {
        get { defaults.string(forKey: prefix + "endpoint") }
        nonmutating set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty { defaults.removeObject(forKey: prefix + "endpoint") }
            else { defaults.set(trimmed, forKey: prefix + "endpoint") }
        }
    }

    var endpointURL: URL? { endpointString.flatMap(URL.init(string:)) }

    /// Wi-Fi-only is the safe default even before a preference has ever been written.
    var wifiOnly: Bool {
        get {
            let key = prefix + "wifiOnly"
            return defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
        }
        nonmutating set { defaults.set(newValue, forKey: prefix + "wifiOnly") }
    }

    func cursor(for stream: String) -> String? {
        defaults.string(forKey: prefix + "cursor." + stream)
    }

    func setCursor(_ cursor: String?, for stream: String) {
        let key = prefix + "cursor." + stream
        if let cursor, !cursor.isEmpty { defaults.set(cursor, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    var consecutiveFailures: Int { defaults.integer(forKey: prefix + "failureCount") }
    var nextAttemptMs: Int64 { Int64(defaults.object(forKey: prefix + "nextAttemptMs") as? Int ?? 0) }
    var suspendedUntilMs: Int64 { Int64(defaults.object(forKey: prefix + "suspendedUntilMs") as? Int ?? 0) }

    func canAttempt(nowMs: Int64) -> Bool {
        nowMs >= nextAttemptMs && nowMs >= suspendedUntilMs
    }

    func recordSuccess() {
        defaults.set(0, forKey: prefix + "failureCount")
        defaults.removeObject(forKey: prefix + "nextAttemptMs")
        defaults.removeObject(forKey: prefix + "suspendedUntilMs")
    }

    func recordFailure(nowMs: Int64) {
        let count = consecutiveFailures + 1
        defaults.set(count, forKey: prefix + "failureCount")
        defaults.set(Int(nowMs + SelfHostedPushRetryPolicy.delayMs(consecutiveFailures: count)),
                     forKey: prefix + "nextAttemptMs")
        if count >= SelfHostedPushRetryPolicy.suspensionThreshold {
            defaults.set(Int(nowMs + SelfHostedPushRetryPolicy.suspensionMs),
                         forKey: prefix + "suspendedUntilMs")
        }
    }
}

enum SelfHostedPushRetryPolicy {
    static let baseDelayMs: Int64 = 30_000
    static let maxDelayMs: Int64 = 15 * 60_000
    static let suspensionThreshold = 8
    static let suspensionMs: Int64 = 6 * 60 * 60_000

    static func delayMs(consecutiveFailures: Int) -> Int64 {
        guard consecutiveFailures > 0 else { return 0 }
        let exponent = min(consecutiveFailures - 1, 5)
        return min(baseDelayMs * Int64(1 << exponent), maxDelayMs)
    }
}

// MARK: - Secret storage

enum SelfHostedPushSecret {
    private static let service = "com.noop.self-hosted-push"
    private static let account = "bearer-token"

    static func token() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setToken(_ token: String?) -> Bool {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let query = baseQuery()
        SecItemDelete(query as CFDictionary)
        guard !trimmed.isEmpty else { return true }

        var item = query
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

// MARK: - HTTP transport

enum SelfHostedPushTransportError: Error {
    case rejectedEndpoint
    case invalidResponse
    case httpStatus(Int)
    case invalidAcknowledgement
}

private final class SelfHostedPushNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Never carry the user-generated bearer token through a redirect. A receiver must acknowledge
        // directly at the configured endpoint.
        completionHandler(nil)
    }
}

enum SelfHostedPushHTTPTransport {
    static func send(batch: SelfHostedPushBatch, endpoint: URL, bearerToken: String) async throws -> SelfHostedPushAck {
        guard SelfHostedPushEndpointPolicy.isAllowed(endpoint) else {
            throw SelfHostedPushTransportError.rejectedEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(SelfHostedPushProtocol.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try SelfHostedPushCodec.encodeNDJSON(batch)

        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let delegate = SelfHostedPushNoRedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SelfHostedPushTransportError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw SelfHostedPushTransportError.httpStatus(http.statusCode) }
        let ack = try SelfHostedPushCodec.decodeAck(data)
        guard SelfHostedPushCodec.ackMatches(ack, batch: batch) else {
            throw SelfHostedPushTransportError.invalidAcknowledgement
        }
        return ack
    }
}

// MARK: - Background-worker semantics

struct SelfHostedPushWorker {
    typealias PageProvider = (_ stream: String, _ afterCursor: String?, _ limit: Int) async throws -> SelfHostedPushPage?
    typealias Sender = (_ batch: SelfHostedPushBatch, _ endpoint: URL, _ token: String) async throws -> SelfHostedPushAck
    typealias WiFiCheck = () async -> Bool
    typealias TokenProvider = () -> String?

    enum Outcome: Equatable {
        case disabled
        case missingEndpoint
        case rejectedEndpoint
        case missingToken
        case deferred
        case wifiRequired
        case noData
        case pushed(Int)
        case failed
    }

    let state: SelfHostedPushStateStore
    var nowMs: () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    var tokenProvider: TokenProvider = { SelfHostedPushSecret.token() }

    /// One quiet attempt. There is intentionally no internal retry loop: an offload-triggered job gets one
    /// chance, records backoff on failure, and exits. That keeps receiver outages out of NOOP's sync path.
    func run(stream: String,
             pageProvider: PageProvider,
             sender: Sender = { batch, endpoint, token in
                 try await SelfHostedPushHTTPTransport.send(batch: batch, endpoint: endpoint, bearerToken: token)
             },
             wifiAvailable: @escaping WiFiCheck) async -> Outcome {
        guard state.enabled else { return .disabled }
        guard let endpoint = state.endpointURL else { return .missingEndpoint }
        guard SelfHostedPushEndpointPolicy.isAllowed(endpoint) else { return .rejectedEndpoint }
        guard let token = tokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return .missingToken
        }

        let now = nowMs()
        guard state.canAttempt(nowMs: now) else { return .deferred }
        if state.wifiOnly, !(await wifiAvailable()) { return .wifiRequired }

        let previous = state.cursor(for: stream)
        do {
            guard let page = try await pageProvider(stream, previous, SelfHostedPushProtocol.maxRecordsPerBatch),
                  !page.records.isEmpty else { return .noData }
            let batch = SelfHostedPushBatch(
                batchId: UUID().uuidString,
                stream: stream,
                previousCursor: previous,
                cursor: page.cursor,
                generatedAtMs: now,
                records: page.records)
            let ack = try await sender(batch, endpoint, token)
            guard SelfHostedPushCodec.ackMatches(ack, batch: batch) else {
                state.recordFailure(nowMs: now)
                return .failed
            }

            // Delivery is at-least-once. Only an exact receiver acknowledgement advances the opaque
            // high-water mark; request success alone is never enough.
            state.setCursor(page.cursor, for: stream)
            state.recordSuccess()
            return .pushed(page.records.count)
        } catch {
            state.recordFailure(nowMs: now)
            return .failed
        }
    }
}
