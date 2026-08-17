import Foundation
import GRDB
import WhoopProtocol

/// One R-R row with the storage-only fields needed to audit same-second ordering.
///
/// `RRInterval` intentionally exposes only physiological data (`ts`, `rrMs`, source channel). The
/// database's `ord` and `seq` fields are storage mechanics, so production analytics should not depend on
/// them. This diagnostic row keeps that boundary intact while allowing an integrity audit to distinguish
/// observed emission order from legacy or split-batch fallback order.
public struct RROrderAuditRow: Equatable, Sendable, Codable {
    public let ts: Int
    public let rrMs: Int
    public let seq: Int
    /// Batch-local emission position recorded at insert time. nil means the order was never observed.
    public let emissionOrder: Int?

    public init(ts: Int, rrMs: Int, seq: Int, emissionOrder: Int?) {
        self.ts = ts
        self.rrMs = rrMs
        self.seq = seq
        self.emissionOrder = emissionOrder
    }
}

public extension WhoopStore {
    /// Read the exact R-R population used by scoring, while retaining order provenance for diagnostics.
    ///
    /// This mirrors `rrIntervals(deviceId:from:to:limit:)` exactly:
    /// - excludes Oura's duplicate SpO2 IBI channel;
    /// - excludes future-stamped/suspect rows;
    /// - uses SQLite's current production order (`ts`, nullable `ord`, `rrMs`, `seq`).
    ///
    /// The caller must provide a bounded time range. There is deliberately no independent row limit:
    /// truncating a window would make the provenance fractions and HRV counterfactual describe a
    /// different population than the requested window.
    func rrOrderAuditRows(deviceId: String, from: Int, to: Int) async throws -> [RROrderAuditRow] {
        try syncRead { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT ts, rrMs, seq, ord
                FROM rrInterval
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                  AND (srcChannel IS NULL OR srcChannel <> ?)
                  AND (tsSuspect IS NULL OR tsSuspect <> 1)
                ORDER BY ts ASC, ord ASC, rrMs ASC, seq ASC
                """, arguments: [deviceId, from, to, RRSourceChannel.spo2Ibi.rawValue])
            return rows.map { row in
                let ts: Int = row["ts"]
                let rrMs: Int = row["rrMs"]
                let seq: Int = row["seq"]
                let ord: Int? = row["ord"]
                return RROrderAuditRow(ts: ts, rrMs: rrMs, seq: seq, emissionOrder: ord)
            }
        }
    }
}
