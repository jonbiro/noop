import Foundation
import Network
import Security
import WhoopStore

// MARK: - Experimental one-way self-hosted export (#1314)
//
// This is deliberately an APP-side network boundary. WhoopStore selects/version-encodes batches but never
// performs I/O; this actor is the only component that talks to the user-owned receiver. It is default-off,
// send-only, and never participates in BLE/offload success. A dead receiver can make THIS job fail, but can
// never make strap sync fail or wait.

enum SelfHostedPushSettings {
    private static let enabledKey = "experimental.selfHostedPush.enabled"
    private static let endpointKey = "experimental.selfHostedPush.endpoint"
    private static let lastSuccessKey = "experimental.selfHostedPush.lastSuccessMs"
    private static let lastErrorKey = "experimental.selfHostedPush.lastError"
    private static let failureCountKey = "experimental.selfHostedPush.failureCount"
    private static let nextAttemptKey = "experimental.selfHostedPush.nextAttemptMs"
    private static let suspendedKey = "experimental.selfHostedPush.suspended"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    static var endpoint: String {
        get { UserDefaults.standard.string(forKey: endpointKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: endpointKey) }
    }
    static var lastSuccessMs: Int64 { Int64(UserDefaults.standard.object(forKey: lastSuccessKey) as? Int ?? 0) }
    static var lastError: String? { UserDefaults.standard.string(forKey: lastErrorKey) }
    static var failureCount: Int { UserDefaults.standard.integer(forKey: failureCountKey) }
    static var nextAttemptMs: Int64 { Int64(UserDefaults.standard.object(forKey: nextAttemptKey) as? Int ?? 0) }
    static var suspended: Bool { UserDefaults.standard.bool(forKey: suspendedKey) }

    static var isConfigured: Bool {
        SelfHostedPushEndpoint.validate(endpoint) != nil && SelfHostedPushTokenStore.read() != nil
    }

    static func noteSuccess(nowMs: Int64) {
        UserDefaults.standard.set(Int(nowMs), forKey: lastSuccessKey)
        UserDefaults.standard.removeObject(forKey: lastErrorKey)
        UserDefaults.standard.set(0, forKey: failureCountKey)
        UserDefaults.standard.set(0, forKey: nextAttemptKey)
        UserDefaults.standard.set(false, forKey: suspendedKey)
    }

    static func noteFailure(_ message: String, nowMs: Int64) {
        let count = failureCount + 1
        UserDefaults.standard.set(count, forKey: failureCountKey)
        UserDefaults.standard.set(message, forKey: lastErrorKey)
        let delaySeconds: Int64
        switch count {
        case 1: delaySeconds = 60
        case 2: delaySeconds = 5 * 60
        case 3: delaySeconds = 15 * 60
        case 4: delaySeconds = 60 * 60
        default: delaySeconds = 6 * 60 * 60
        }
        UserDefaults.standard.set(Int(nowMs + delaySeconds * 1_000), forKey: nextAttemptKey)
        if count >= 5 { UserDefaults.standard.set(true, forKey: suspendedKey) }
    }

    static func resetFailureState() {
        UserDefaults.standard.removeObject(forKey: lastErrorKey)
        UserDefaults.standard.set(0, forKey: failureCountKey)
        UserDefaults.standard.set(0, forKey: nextAttemptKey)
        UserDefaults.standard.set(false, forKey: suspendedKey)
    }
}

enum SelfHostedPushEndpoint {
    /// HTTPS is accepted anywhere. Plain HTTP is intentionally restricted to the same local/private
    /// destinations already accepted by AI Coach's Custom provider guard. Keeping one host classifier
    /// avoids two subtly different definitions of "local network" inside the app.
    static func validate(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              components.user == nil, components.password == nil,
              components.fragment == nil,
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        let scheme = components.scheme?.lowercased()
        guard scheme == "https" || (scheme == "http" && AIProvider.isPrivateLANOrLoopback(host)) else { return nil }
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }
}

enum SelfHostedPushTokenStore {
    private static let service = "com.noop.selfhostedpush"
    private static let account = "bearer-token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { clear(); return trimmed.isEmpty }
        SecItemDelete(baseQuery as CFDictionary)
        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    static func clear() { SecItemDelete(baseQuery as CFDictionary) }
}

private enum SelfHostedPushNetworkPolicy {
    /// Protocol v1 is intentionally Wi-Fi-only. This is an actual interface gate, not merely
    /// `allowsCellularAccess = false`: a satisfied non-Wi-Fi path must not start an export request.
    static func hasUsableWiFiPath() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.noop.selfhostedpush.path")
            let lock = NSLock()
            var resumed = false
            monitor.pathUpdateHandler = { path in
                lock.lock()
                guard !resumed else {
                    lock.unlock()
                    return
                }
                resumed = true
                lock.unlock()
                let allowed = path.status == .satisfied && path.usesInterfaceType(.wifi)
                monitor.cancel()
                continuation.resume(returning: allowed)
            }
            monitor.start(queue: queue)
        }
    }
}

actor SelfHostedPushWorker {
    static let shared = SelfHostedPushWorker()

    enum Outcome: Equatable {
        case skipped(String)
        case success(posts: Int, rows: Int)
        case failed(String)

        var message: String {
            switch self {
            case .skipped(let reason): return reason
            case .success(let posts, let rows): return "Sent \(rows) rows in \(posts) batch\(posts == 1 ? "" : "es")."
            case .failed(let reason): return reason
            }
        }
    }

    private var running = false
    private let maxAutomaticPosts = 24
    private let maxManualPosts = 120
    private let appendRowsPerBatch = 500

    func run(store: WhoopStore, manual: Bool = false, now: Date = Date()) async -> Outcome {
        guard manual || SelfHostedPushSettings.enabled else { return .skipped("Self-hosted export is off.") }
        guard let endpoint = SelfHostedPushEndpoint.validate(SelfHostedPushSettings.endpoint) else {
            return .failed("Enter a valid HTTPS endpoint (or a private/local HTTP endpoint).")
        }
        guard let token = SelfHostedPushTokenStore.read() else { return .failed("Add a bearer token first.") }

        let nowMs = Int64(now.timeIntervalSince1970 * 1_000)
        if !manual {
            if SelfHostedPushSettings.suspended {
                return .skipped("Automatic export is paused after repeated failures. Use Push now to test it.")
            }
            if nowMs < SelfHostedPushSettings.nextAttemptMs {
                return .skipped("Automatic export is waiting for its retry backoff.")
            }
        }
        guard !running else { return .skipped("An export is already running.") }
        guard await SelfHostedPushNetworkPolicy.hasUsableWiFiPath() else {
            return .skipped("Self-hosted export is Wi-Fi-only in this Experimental version.")
        }
        running = true
        defer { running = false }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.allowsCellularAccess = false
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        let session = URLSession(configuration: configuration)

        let maxPosts = manual ? maxManualPosts : maxAutomaticPosts
        var posts = 0
        var rowsSent = 0
        do {
            for stream in SelfHostedPush.Stream.allCases where stream.mode == .upsertWindow {
                guard posts < maxPosts else { break }
                if let batch = try await store.selfHostedPushMutableBatch(stream, now: now) {
                    try await post(batch, to: endpoint, token: token, using: session)
                    posts += 1
                    rowsSent += batch.records.count
                }
            }

            let appendStreams = SelfHostedPush.Stream.allCases.filter { $0.mode == .append }
            var exhausted = Set<SelfHostedPush.Stream>()
            while posts < maxPosts && exhausted.count < appendStreams.count {
                for stream in appendStreams where posts < maxPosts && !exhausted.contains(stream) {
                    guard let batch = try await store.nextSelfHostedPushAppendBatch(stream, limit: appendRowsPerBatch) else {
                        exhausted.insert(stream)
                        continue
                    }
                    try await post(batch, to: endpoint, token: token, using: session)
                    if let cursor = batch.cursorToInclusive {
                        try await store.setSelfHostedPushCursor(stream, cursor)
                    }
                    posts += 1
                    rowsSent += batch.records.count
                }
            }

            SelfHostedPushSettings.noteSuccess(nowMs: nowMs)
            return .success(posts: posts, rows: rowsSent)
        } catch {
            let message = SelfHostedPushWorker.safeErrorMessage(error)
            SelfHostedPushSettings.noteFailure(message, nowMs: nowMs)
            return .failed(message)
        }
    }

    private func post(_ batch: SelfHostedPush.Batch, to endpoint: URL, token: String, using session: URLSession) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = try batch.ndjson()
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(String(SelfHostedPush.protocolVersion), forHTTPHeaderField: "X-NOOP-Push-Protocol")
        request.setValue(batch.stream.rawValue, forHTTPHeaderField: "X-NOOP-Push-Stream")
        request.setValue(batch.mode.rawValue, forHTTPHeaderField: "X-NOOP-Push-Mode")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PushError.nonHTTPResponse }
        guard (200..<300).contains(http.statusCode) else { throw PushError.httpStatus(http.statusCode) }
    }

    private enum PushError: LocalizedError {
        case nonHTTPResponse
        case httpStatus(Int)
        var errorDescription: String? {
            switch self {
            case .nonHTTPResponse: return "Receiver returned a non-HTTP response."
            case .httpStatus(let status): return "Receiver returned HTTP \(status)."
            }
        }
    }

    private static func safeErrorMessage(_ error: Error) -> String {
        if let push = error as? PushError { return push.localizedDescription }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Network error (\(ns.code)). Check the endpoint and try again."
        }
        return "Export failed. Check the endpoint and try again."
    }
}
