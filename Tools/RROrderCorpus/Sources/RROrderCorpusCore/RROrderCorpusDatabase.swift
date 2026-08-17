import Foundation
import GRDB
import WhoopProtocol
import WhoopStore

public enum RROrderCorpusDatabaseError: Error, Equatable, CustomStringConvertible {
    case databaseNotFound(String)
    case incompatibleSchema(String)
    case invalidRange(from: Int, to: Int)
    case invalidLimit(Int)

    public var description: String {
        switch self {
        case .databaseNotFound(let message), .incompatibleSchema(let message):
            return message
        case .invalidRange(let from, let to):
            return "Invalid session range: from (\(from)) must be less than or equal to to (\(to))."
        case .invalidLimit(let value):
            return "Session limit must be greater than zero; received \(value)."
        }
    }
}

/// Resolves the local NOOP SQLite database without opening or modifying it.
public enum RROrderCorpusDatabasePath {
    public static let productionBundleID = "com.noopapp.noop"

    public static func resolve(
        explicitPath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) throws -> String {
        let fm = FileManager.default

        if let explicitPath = nonEmpty(explicitPath) {
            let expanded = expandHome(explicitPath, home: home)
            guard fm.fileExists(atPath: expanded) else {
                throw RROrderCorpusDatabaseError.databaseNotFound(
                    "NOOP database not found at --db path: \(expanded)"
                )
            }
            return expanded
        }

        if let environmentPath = nonEmpty(environment["NOOP_DB_PATH"]) {
            let expanded = expandHome(environmentPath, home: home)
            guard fm.fileExists(atPath: expanded) else {
                throw RROrderCorpusDatabaseError.databaseNotFound(
                    "NOOP database not found at NOOP_DB_PATH: \(expanded)"
                )
            }
            return expanded
        }

        let bundleID = nonEmpty(environment["NOOP_BUNDLE_ID"]) ?? productionBundleID
        let candidates = databaseCandidates(bundleID: bundleID, home: home)
        if let existing = candidates.first(where: fm.fileExists(atPath:)) {
            return existing
        }

        throw RROrderCorpusDatabaseError.databaseNotFound(
            "No NOOP database was found. Start NOOP once or pass --db. Checked: \(candidates.joined(separator: ", "))"
        )
    }

    public static func databaseCandidates(bundleID: String = productionBundleID, home: String) -> [String] {
        orderedUnique([
            "\(home)/Library/Containers/\(bundleID)/Data/Library/Application Support/OpenWhoop/whoop.sqlite",
            "\(home)/Library/Application Support/OpenWhoop/whoop.sqlite",
        ])
    }

    public static func expandHome(_ path: String, home: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return home + String(path.dropFirst())
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

/// The stored sleep-session window used as one corpus observation.
public struct RROrderCorpusSleepSession: Equatable, Sendable, Codable {
    public let detectedStartTs: Int
    public let endTs: Int
    public let cachedAvgHrvMs: Double?
    public let userEdited: Bool
    public let startTsAdjusted: Int?
    public let stagingSparse: Bool?

    public init(
        detectedStartTs: Int,
        endTs: Int,
        cachedAvgHrvMs: Double?,
        userEdited: Bool,
        startTsAdjusted: Int?,
        stagingSparse: Bool?
    ) {
        self.detectedStartTs = detectedStartTs
        self.endTs = endTs
        self.cachedAvgHrvMs = cachedAvgHrvMs
        self.userEdited = userEdited
        self.startTsAdjusted = startTsAdjusted
        self.stagingSparse = stagingSparse
    }

    /// User-corrected onset when present; otherwise the immutable detected session key.
    public var effectiveStartTs: Int { startTsAdjusted ?? detectedStartTs }

    public var durationSeconds: Int { endTs - effectiveStartTs }
}

/// Strictly read-only access to the two tables needed by the corpus experiment.
///
/// This intentionally does not instantiate `WhoopStore(path:)`: that initializer runs migrations and owns
/// a writable pool. The corpus tool opens SQLite with GRDB's `readonly` configuration, validates the current
/// schema, and executes the same R-R population predicate and ordering as `WhoopStore.rrOrderAuditRows`.
public final class RROrderCorpusDatabase {
    public let path: String
    private let dbQueue: DatabaseQueue

    public init(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw RROrderCorpusDatabaseError.databaseNotFound("NOOP database not found at: \(path)")
        }

        var configuration = Configuration()
        configuration.readonly = true
        configuration.busyMode = .timeout(5)

        self.path = path
        self.dbQueue = try DatabaseQueue(path: path, configuration: configuration)
        try validateSchema()
    }

    /// Devices with at least one stored sleep session in the requested detected-start range and at least
    /// one R-R row anywhere in the database. Sorted so pseudonym assignment is deterministic.
    public func deviceIDs(from: Int, to: Int) throws -> [String] {
        try validateRange(from: from, to: to)
        return try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT s.deviceId
                FROM sleepSession s
                WHERE s.startTs >= ? AND s.startTs <= ?
                  AND EXISTS (
                    SELECT 1 FROM rrInterval r
                    WHERE r.deviceId = s.deviceId
                    LIMIT 1
                  )
                ORDER BY s.deviceId ASC
                """, arguments: [from, to])
        }
    }

    /// Stored sleep sessions selected by their immutable detected start, oldest first.
    public func sleepSessions(deviceID: String, from: Int, to: Int, limit: Int) throws -> [RROrderCorpusSleepSession] {
        try validateRange(from: from, to: to)
        guard limit > 0 else { throw RROrderCorpusDatabaseError.invalidLimit(limit) }

        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT startTs, endTs, avgHrv, userEdited, startTsAdjusted, stagingSparse
                FROM sleepSession
                WHERE deviceId = ? AND startTs >= ? AND startTs <= ?
                ORDER BY startTs ASC
                LIMIT ?
                """, arguments: [deviceID, from, to, limit])
                .map { row in
                    let userEditedInt: Int = row["userEdited"]
                    let stagingSparseInt: Int? = row["stagingSparse"]
                    return RROrderCorpusSleepSession(
                        detectedStartTs: row["startTs"],
                        endTs: row["endTs"],
                        cachedAvgHrvMs: row["avgHrv"],
                        userEdited: userEditedInt != 0,
                        startTsAdjusted: row["startTsAdjusted"],
                        stagingSparse: stagingSparseInt.map { $0 != 0 }
                    )
                }
        }
    }

    /// Exact diagnostic twin of `WhoopStore.rrOrderAuditRows` over a bounded session window.
    public func rrOrderAuditRows(deviceID: String, from: Int, to: Int) throws -> [RROrderAuditRow] {
        try validateRange(from: from, to: to)
        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, rrMs, seq, ord
                FROM rrInterval
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                  AND (srcChannel IS NULL OR srcChannel <> ?)
                  AND (tsSuspect IS NULL OR tsSuspect <> 1)
                ORDER BY ts ASC, ord ASC, rrMs ASC, seq ASC
                """, arguments: [deviceID, from, to, RRSourceChannel.spo2Ibi.rawValue])
                .map { row in
                    RROrderAuditRow(
                        ts: row["ts"],
                        rrMs: row["rrMs"],
                        seq: row["seq"],
                        emissionOrder: row["ord"]
                    )
                }
        }
    }

    private func validateRange(from: Int, to: Int) throws {
        guard from <= to else { throw RROrderCorpusDatabaseError.invalidRange(from: from, to: to) }
    }

    private func validateSchema() throws {
        try dbQueue.read { db in
            let tableNames = try Set(String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            ))

            let required: [String: Set<String>] = [
                "sleepSession": [
                    "deviceId", "startTs", "endTs", "avgHrv", "userEdited",
                    "startTsAdjusted", "stagingSparse",
                ],
                "rrInterval": [
                    "deviceId", "ts", "rrMs", "seq", "ord", "srcChannel", "tsSuspect",
                ],
            ]

            for (table, expectedColumns) in required {
                guard tableNames.contains(table) else {
                    throw RROrderCorpusDatabaseError.incompatibleSchema(
                        "The NOOP database is missing required table \(table). Launch the current app before running the corpus tool."
                    )
                }
                let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
                let actualColumns = Set(rows.map { (row: Row) -> String in row["name"] })
                let missing = expectedColumns.subtracting(actualColumns).sorted()
                guard missing.isEmpty else {
                    throw RROrderCorpusDatabaseError.incompatibleSchema(
                        "The NOOP database table \(table) is missing current audit columns: \(missing.joined(separator: ", ")). Launch the current app before running the corpus tool."
                    )
                }
            }
        }
    }
}
