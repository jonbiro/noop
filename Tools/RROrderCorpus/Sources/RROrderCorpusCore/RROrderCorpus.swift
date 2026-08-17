import Foundation
import StrandAnalytics
import WhoopStore

public enum RROrderCorpusFormat: String, CaseIterable, Sendable {
    case jsonl
    case csv
}

/// One analysis-ready sleep-session observation. It contains aggregate diagnostics only, never raw R-R rows.
public struct RROrderCorpusRecord: Equatable, Sendable, Codable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let auditSchemaVersion: Int
    public let observationKey: String
    public let deviceKey: String
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
    public let cachedAvgHrvMs: Double?
    public let inputCounts: RROrderCorpusInputCounts
    public let audit: RROrderAuditReport

    public init(deviceKey: String, rawDeviceID: String, includeDeviceID: Bool,
                session: RROrderCorpusSleepSession, window: RROrderCorpusAuditWindow) {
        schemaVersion = Self.currentSchemaVersion
        auditSchemaVersion = RROrderAuditReport.currentSchemaVersion
        self.deviceKey = deviceKey
        deviceID = includeDeviceID ? rawDeviceID : nil
        detectedStartTs = session.detectedStartTs
        detectedStartUTC = Self.utcString(session.detectedStartTs)
        effectiveStartTs = session.effectiveStartTs
        effectiveStartUTC = Self.utcString(session.effectiveStartTs)
        endTs = session.endTs
        endUTC = Self.utcString(session.endTs)
        durationSeconds = session.durationSeconds
        userEdited = session.userEdited
        stagingSparse = session.stagingSparse
        cachedAvgHrvMs = session.cachedAvgHrvMs
        inputCounts = window.inputCounts
        audit = RROrderAudit.evaluate(window.rows)
        observationKey = "\(deviceKey):\(session.detectedStartTs):\(session.endTs)"
    }

    private static func utcString(_ unixSeconds: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unixSeconds)))
    }
}

public struct RROrderCorpusIntegrityCounts: Equatable, Sendable, Codable {
    public let noData: Int
    public let complete: Int
    public let partial: Int
    public let ambiguous: Int

    init(records: [RROrderCorpusRecord]) {
        noData = records.filter { $0.audit.integrityStatus == .noData }.count
        complete = records.filter { $0.audit.integrityStatus == .complete }.count
        partial = records.filter { $0.audit.integrityStatus == .partial }.count
        ambiguous = records.filter { $0.audit.integrityStatus == .ambiguous }.count
    }
}

public struct RROrderCorpusRunSummary: Equatable, Sendable, Codable {
    public let databaseUserVersion: Int
    public let deviceCount: Int
    public let sessionsExamined: Int
    public let recordsWritten: Int
    public let sessionsBelowMinimumDuration: Int
    public let invalidSessionWindows: Int
    public let totalRowsInWindows: Int
    public let scoringRows: Int
    public let excludedRows: Int
    public let totalIntervals: Int
    public let sessionsWithProductionRmssd: Int
    public let integrity: RROrderCorpusIntegrityCounts
    public let sessionsWithCounterfactualCleaningChange: Int
    public let rawInvariantFailures: Int

    public var text: String {
        "R-R corpus v\(RROrderCorpusRecord.currentSchemaVersion): \(recordsWritten) session(s), "
            + "\(deviceCount) device(s), \(totalIntervals) scoring intervals; "
            + "integrity complete/partial/ambiguous/no-data = \(integrity.complete)/\(integrity.partial)/\(integrity.ambiguous)/\(integrity.noData); "
            + "\(sessionsWithProductionRmssd) production HRV result(s); \(excludedRows) row(s) excluded by scoring filters; "
            + "\(sessionsWithCounterfactualCleaningChange) cleaning-change session(s); \(rawInvariantFailures) raw invariant failure(s)."
    }
}

public struct RROrderCorpusRunResult: Equatable, Sendable {
    public let records: [RROrderCorpusRecord]
    public let summary: RROrderCorpusRunSummary
}

public enum RROrderCorpusRunner {
    public static func run(database: RROrderCorpusDatabase, requestedDeviceIDs: [String], from: Int, to: Int,
                           sessionLimitPerDevice: Int, minimumDurationSeconds: Int,
                           includeDeviceID: Bool) throws -> RROrderCorpusRunResult {
        let deviceIDs = requestedDeviceIDs.isEmpty
            ? try database.deviceIDs(from: from, to: to)
            : orderedUnique(requestedDeviceIDs)

        var records: [RROrderCorpusRecord] = []
        var sessionsExamined = 0
        var belowMinimum = 0
        var invalidWindows = 0

        for (index, deviceID) in deviceIDs.enumerated() {
            let deviceKey = String(format: "device-%03d", index + 1)
            let sessions = try database.sleepSessions(deviceID: deviceID, from: from, to: to,
                                                      limit: sessionLimitPerDevice)
            for session in sessions {
                sessionsExamined += 1
                guard session.durationSeconds > 0 else { invalidWindows += 1; continue }
                guard session.durationSeconds >= minimumDurationSeconds else { belowMinimum += 1; continue }
                let window = try database.rrOrderAuditWindow(
                    deviceID: deviceID,
                    from: session.effectiveStartTs,
                    to: session.endTs
                )
                records.append(RROrderCorpusRecord(
                    deviceKey: deviceKey,
                    rawDeviceID: deviceID,
                    includeDeviceID: includeDeviceID,
                    session: session,
                    window: window
                ))
            }
        }

        records.sort {
            if $0.detectedStartTs != $1.detectedStartTs { return $0.detectedStartTs < $1.detectedStartTs }
            return $0.deviceKey < $1.deviceKey
        }

        let integrity = RROrderCorpusIntegrityCounts(records: records)
        let summary = RROrderCorpusRunSummary(
            databaseUserVersion: database.userVersion,
            deviceCount: deviceIDs.count,
            sessionsExamined: sessionsExamined,
            recordsWritten: records.count,
            sessionsBelowMinimumDuration: belowMinimum,
            invalidSessionWindows: invalidWindows,
            totalRowsInWindows: records.reduce(0) { $0 + $1.inputCounts.totalRowsInWindow },
            scoringRows: records.reduce(0) { $0 + $1.inputCounts.scoringRows },
            excludedRows: records.reduce(0) { $0 + $1.inputCounts.excludedRows },
            totalIntervals: records.reduce(0) { $0 + $1.audit.provenance.totalIntervals },
            sessionsWithProductionRmssd: records.filter { $0.audit.currentOrder.rmssdMs != nil }.count,
            integrity: integrity,
            sessionsWithCounterfactualCleaningChange: records.filter {
                $0.audit.flags.contains(.counterfactualChangesCleaningOutcome)
            }.count,
            rawInvariantFailures: records.filter { !$0.audit.rawOrderInvariantPreserved }.count
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
        case .jsonl: return try encodeJSONLines(records)
        case .csv: return encodeCSV(records)
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
        for record in records { lines.append(csvValues(record).map(csvEscape).joined(separator: ",")) }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static let csvHeader = [
        "schema_version", "audit_schema_version", "observation_key", "device_key", "device_id",
        "detected_start_ts", "detected_start_utc", "effective_start_ts", "effective_start_utc",
        "end_ts", "end_utc", "duration_seconds", "user_edited", "staging_sparse", "cached_avg_hrv_ms",
        "total_rows_in_window", "scoring_rows", "excluded_rows", "spo2_ibi_rows", "suspect_timestamp_rows", "scoring_fraction",
        "integrity_status", "audit_flags", "total_intervals", "first_rr_ts", "last_rr_ts", "rr_span_seconds",
        "distinct_seconds", "max_intervals_per_second", "recorded_order_fraction", "multi_beat_intervals",
        "trustworthy_multi_beat_interval_fraction", "legacy_unknown_seconds", "mixed_order_seconds", "ambiguous_order_seconds",
        "reordered_groups", "reordered_group_fraction", "value_inversions", "possible_value_inversions",
        "normalized_inversion_fraction", "max_inversions_in_group", "max_trustworthy_group_size",
        "current_rmssd_ms", "magnitude_rmssd_ms", "rmssd_delta_ms", "rmssd_delta_pct_current",
        "current_sdnn_ms", "magnitude_sdnn_ms", "sdnn_delta_ms", "sdnn_delta_pct_current",
        "current_mean_nn_ms", "magnitude_mean_nn_ms", "mean_nn_delta_ms", "mean_nn_delta_pct_current",
        "current_pnn50_pct", "magnitude_pnn50_pct", "pnn50_delta_percentage_points",
        "current_input", "current_production_n_clean", "current_actual_clean_count", "current_rejected_count",
        "current_rejected_fraction", "current_contiguous_pairs", "current_meets_beat_gate",
        "magnitude_production_n_clean", "magnitude_actual_clean_count", "magnitude_rejected_count",
        "magnitude_rejected_fraction", "magnitude_contiguous_pairs", "magnitude_meets_beat_gate",
        "current_raw_rmssd_ms", "magnitude_raw_rmssd_ms", "raw_rmssd_delta_ms", "raw_rmssd_delta_pct_current",
        "current_raw_pnn50_pct", "magnitude_raw_pnn50_pct", "raw_pnn50_delta_percentage_points",
        "current_raw_sdnn_ms", "magnitude_raw_sdnn_ms", "current_raw_mean_nn_ms", "magnitude_raw_mean_nn_ms",
        "raw_order_invariant_preserved",
    ]

    private static func csvValues(_ record: RROrderCorpusRecord) -> [String] {
        let p = record.audit.provenance
        let impact = record.audit.permutationImpact
        let current = record.audit.currentOrder
        let magnitude = record.audit.magnitudeOrderCounterfactual
        return [
            String(record.schemaVersion), String(record.auditSchemaVersion), record.observationKey,
            record.deviceKey, record.deviceID ?? "",
            String(record.detectedStartTs), record.detectedStartUTC, String(record.effectiveStartTs),
            record.effectiveStartUTC, String(record.endTs), record.endUTC, String(record.durationSeconds),
            String(record.userEdited), optionalBool(record.stagingSparse), number(record.cachedAvgHrvMs),
            String(record.inputCounts.totalRowsInWindow), String(record.inputCounts.scoringRows),
            String(record.inputCounts.excludedRows), String(record.inputCounts.spo2IbiRows),
            String(record.inputCounts.suspectTimestampRows), number(record.inputCounts.scoringFraction),
            record.audit.integrityStatus.rawValue, record.audit.flags.map(\.rawValue).joined(separator: "|"),
            String(p.totalIntervals), optionalInt(p.firstTs), optionalInt(p.lastTs), optionalInt(p.spanSeconds),
            String(p.distinctSeconds), String(p.maxIntervalsPerSecond), number(p.recordedOrderFraction),
            String(p.multiBeatIntervals), number(p.trustworthyMultiBeatIntervalFraction),
            String(p.allUnknownMultiBeatSeconds), String(p.mixedOrderMultiBeatSeconds),
            String(p.ambiguousRecordedOrderMultiBeatSeconds), String(impact.reorderedGroups),
            number(impact.reorderedGroupFraction), String(impact.valueInversions), String(impact.possibleValueInversions),
            number(impact.normalizedValueInversionFraction), String(impact.maxValueInversionsInGroup),
            String(impact.maxTrustworthyGroupSize),
            number(current.rmssdMs), number(magnitude.rmssdMs), number(record.audit.rmssdCurrentMinusMagnitudeMs),
            number(record.audit.rmssdCurrentMinusMagnitudePctOfCurrent),
            number(current.sdnnMs), number(magnitude.sdnnMs), number(record.audit.sdnnCurrentMinusMagnitudeMs),
            number(record.audit.sdnnCurrentMinusMagnitudePctOfCurrent),
            number(current.meanNNMs), number(magnitude.meanNNMs), number(record.audit.meanNNCurrentMinusMagnitudeMs),
            number(record.audit.meanNNCurrentMinusMagnitudePctOfCurrent),
            number(current.pnn50Pct), number(magnitude.pnn50Pct), number(record.audit.pnn50CurrentMinusMagnitudePercentagePoints),
            String(current.nInput), String(current.nClean), String(current.actualCleanCount), String(current.rejectedCount),
            number(current.rejectedFraction), String(current.contiguousPairCount), String(current.meetsProductionBeatGate),
            String(magnitude.nClean), String(magnitude.actualCleanCount), String(magnitude.rejectedCount),
            number(magnitude.rejectedFraction), String(magnitude.contiguousPairCount), String(magnitude.meetsProductionBeatGate),
            number(current.rawRmssdMs), number(magnitude.rawRmssdMs), number(record.audit.rawRmssdCurrentMinusMagnitudeMs),
            number(record.audit.rawRmssdCurrentMinusMagnitudePctOfCurrent),
            number(current.rawPnn50Pct), number(magnitude.rawPnn50Pct),
            number(record.audit.rawPnn50CurrentMinusMagnitudePercentagePoints),
            number(current.rawSdnnMs), number(magnitude.rawSdnnMs), number(current.rawMeanNNMs), number(magnitude.rawMeanNNMs),
            String(record.audit.rawOrderInvariantPreserved),
        ]
    }

    private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func optionalInt(_ value: Int?) -> String { value.map(String.init) ?? "" }
    private static func optionalBool(_ value: Bool?) -> String { value.map(String.init) ?? "" }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
