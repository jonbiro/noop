import Foundation
import StrandAnalytics
import WhoopStore

public enum RROrderCorpusFormat: String, CaseIterable, Sendable {
    case jsonl
    case csv
}

/// One analysis-ready sleep-session observation. It contains aggregate diagnostics only, never raw R-R rows.
public struct RROrderCorpusRecord: Equatable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let deviceKey: String
    /// Raw database identifier is omitted by default and included only after an explicit CLI opt-in.
    public let deviceID: String?

    public let detectedStartTs: Int
    public let detectedStartUTC: String
    public let effectiveStartTs: Int
    public let effectiveStartUTC: String
    public let endTs: Int
    public let endUTC: String
    public let durationSeconds: Int

    public let userEdited: Bool
    public let stagingSparse: Bool?
    /// Existing cached nightly value, retained as context. It is not used to calculate the audit.
    public let cachedAvgHrvMs: Double?

    public let audit: RROrderAuditReport

    public init(
        deviceKey: String,
        rawDeviceID: String,
        includeDeviceID: Bool,
        session: RROrderCorpusSleepSession,
        rows: [RROrderAuditRow]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.deviceKey = deviceKey
        self.deviceID = includeDeviceID ? rawDeviceID : nil
        self.detectedStartTs = session.detectedStartTs
        self.detectedStartUTC = Self.utcString(session.detectedStartTs)
        self.effectiveStartTs = session.effectiveStartTs
        self.effectiveStartUTC = Self.utcString(session.effectiveStartTs)
        self.endTs = session.endTs
        self.endUTC = Self.utcString(session.endTs)
        self.durationSeconds = session.durationSeconds
        self.userEdited = session.userEdited
        self.stagingSparse = session.stagingSparse
        self.cachedAvgHrvMs = session.cachedAvgHrvMs
        self.audit = RROrderAudit.evaluate(rows)
    }

    private static func utcString(_ unixSeconds: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unixSeconds)))
    }
}

public struct RROrderCorpusRunSummary: Equatable, Sendable, Codable {
    public let deviceCount: Int
    public let sessionsExamined: Int
    public let recordsWritten: Int
    public let sessionsBelowMinimumDuration: Int
    public let invalidSessionWindows: Int
    public let totalIntervals: Int
    public let sessionsWithProductionRmssd: Int
    public let sessionsWithCompleteSameSecondOrder: Int

    public init(
        deviceCount: Int,
        sessionsExamined: Int,
        recordsWritten: Int,
        sessionsBelowMinimumDuration: Int,
        invalidSessionWindows: Int,
        totalIntervals: Int,
        sessionsWithProductionRmssd: Int,
        sessionsWithCompleteSameSecondOrder: Int
    ) {
        self.deviceCount = deviceCount
        self.sessionsExamined = sessionsExamined
        self.recordsWritten = recordsWritten
        self.sessionsBelowMinimumDuration = sessionsBelowMinimumDuration
        self.invalidSessionWindows = invalidSessionWindows
        self.totalIntervals = totalIntervals
        self.sessionsWithProductionRmssd = sessionsWithProductionRmssd
        self.sessionsWithCompleteSameSecondOrder = sessionsWithCompleteSameSecondOrder
    }

    public var text: String {
        "R-R corpus: \(recordsWritten) session(s) written across \(deviceCount) device(s); "
            + "\(totalIntervals) intervals; \(sessionsWithProductionRmssd) session(s) cleared the production HRV gate; "
            + "\(sessionsWithCompleteSameSecondOrder) session(s) had complete same-second order; "
            + "\(sessionsBelowMinimumDuration) below minimum duration; \(invalidSessionWindows) invalid window(s)."
    }
}

public struct RROrderCorpusRunResult: Equatable, Sendable {
    public let records: [RROrderCorpusRecord]
    public let summary: RROrderCorpusRunSummary

    public init(records: [RROrderCorpusRecord], summary: RROrderCorpusRunSummary) {
        self.records = records
        self.summary = summary
    }
}

public enum RROrderCorpusRunner {
    /// Run the audit once per stored sleep session. Empty `requestedDeviceIDs` means every eligible device.
    public static func run(
        database: RROrderCorpusDatabase,
        requestedDeviceIDs: [String],
        from: Int,
        to: Int,
        sessionLimitPerDevice: Int,
        minimumDurationSeconds: Int,
        includeDeviceID: Bool
    ) throws -> RROrderCorpusRunResult {
        let deviceIDs = requestedDeviceIDs.isEmpty
            ? try database.deviceIDs(from: from, to: to)
            : orderedUnique(requestedDeviceIDs)

        var records: [RROrderCorpusRecord] = []
        var sessionsExamined = 0
        var belowMinimum = 0
        var invalidWindows = 0

        for (index, deviceID) in deviceIDs.enumerated() {
            let deviceKey = String(format: "device-%03d", index + 1)
            let sessions = try database.sleepSessions(
                deviceID: deviceID,
                from: from,
                to: to,
                limit: sessionLimitPerDevice
            )

            for session in sessions {
                sessionsExamined += 1
                guard session.durationSeconds > 0 else {
                    invalidWindows += 1
                    continue
                }
                guard session.durationSeconds >= minimumDurationSeconds else {
                    belowMinimum += 1
                    continue
                }

                let rows = try database.rrOrderAuditRows(
                    deviceID: deviceID,
                    from: session.effectiveStartTs,
                    to: session.endTs
                )
                records.append(RROrderCorpusRecord(
                    deviceKey: deviceKey,
                    rawDeviceID: deviceID,
                    includeDeviceID: includeDeviceID,
                    session: session,
                    rows: rows
                ))
            }
        }

        records.sort {
            if $0.detectedStartTs != $1.detectedStartTs { return $0.detectedStartTs < $1.detectedStartTs }
            return $0.deviceKey < $1.deviceKey
        }

        let summary = RROrderCorpusRunSummary(
            deviceCount: deviceIDs.count,
            sessionsExamined: sessionsExamined,
            recordsWritten: records.count,
            sessionsBelowMinimumDuration: belowMinimum,
            invalidSessionWindows: invalidWindows,
            totalIntervals: records.reduce(0) { $0 + $1.audit.provenance.totalIntervals },
            sessionsWithProductionRmssd: records.reduce(0) {
                $0 + ($1.audit.currentOrder.rmssdMs == nil ? 0 : 1)
            },
            sessionsWithCompleteSameSecondOrder: records.reduce(0) {
                $0 + ($1.audit.provenance.hasCompleteSameSecondOrder ? 1 : 0)
            }
        )
        return RROrderCorpusRunResult(records: records, summary: summary)
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

public enum RROrderCorpusEncoder {
    public static func encode(_ records: [RROrderCorpusRecord], format: RROrderCorpusFormat) throws -> Data {
        switch format {
        case .jsonl:
            return try encodeJSONLines(records)
        case .csv:
            return encodeCSV(records)
        }
    }

    private static func encodeJSONLines(_ records: [RROrderCorpusRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var output = Data()
        for record in records {
            output.append(try encoder.encode(record))
            output.append(0x0A)
        }
        return output
    }

    private static func encodeCSV(_ records: [RROrderCorpusRecord]) -> Data {
        var lines = [csvHeader.map(csvEscape).joined(separator: ",")]
        lines.reserveCapacity(records.count + 1)
        for record in records {
            lines.append(csvValues(record).map(csvEscape).joined(separator: ","))
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static let csvHeader = [
        "schema_version", "device_key", "device_id",
        "detected_start_ts", "detected_start_utc", "effective_start_ts", "effective_start_utc",
        "end_ts", "end_utc", "duration_seconds", "user_edited", "staging_sparse", "cached_avg_hrv_ms",
        "total_intervals", "intervals_with_recorded_order", "intervals_with_unknown_order",
        "recorded_order_fraction", "single_beat_seconds", "multi_beat_seconds", "multi_beat_intervals",
        "trustworthy_multi_beat_seconds", "trustworthy_multi_beat_intervals",
        "trustworthy_multi_beat_interval_fraction", "all_unknown_multi_beat_seconds",
        "all_unknown_multi_beat_intervals", "mixed_order_multi_beat_seconds", "mixed_order_multi_beat_intervals",
        "ambiguous_recorded_order_multi_beat_seconds", "ambiguous_recorded_order_multi_beat_intervals",
        "magnitude_reordered_trustworthy_seconds", "magnitude_reordered_trustworthy_intervals",
        "complete_same_second_order",
        "current_rmssd_ms", "magnitude_rmssd_ms", "rmssd_delta_ms", "rmssd_delta_pct_of_current",
        "current_sdnn_ms", "magnitude_sdnn_ms", "current_mean_nn_ms", "magnitude_mean_nn_ms",
        "current_pnn50_pct", "magnitude_pnn50_pct", "current_n_input", "current_n_clean",
        "magnitude_n_input", "magnitude_n_clean", "current_raw_rmssd_ms", "magnitude_raw_rmssd_ms",
        "raw_rmssd_delta_ms", "raw_rmssd_delta_pct_of_current",
    ]

    private static func csvValues(_ record: RROrderCorpusRecord) -> [String] {
        let provenance = record.audit.provenance
        let current = record.audit.currentOrder
        let magnitude = record.audit.magnitudeOrderCounterfactual
        return [
            String(record.schemaVersion), record.deviceKey, record.deviceID ?? "",
            String(record.detectedStartTs), record.detectedStartUTC,
            String(record.effectiveStartTs), record.effectiveStartUTC,
            String(record.endTs), record.endUTC, String(record.durationSeconds),
            String(record.userEdited), optionalBool(record.stagingSparse), number(record.cachedAvgHrvMs),
            String(provenance.totalIntervals), String(provenance.intervalsWithRecordedOrder),
            String(provenance.intervalsWithUnknownOrder), number(provenance.recordedOrderFraction),
            String(provenance.singleBeatSeconds), String(provenance.multiBeatSeconds),
            String(provenance.multiBeatIntervals), String(provenance.trustworthyMultiBeatSeconds),
            String(provenance.trustworthyMultiBeatIntervals),
            number(provenance.trustworthyMultiBeatIntervalFraction),
            String(provenance.allUnknownMultiBeatSeconds), String(provenance.allUnknownMultiBeatIntervals),
            String(provenance.mixedOrderMultiBeatSeconds), String(provenance.mixedOrderMultiBeatIntervals),
            String(provenance.ambiguousRecordedOrderMultiBeatSeconds),
            String(provenance.ambiguousRecordedOrderMultiBeatIntervals),
            String(provenance.magnitudeReorderedTrustworthySeconds),
            String(provenance.magnitudeReorderedTrustworthyIntervals),
            String(provenance.hasCompleteSameSecondOrder),
            number(current.rmssdMs), number(magnitude.rmssdMs), number(record.audit.rmssdCurrentMinusMagnitudeMs),
            number(record.audit.rmssdCurrentMinusMagnitudePctOfCurrent),
            number(current.sdnnMs), number(magnitude.sdnnMs), number(current.meanNNMs), number(magnitude.meanNNMs),
            number(current.pnn50Pct), number(magnitude.pnn50Pct), String(current.nInput), String(current.nClean),
            String(magnitude.nInput), String(magnitude.nClean), number(current.rawRmssdMs),
            number(magnitude.rawRmssdMs), number(record.audit.rawRmssdCurrentMinusMagnitudeMs),
            number(record.audit.rawRmssdCurrentMinusMagnitudePctOfCurrent),
        ]
    }

    private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func optionalBool(_ value: Bool?) -> String {
        value.map { String($0) } ?? ""
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
