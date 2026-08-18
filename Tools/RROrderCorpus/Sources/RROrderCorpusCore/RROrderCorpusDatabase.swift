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
                throw RROrderCorpusDatabaseError.databaseNotFound("NOOP database not found at --db path: \(expanded)")
            }
            return expanded
        }
        if let environmentPath = nonEmpty(environment["NOOP_DB_PATH"]) {
            let expanded = expandHome(environmentPath, home: home)
            guard fm.fileExists(atPath: expanded) else {
                throw RROrderCorpusDatabaseError.databaseNotFound("NOOP database not found at NOOP_DB_PATH: \(expanded)")
            }
            return expanded
        }
        let bundleID = nonEmpty(environment["NOOP_BUNDLE_ID"]) ?? productionBundleID
        let candidates = databaseCandidates(bundleID: bundleID, home: home)
        if let existing = candidates.first(where: fm.fileExists(atPath:)) { return existing }
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

public struct RROrderCorpusSleepSession: Equatable, Sendable, Codable {
    public let detectedStartTs: Int
    public let endTs: Int
    public let cachedAvgHrvMs: Double?
    public let userEdited: Bool
    public let startTsAdjusted: Int?
    public let stagingSparse: Bool?

    public init(detectedStartTs: Int, endTs: Int, cachedAvgHrvMs: Double?, userEdited: Bool,
                startTsAdjusted: Int?, stagingSparse: Bool?) {
        self.detectedStartTs = detectedStartTs
        self.endTs = endTs
        self.cachedAvgHrvMs = cachedAvgHrvMs
        self.userEdited = userEdited
        self.startTsAdjusted = startTsAdjusted
        self.stagingSparse = stagingSparse
    }

    public var effectiveStartTs: Int { startTsAdjusted ?? detectedStartTs }
    public var durationSeconds: Int { endTs - effectiveStartTs }
}

/// Counts before and after the exact production R-R population filters.
public struct RROrderCorpusInputCounts: Equatable, Sendable, Codable {
    public let totalRowsInWindow: Int
    public let scoringRows: Int
    public let excludedRows: Int
    public let spo2IbiRows: Int
    public let suspectTimestampRows: Int

    public init(totalRowsInWindow: Int, scoringRows: Int, spo2IbiRows: Int, suspectTimestampRows: Int) {
        self.totalRowsInWindow = totalRowsInWindow
        self.scoringRows = scoringRows
        self.excludedRows = max(0, totalRowsInWindow - scoringRows)
        self.spo2IbiRows = spo2IbiRows
        self.suspectTimestampRows = suspectTimestampRows
    }

    public var scoringFraction: Double? {
        guard totalRowsInWindow > 0 else { return nil }
        return Double(scoringRows) / Double(totalRowsInWindow)
    }
}

public struct RROrderCorpusAuditWindow: Equatable, Sendable {
    public let rows: [RROrderAuditRow]
    public let inputCounts: RROrderCorpusInputCounts
}

/// Strictly read-only access to the tables needed by the corpus experiment.
public final class RROrderCorpusDatabase {
    public let path: String
    public let userVersion: Int
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
        self.userVersion = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        }
        try validateSchema()
    }

    public func deviceIDs(from: Int, to: Int) throws -> [String] {
        try validateRange(from: from, to: to)
        return try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT s.deviceId
                FROM sleepSession s
                WHERE s.startTs >= ? AND s.startTs <= ?
                  AND EXISTS (SELECT 1 FROM rrInterval r WHERE r.deviceId = s.deviceId LIMIT 1)
                ORDER BY s.deviceId ASC
                """, arguments: [from, to])
        }
    }

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
                """, arguments: [deviceID, from, to, limit]).map { row in
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

    /// Read the exact scoring population plus aggregate exclusion counts for the same bounded window.
    public func rrOrderAuditWindow(deviceID: String, from: Int, to: Int) throws -> RROrderCorpusAuditWindow {
        try validateRange(from: from, to: to)
        return try dbQueue.read { db in
            let countRow = try Row.fetchOne(db, sql: """
                SELECT
                    COUNT(*) AS totalRows,
                    SUM(CASE WHEN (srcChannel IS NULL OR srcChannel <> ?) AND
                                      (tsSuspect IS NULL OR tsSuspect <> 1)
                             THEN 1 ELSE 0 END) AS scoringRows,
                    SUM(CASE WHEN srcChannel = ? THEN 1 ELSE 0 END) AS spo2Rows,
                    SUM(CASE WHEN tsSuspect = 1 THEN 1 ELSE 0 END) AS suspectRows
                FROM rrInterval
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                """, arguments: [RRSourceChannel.spo2Ibi.rawValue, RRSourceChannel.spo2Ibi.rawValue,
                                  deviceID, from, to])
            let totalRows: Int = countRow?["totalRows"] ?? 0
            let scoringRows: Int = countRow?["scoringRows"] ?? 0
            let spo2Rows: Int = countRow?["spo2Rows"] ?? 0
            let suspectRows: Int = countRow?["suspectRows"] ?? 0

            let rows = try Row.fetchAll(db, sql: """
                SELECT ts, rrMs, seq, ord
                FROM rrInterval
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                  AND (srcChannel IS NULL OR srcChannel <> ?)
                  AND (tsSuspect IS NULL OR tsSuspect <> 1)
                ORDER BY ts ASC, ord ASC, rrMs ASC, seq ASC
                """, arguments: [deviceID, from, to, RRSourceChannel.spo2Ibi.rawValue]).map { row in
                    RROrderAuditRow(ts: row["ts"], rrMs: row["rrMs"], seq: row["seq"], emissionOrder: row["ord"])
                }
            return RROrderCorpusAuditWindow(
                rows: rows,
                inputCounts: RROrderCorpusInputCounts(
                    totalRowsInWindow: totalRows,
                    scoringRows: scoringRows,
                    spo2IbiRows: spo2Rows,
                    suspectTimestampRows: suspectRows
                )
            )
        }
    }

    /// Compatibility helper for tests and focused callers.
    public func rrOrderAuditRows(deviceID: String, from: Int, to: Int) throws -> [RROrderAuditRow] {
        try rrOrderAuditWindow(deviceID: deviceID, from: from, to: to).rows
    }

    private func validateRange(from: Int, to: Int) throws {
        guard from <= to else { throw RROrderCorpusDatabaseError.invalidRange(from: from, to: to) }
    }

    private func validateSchema() throws {
        try dbQueue.read { db in
            let tableNames = try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
            let required: [String: Set<String>] = [
                "sleepSession": ["deviceId", "startTs", "endTs", "avgHrv", "userEdited", "startTsAdjusted", "stagingSparse"],
                "rrInterval": ["deviceId", "ts", "rrMs", "seq", "ord", "srcChannel", "tsSuspect"],
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
