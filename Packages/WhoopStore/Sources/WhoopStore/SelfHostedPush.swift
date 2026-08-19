import Foundation
import GRDB

/// Versioned, receiver-agnostic rows for the Experimental one-way self-hosted export (#1314).
///
/// This deliberately lives in WhoopStore rather than the app/network layer so the selection contract,
/// cursor semantics, and NDJSON wire shape are deterministic and headlessly testable. Nothing here
/// performs network I/O. A caller reads a batch, POSTs it, and commits the returned append cursor only
/// after the receiver returns a successful 2xx response.
public enum SelfHostedPush {
    public static let protocolVersion = 1
    public static let cursorPrefix = "selfHostedPush:"
    public static let defaultAppendLimit = 500
    public static let defaultMutableWindowDays = 14

    public enum Mode: String, Codable, Sendable {
        /// Rows are immutable in practice and are selected by SQLite insertion order. This is NOT a
        /// timestamp high-water: a late historical backfill receives a newer rowid and therefore still
        /// exports even when its physiological timestamp is older than data already sent.
        case append
        /// Rows can be recomputed or user-edited. The sender repeats a bounded authoritative window and
        /// the receiver UPSERTs by the documented natural key. No append cursor is used for this mode.
        case upsertWindow
    }

    /// The intentionally small v1 stream surface. Raw batches / experimental deep buffers are omitted:
    /// this feature is for useful local health data, not an automatic raw-research exfiltration path.
    public enum Stream: String, CaseIterable, Codable, Sendable {
        case dailyMetric
        case sleepSession
        case workout
        case journal

        case hrSample
        case rrInterval
        case event
        case battery
        case spo2Sample
        case skinTempSample
        case respSample
        case gravitySample
        case stepSample
        case ppgHrSample

        public var mode: Mode {
            switch self {
            case .dailyMetric, .sleepSession, .workout, .journal:
                return .upsertWindow
            default:
                return .append
            }
        }

        /// Natural key columns the receiver uses for idempotent UPSERT. Retries are expected and safe.
        public var naturalKey: [String] {
            switch self {
            case .rrInterval: return ["deviceId", "ts", "rrMs"]
            case .event: return ["deviceId", "ts", "kind"]
            case .sleepSession: return ["deviceId", "startTs"]
            case .dailyMetric: return ["deviceId", "day"]
            case .workout: return ["deviceId", "startTs", "sport"]
            case .journal: return ["deviceId", "day", "question"]
            default: return ["deviceId", "ts"]
            }
        }
    }

    public enum JSONValue: Equatable, Sendable {
        case null
        case int(Int64)
        case double(Double)
        case string(String)
        case dataBase64(String)

        fileprivate var foundationValue: Any {
            switch self {
            case .null: return NSNull()
            case .int(let value): return value
            case .double(let value): return value
            case .string(let value): return value
            case .dataBase64(let value): return value
            }
        }
    }

    public struct Window: Equatable, Sendable {
        public enum Field: String, Sendable { case day, startTs }
        public let field: Field
        public let from: String
        public let through: String
    }

    public struct Batch: Equatable, Sendable {
        public let stream: Stream
        public let generatedAtMs: Int64
        public let records: [[String: JSONValue]]
        /// Append-only SQLite rowid cursor. Nil for rolling upsert windows.
        public let cursorFromExclusive: Int64?
        public let cursorToInclusive: Int64?
        public let window: Window?

        public var mode: Mode { stream.mode }
        public var isEmpty: Bool { records.isEmpty }

        /// Deterministic NDJSON. The first line is a batch envelope; each following line is one record.
        /// Sorted JSON keys make fixtures/replay diffs stable. A trailing newline is included so ordinary
        /// line-oriented receivers can stream the body without special handling of the final record.
        public func ndjson() throws -> Data {
            var header: [String: Any] = [
                "kind": "batch",
                "protocol": SelfHostedPush.protocolVersion,
                "stream": stream.rawValue,
                "mode": mode.rawValue,
                "generatedAtMs": generatedAtMs,
                "rowCount": records.count,
                "naturalKey": stream.naturalKey,
            ]
            if let cursorFromExclusive, let cursorToInclusive {
                header["cursor"] = [
                    "fromExclusive": cursorFromExclusive,
                    "toInclusive": cursorToInclusive,
                ]
            }
            if let window {
                header["window"] = [
                    "field": window.field.rawValue,
                    "from": window.from,
                    "through": window.through,
                ]
            }

            var lines: [Data] = [try SelfHostedPush.encodeJSONObject(header)]
            lines.reserveCapacity(records.count + 1)
            for record in records {
                let data = Dictionary(uniqueKeysWithValues: record.map { ($0.key, $0.value.foundationValue) })
                lines.append(try SelfHostedPush.encodeJSONObject(["kind": "row", "data": data]))
            }
            var body = Data()
            for line in lines {
                body.append(line)
                body.append(0x0A)
            }
            return body
        }
    }

    private static func encodeJSONObject(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    fileprivate static func value(_ databaseValue: DatabaseValue) -> JSONValue {
        switch databaseValue.storage {
        case .null: return .null
        case .int64(let value): return .int(value)
        case .double(let value): return .double(value)
        case .string(let value): return .string(value)
        case .blob(let value): return .dataBase64(value.base64EncodedString())
        }
    }
}

extension WhoopStore {
    /// Distinct from the legacy upload `highwater:` and server-pull `read:` cursors. Restoring a DB also
    /// restores these cursors with it, which can at worst cause idempotent re-send, never a skipped row.
    public func selfHostedPushCursor(_ stream: SelfHostedPush.Stream) async throws -> Int64 {
        Int64(try await cursor(SelfHostedPush.cursorPrefix + stream.rawValue) ?? 0)
    }

    /// Commit only AFTER a receiver accepted the matching append batch. Upsert-window streams never use it.
    public func setSelfHostedPushCursor(_ stream: SelfHostedPush.Stream, _ rowID: Int64) async throws {
        guard stream.mode == .append else { return }
        try await setCursor(SelfHostedPush.cursorPrefix + stream.rawValue, Int(rowID))
    }

    /// Next append-only chunk after the stream's committed insertion-order cursor.
    ///
    /// Uses SQLite rowid instead of physiological timestamp. That is the important #1314 property: if the
    /// strap later offloads an older timestamp, its newly inserted rowid is still after the cursor and the
    /// row is exported. The internal `synced` flag is explicitly stripped from the wire.
    public func nextSelfHostedPushAppendBatch(
        _ stream: SelfHostedPush.Stream,
        limit: Int = SelfHostedPush.defaultAppendLimit,
        generatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) async throws -> SelfHostedPush.Batch? {
        guard stream.mode == .append else { return nil }
        let boundedLimit = min(max(limit, 1), 5_000)
        let from = try await selfHostedPushCursor(stream)
        return try syncRead { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT rowid AS _noopPushRowID, * FROM \(stream.rawValue) WHERE rowid > ? ORDER BY rowid LIMIT ?",
                arguments: [from, boundedLimit]
            )
            guard !rows.isEmpty else { return nil }
            let to = rows.compactMap { row -> Int64? in
                let value: Int64? = row["_noopPushRowID"]
                return value
            }.max() ?? from
            let records = rows.map(SelfHostedPush.record)
            return SelfHostedPush.Batch(
                stream: stream,
                generatedAtMs: generatedAtMs,
                records: records,
                cursorFromExclusive: from,
                cursorToInclusive: to,
                window: nil
            )
        }
    }

    /// Current authoritative mutable window. The receiver UPSERTs by the stream natural key.
    ///
    /// This intentionally repeats recent rows rather than pretending mutable/recomputed data are append-only.
    /// Deletion tombstones are not part of protocol v1; edits/recomputes are propagated by repeated UPSERT.
    public func selfHostedPushMutableBatch(
        _ stream: SelfHostedPush.Stream,
        windowDays: Int = SelfHostedPush.defaultMutableWindowDays,
        now: Date = Date(),
        calendar: Calendar = .current,
        generatedAtMs: Int64? = nil
    ) async throws -> SelfHostedPush.Batch? {
        guard stream.mode == .upsertWindow else { return nil }
        let days = min(max(windowDays, 1), 90)
        let end = now
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        let generated = generatedAtMs ?? Int64(now.timeIntervalSince1970 * 1000)

        return try syncRead { db in
            let rows: [Row]
            let window: SelfHostedPush.Window
            switch stream {
            case .dailyMetric, .journal:
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "yyyy-MM-dd"
                let fromDay = formatter.string(from: start)
                let throughDay = formatter.string(from: end)
                rows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM \(stream.rawValue) WHERE day >= ? AND day <= ? ORDER BY day",
                    arguments: [fromDay, throughDay]
                )
                window = .init(field: .day, from: fromDay, through: throughDay)
            case .sleepSession, .workout:
                let fromTs = Int(start.timeIntervalSince1970)
                let throughTs = Int(end.timeIntervalSince1970)
                rows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM \(stream.rawValue) WHERE startTs >= ? AND startTs <= ? ORDER BY startTs",
                    arguments: [fromTs, throughTs]
                )
                window = .init(field: .startTs, from: String(fromTs), through: String(throughTs))
            default:
                return nil
            }
            guard !rows.isEmpty else { return nil }
            return SelfHostedPush.Batch(
                stream: stream,
                generatedAtMs: generated,
                records: rows.map(SelfHostedPush.record),
                cursorFromExclusive: nil,
                cursorToInclusive: nil,
                window: window
            )
        }
    }
}

private extension SelfHostedPush {
    static func record(_ row: Row) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for (column, databaseValue) in row {
            // Internal transport bookkeeping never belongs in the receiver contract.
            guard column != "_noopPushRowID", column != "synced" else { continue }
            result[column] = value(databaseValue)
        }
        return result
    }
}
