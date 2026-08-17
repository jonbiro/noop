import Foundation

public enum RROrderCorpusSummaryFormat: String, CaseIterable, Sendable {
    case json
    case markdown
}

public enum RROrderCorpusSummaryError: Error, Equatable, CustomStringConvertible {
    case invalidUTF8
    case invalidJSONLine(line: Int, message: String)
    case unsupportedRecordSchema(line: Int?, version: Int)
    case duplicateObservation(deviceKey: String, detectedStartTs: Int, endTs: Int)

    public var description: String {
        switch self {
        case .invalidUTF8:
            return "Corpus input is not valid UTF-8."
        case .invalidJSONLine(let line, let message):
            return "Invalid corpus JSON on line \(line): \(message)"
        case .unsupportedRecordSchema(let line, let version):
            if let line {
                return "Unsupported corpus record schemaVersion \(version) on line \(line)."
            }
            return "Unsupported corpus record schemaVersion \(version)."
        case .duplicateObservation(let deviceKey, let start, let end):
            return "Duplicate corpus observation for \(deviceKey) at detectedStartTs=\(start), endTs=\(end)."
        }
    }
}

/// Deterministic R-7 percentile summary, the default quantile method used by R, NumPy, and many
/// statistical packages. Values are expected to be finite because JSON cannot encode NaN or infinity.
public struct RROrderDistributionSummary: Equatable, Sendable, Codable {
    public let count: Int
    public let minimum: Double
    public let p10: Double
    public let p25: Double
    public let median: Double
    public let p75: Double
    public let p90: Double
    public let maximum: Double
    public let mean: Double
    public let sampleStdDev: Double?

    public init?(_ values: [Double]) {
        let finite = values.filter(\.isFinite).sorted()
        guard !finite.isEmpty else { return nil }

        let computedMean = finite.reduce(0, +) / Double(finite.count)
        let computedSampleStdDev: Double?
        if finite.count > 1 {
            let squared = finite.reduce(0.0) { partial, value in
                let difference = value - computedMean
                return partial + difference * difference
            }
            computedSampleStdDev = (squared / Double(finite.count - 1)).squareRoot()
        } else {
            computedSampleStdDev = nil
        }

        count = finite.count
        minimum = finite[0]
        p10 = Self.quantile(finite, probability: 0.10)
        p25 = Self.quantile(finite, probability: 0.25)
        median = Self.quantile(finite, probability: 0.50)
        p75 = Self.quantile(finite, probability: 0.75)
        p90 = Self.quantile(finite, probability: 0.90)
        maximum = finite[finite.count - 1]
        mean = computedMean
        sampleStdDev = computedSampleStdDev
    }

    static func quantile(_ sorted: [Double], probability: Double) -> Double {
        precondition(!sorted.isEmpty)
        let p = min(1, max(0, probability))
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        guard lower != upper else { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}

public struct RROrderSignedDifferenceSummary: Equatable, Sendable, Codable {
    public let distribution: RROrderDistributionSummary?
    public let absoluteDistribution: RROrderDistributionSummary?
    public let positiveCount: Int
    public let negativeCount: Int
    public let zeroCount: Int

    public init(_ values: [Double], zeroTolerance: Double = 1e-9) {
        let finite = values.filter(\.isFinite)
        distribution = RROrderDistributionSummary(finite)
        absoluteDistribution = RROrderDistributionSummary(finite.map(abs))
        positiveCount = finite.filter { $0 > zeroTolerance }.count
        negativeCount = finite.filter { $0 < -zeroTolerance }.count
        zeroCount = finite.count - positiveCount - negativeCount
    }
}

/// Descriptive exceedance count only. These bins are not release, clinical, or score-withholding thresholds.
public struct RROrderExceedanceBin: Equatable, Sendable, Codable {
    public let threshold: Double
    public let count: Int
    public let fraction: Double?

    public init(threshold: Double, count: Int, denominator: Int) {
        self.threshold = threshold
        self.count = count
        self.fraction = denominator > 0 ? Double(count) / Double(denominator) : nil
    }
}

public struct RROrderTriStateCounts: Equatable, Sendable, Codable {
    public let trueCount: Int
    public let falseCount: Int
    public let unknownCount: Int

    public init(values: [Bool?]) {
        let trueCount = values.filter { $0 == true }.count
        let falseCount = values.filter { $0 == false }.count
        self.trueCount = trueCount
        self.falseCount = falseCount
        self.unknownCount = values.count - trueCount - falseCount
    }
}

public struct RROrderCorpusProvenanceSummary: Equatable, Sendable, Codable {
    public let totalIntervals: Int
    public let intervalsWithRecordedOrder: Int
    public let intervalsWithUnknownOrder: Int
    public let weightedRecordedOrderFraction: Double?

    public let singleBeatSeconds: Int
    public let multiBeatSeconds: Int
    public let multiBeatIntervals: Int
    public let trustworthyMultiBeatSeconds: Int
    public let trustworthyMultiBeatIntervals: Int
    public let weightedTrustworthyMultiBeatIntervalFraction: Double?

    public let allUnknownMultiBeatSeconds: Int
    public let allUnknownMultiBeatIntervals: Int
    public let mixedOrderMultiBeatSeconds: Int
    public let mixedOrderMultiBeatIntervals: Int
    public let ambiguousRecordedOrderMultiBeatSeconds: Int
    public let ambiguousRecordedOrderMultiBeatIntervals: Int
    public let magnitudeReorderedTrustworthySeconds: Int
    public let magnitudeReorderedTrustworthyIntervals: Int

    public let sessionsWithIntervals: Int
    public let sessionsWithMultiBeatIntervals: Int
    public let sessionsWithCompleteSameSecondOrder: Int
    public let sessionsWithLegacyUnknownGroups: Int
    public let sessionsWithMixedOrderGroups: Int
    public let sessionsWithAmbiguousRecordedOrderGroups: Int
    public let sessionsWhereMagnitudeChangedTrustworthyGroups: Int

    public let recordedOrderFractionBySession: RROrderDistributionSummary?
    public let trustworthyMultiBeatIntervalFractionBySession: RROrderDistributionSummary?

    init(records: [RROrderCorpusRecord]) {
        let provenance = records.map(\.audit.provenance)
        totalIntervals = provenance.reduce(0) { $0 + $1.totalIntervals }
        intervalsWithRecordedOrder = provenance.reduce(0) { $0 + $1.intervalsWithRecordedOrder }
        intervalsWithUnknownOrder = provenance.reduce(0) { $0 + $1.intervalsWithUnknownOrder }
        weightedRecordedOrderFraction = totalIntervals > 0
            ? Double(intervalsWithRecordedOrder) / Double(totalIntervals)
            : nil

        singleBeatSeconds = provenance.reduce(0) { $0 + $1.singleBeatSeconds }
        multiBeatSeconds = provenance.reduce(0) { $0 + $1.multiBeatSeconds }
        multiBeatIntervals = provenance.reduce(0) { $0 + $1.multiBeatIntervals }
        trustworthyMultiBeatSeconds = provenance.reduce(0) { $0 + $1.trustworthyMultiBeatSeconds }
        trustworthyMultiBeatIntervals = provenance.reduce(0) { $0 + $1.trustworthyMultiBeatIntervals }
        weightedTrustworthyMultiBeatIntervalFraction = multiBeatIntervals > 0
            ? Double(trustworthyMultiBeatIntervals) / Double(multiBeatIntervals)
            : nil

        allUnknownMultiBeatSeconds = provenance.reduce(0) { $0 + $1.allUnknownMultiBeatSeconds }
        allUnknownMultiBeatIntervals = provenance.reduce(0) { $0 + $1.allUnknownMultiBeatIntervals }
        mixedOrderMultiBeatSeconds = provenance.reduce(0) { $0 + $1.mixedOrderMultiBeatSeconds }
        mixedOrderMultiBeatIntervals = provenance.reduce(0) { $0 + $1.mixedOrderMultiBeatIntervals }
        ambiguousRecordedOrderMultiBeatSeconds = provenance.reduce(0) {
            $0 + $1.ambiguousRecordedOrderMultiBeatSeconds
        }
        ambiguousRecordedOrderMultiBeatIntervals = provenance.reduce(0) {
            $0 + $1.ambiguousRecordedOrderMultiBeatIntervals
        }
        magnitudeReorderedTrustworthySeconds = provenance.reduce(0) {
            $0 + $1.magnitudeReorderedTrustworthySeconds
        }
        magnitudeReorderedTrustworthyIntervals = provenance.reduce(0) {
            $0 + $1.magnitudeReorderedTrustworthyIntervals
        }

        sessionsWithIntervals = provenance.filter { $0.totalIntervals > 0 }.count
        sessionsWithMultiBeatIntervals = provenance.filter { $0.multiBeatIntervals > 0 }.count
        sessionsWithCompleteSameSecondOrder = provenance.filter(\.hasCompleteSameSecondOrder).count
        sessionsWithLegacyUnknownGroups = provenance.filter { $0.allUnknownMultiBeatSeconds > 0 }.count
        sessionsWithMixedOrderGroups = provenance.filter { $0.mixedOrderMultiBeatSeconds > 0 }.count
        sessionsWithAmbiguousRecordedOrderGroups = provenance.filter {
            $0.ambiguousRecordedOrderMultiBeatSeconds > 0
        }.count
        sessionsWhereMagnitudeChangedTrustworthyGroups = provenance.filter {
            $0.magnitudeReorderedTrustworthySeconds > 0
        }.count

        recordedOrderFractionBySession = RROrderDistributionSummary(
            provenance.filter { $0.totalIntervals > 0 }.compactMap(\.recordedOrderFraction)
        )
        trustworthyMultiBeatIntervalFractionBySession = RROrderDistributionSummary(
            provenance
                .filter { $0.multiBeatIntervals > 0 }
                .compactMap(\.trustworthyMultiBeatIntervalFraction)
        )
    }
}

public struct RROrderCorpusHRVSummary: Equatable, Sendable, Codable {
    public let currentProductionAvailableCount: Int
    public let magnitudeProductionAvailableCount: Int
    public let pairedProductionCount: Int
    public let currentProductionRmssdMs: RROrderDistributionSummary?
    public let magnitudeProductionRmssdMs: RROrderDistributionSummary?
    public let currentMinusMagnitudeMs: RROrderSignedDifferenceSummary
    public let currentMinusMagnitudePctOfCurrent: RROrderSignedDifferenceSummary
    public let absoluteDeltaMsExceedance: [RROrderExceedanceBin]
    public let absoluteDeltaPctExceedance: [RROrderExceedanceBin]
    public let currentCleanFraction: RROrderDistributionSummary?
    public let magnitudeCleanFraction: RROrderDistributionSummary?

    public let currentRawAvailableCount: Int
    public let magnitudeRawAvailableCount: Int
    public let pairedRawCount: Int
    public let currentRawRmssdMs: RROrderDistributionSummary?
    public let magnitudeRawRmssdMs: RROrderDistributionSummary?
    public let rawCurrentMinusMagnitudeMs: RROrderSignedDifferenceSummary
    public let rawCurrentMinusMagnitudePctOfCurrent: RROrderSignedDifferenceSummary

    public let cachedAvailableCount: Int
    public let pairedCurrentAndCachedCount: Int
    public let currentMinusCachedMs: RROrderSignedDifferenceSummary

    init(records: [RROrderCorpusRecord]) {
        let current = records.map(\.audit.currentOrder)
        let magnitude = records.map(\.audit.magnitudeOrderCounterfactual)

        let currentProduction = current.compactMap(\.rmssdMs)
        let magnitudeProduction = magnitude.compactMap(\.rmssdMs)
        currentProductionAvailableCount = currentProduction.count
        magnitudeProductionAvailableCount = magnitudeProduction.count
        currentProductionRmssdMs = RROrderDistributionSummary(currentProduction)
        magnitudeProductionRmssdMs = RROrderDistributionSummary(magnitudeProduction)

        var productionDeltaMs: [Double] = []
        var productionDeltaPct: [Double] = []
        var currentCleanFractions: [Double] = []
        var magnitudeCleanFractions: [Double] = []
        for record in records {
            let lhs = record.audit.currentOrder
            let rhs = record.audit.magnitudeOrderCounterfactual
            if lhs.nInput > 0 {
                currentCleanFractions.append(Double(lhs.nClean) / Double(lhs.nInput))
            }
            if rhs.nInput > 0 {
                magnitudeCleanFractions.append(Double(rhs.nClean) / Double(rhs.nInput))
            }
            if let currentRmssd = lhs.rmssdMs, let magnitudeRmssd = rhs.rmssdMs {
                let delta = currentRmssd - magnitudeRmssd
                productionDeltaMs.append(delta)
                if currentRmssd != 0 { productionDeltaPct.append(delta / currentRmssd * 100) }
            }
        }
        pairedProductionCount = productionDeltaMs.count
        currentMinusMagnitudeMs = RROrderSignedDifferenceSummary(productionDeltaMs)
        currentMinusMagnitudePctOfCurrent = RROrderSignedDifferenceSummary(productionDeltaPct)
        absoluteDeltaMsExceedance = Self.exceedanceBins(
            productionDeltaMs,
            thresholds: [1, 2, 5, 10, 20]
        )
        absoluteDeltaPctExceedance = Self.exceedanceBins(
            productionDeltaPct,
            thresholds: [1, 5, 10, 20, 50]
        )
        currentCleanFraction = RROrderDistributionSummary(currentCleanFractions)
        magnitudeCleanFraction = RROrderDistributionSummary(magnitudeCleanFractions)

        let currentRaw = current.compactMap(\.rawRmssdMs)
        let magnitudeRaw = magnitude.compactMap(\.rawRmssdMs)
        currentRawAvailableCount = currentRaw.count
        magnitudeRawAvailableCount = magnitudeRaw.count
        currentRawRmssdMs = RROrderDistributionSummary(currentRaw)
        magnitudeRawRmssdMs = RROrderDistributionSummary(magnitudeRaw)

        var rawDeltaMs: [Double] = []
        var rawDeltaPct: [Double] = []
        for record in records {
            guard let currentRmssd = record.audit.currentOrder.rawRmssdMs,
                  let magnitudeRmssd = record.audit.magnitudeOrderCounterfactual.rawRmssdMs else { continue }
            let delta = currentRmssd - magnitudeRmssd
            rawDeltaMs.append(delta)
            if currentRmssd != 0 { rawDeltaPct.append(delta / currentRmssd * 100) }
        }
        pairedRawCount = rawDeltaMs.count
        rawCurrentMinusMagnitudeMs = RROrderSignedDifferenceSummary(rawDeltaMs)
        rawCurrentMinusMagnitudePctOfCurrent = RROrderSignedDifferenceSummary(rawDeltaPct)

        cachedAvailableCount = records.compactMap(\.cachedAvgHrvMs).count
        var cachedDelta: [Double] = []
        for record in records {
            if let currentRmssd = record.audit.currentOrder.rmssdMs,
               let cached = record.cachedAvgHrvMs {
                cachedDelta.append(currentRmssd - cached)
            }
        }
        pairedCurrentAndCachedCount = cachedDelta.count
        currentMinusCachedMs = RROrderSignedDifferenceSummary(cachedDelta)
    }

    private static func exceedanceBins(
        _ values: [Double],
        thresholds: [Double]
    ) -> [RROrderExceedanceBin] {
        let absolute = values.filter(\.isFinite).map(abs)
        return thresholds.map { threshold in
            RROrderExceedanceBin(
                threshold: threshold,
                count: absolute.filter { $0 >= threshold }.count,
                denominator: absolute.count
            )
        }
    }
}

public struct RROrderCorpusDeviceSummary: Equatable, Sendable, Codable {
    public let deviceKey: String
    public let sessionCount: Int
    public let totalIntervals: Int
    public let sessionsWithCompleteSameSecondOrder: Int
    public let weightedRecordedOrderFraction: Double?
    public let weightedTrustworthyMultiBeatIntervalFraction: Double?
    public let pairedProductionCount: Int
    public let currentMinusMagnitudeMs: RROrderDistributionSummary?
    public let currentMinusMagnitudePctOfCurrent: RROrderDistributionSummary?

    init(deviceKey: String, records: [RROrderCorpusRecord]) {
        self.deviceKey = deviceKey
        sessionCount = records.count
        let provenance = RROrderCorpusProvenanceSummary(records: records)
        totalIntervals = provenance.totalIntervals
        sessionsWithCompleteSameSecondOrder = provenance.sessionsWithCompleteSameSecondOrder
        weightedRecordedOrderFraction = provenance.weightedRecordedOrderFraction
        weightedTrustworthyMultiBeatIntervalFraction = provenance.weightedTrustworthyMultiBeatIntervalFraction

        var deltaMs: [Double] = []
        var deltaPct: [Double] = []
        for record in records {
            guard let current = record.audit.currentOrder.rmssdMs,
                  let magnitude = record.audit.magnitudeOrderCounterfactual.rmssdMs else { continue }
            let delta = current - magnitude
            deltaMs.append(delta)
            if current != 0 { deltaPct.append(delta / current * 100) }
        }
        pairedProductionCount = deltaMs.count
        currentMinusMagnitudeMs = RROrderDistributionSummary(deltaMs)
        currentMinusMagnitudePctOfCurrent = RROrderDistributionSummary(deltaPct)
    }
}

/// Aggregate-only result. It intentionally contains no raw device ID and no per-session observation.
public struct RROrderCorpusSummary: Equatable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let inputRecordSchemaVersion: Int
    public let recordCount: Int
    public let deviceCount: Int
    public let earliestDetectedStartTs: Int?
    public let earliestDetectedStartUTC: String?
    public let latestEndTs: Int?
    public let latestEndUTC: String?
    public let durationSeconds: RROrderDistributionSummary?
    public let userEditedSessionCount: Int
    public let stagingSparse: RROrderTriStateCounts
    public let provenance: RROrderCorpusProvenanceSummary
    public let hrv: RROrderCorpusHRVSummary
    public let devices: [RROrderCorpusDeviceSummary]

    public static func summarize(_ records: [RROrderCorpusRecord]) throws -> RROrderCorpusSummary {
        try validate(records)
        let earliest = records.map(\.detectedStartTs).min()
        let latest = records.map(\.endTs).max()
        let grouped = Dictionary(grouping: records, by: \.deviceKey)
        let devices = grouped.keys.sorted().map { deviceKey in
            RROrderCorpusDeviceSummary(deviceKey: deviceKey, records: grouped[deviceKey] ?? [])
        }

        return RROrderCorpusSummary(
            schemaVersion: currentSchemaVersion,
            inputRecordSchemaVersion: RROrderCorpusRecord.currentSchemaVersion,
            recordCount: records.count,
            deviceCount: grouped.count,
            earliestDetectedStartTs: earliest,
            earliestDetectedStartUTC: earliest.map(utcString),
            latestEndTs: latest,
            latestEndUTC: latest.map(utcString),
            durationSeconds: RROrderDistributionSummary(records.map { Double($0.durationSeconds) }),
            userEditedSessionCount: records.filter(\.userEdited).count,
            stagingSparse: RROrderTriStateCounts(values: records.map(\.stagingSparse)),
            provenance: RROrderCorpusProvenanceSummary(records: records),
            hrv: RROrderCorpusHRVSummary(records: records),
            devices: devices
        )
    }

    public init(
        schemaVersion: Int,
        inputRecordSchemaVersion: Int,
        recordCount: Int,
        deviceCount: Int,
        earliestDetectedStartTs: Int?,
        earliestDetectedStartUTC: String?,
        latestEndTs: Int?,
        latestEndUTC: String?,
        durationSeconds: RROrderDistributionSummary?,
        userEditedSessionCount: Int,
        stagingSparse: RROrderTriStateCounts,
        provenance: RROrderCorpusProvenanceSummary,
        hrv: RROrderCorpusHRVSummary,
        devices: [RROrderCorpusDeviceSummary]
    ) {
        self.schemaVersion = schemaVersion
        self.inputRecordSchemaVersion = inputRecordSchemaVersion
        self.recordCount = recordCount
        self.deviceCount = deviceCount
        self.earliestDetectedStartTs = earliestDetectedStartTs
        self.earliestDetectedStartUTC = earliestDetectedStartUTC
        self.latestEndTs = latestEndTs
        self.latestEndUTC = latestEndUTC
        self.durationSeconds = durationSeconds
        self.userEditedSessionCount = userEditedSessionCount
        self.stagingSparse = stagingSparse
        self.provenance = provenance
        self.hrv = hrv
        self.devices = devices
    }

    private struct ObservationIdentity: Hashable {
        let deviceKey: String
        let detectedStartTs: Int
        let endTs: Int
    }

    private static func validate(_ records: [RROrderCorpusRecord]) throws {
        var identities = Set<ObservationIdentity>()
        for record in records {
            guard record.schemaVersion == RROrderCorpusRecord.currentSchemaVersion else {
                throw RROrderCorpusSummaryError.unsupportedRecordSchema(
                    line: nil,
                    version: record.schemaVersion
                )
            }
            let identity = ObservationIdentity(
                deviceKey: record.deviceKey,
                detectedStartTs: record.detectedStartTs,
                endTs: record.endTs
            )
            guard identities.insert(identity).inserted else {
                throw RROrderCorpusSummaryError.duplicateObservation(
                    deviceKey: identity.deviceKey,
                    detectedStartTs: identity.detectedStartTs,
                    endTs: identity.endTs
                )
            }
        }
    }

    private static func utcString(_ unixSeconds: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unixSeconds)))
    }
}

public enum RROrderCorpusSummaryInput {
    /// Decode one schema-v1 corpus record per nonblank line. Duplicate observations fail closed so a
    /// concatenated/replayed file cannot silently double-weight a night.
    public static func decodeJSONLines(_ data: Data) throws -> [RROrderCorpusRecord] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw RROrderCorpusSummaryError.invalidUTF8
        }

        let decoder = JSONDecoder()
        var records: [RROrderCorpusRecord] = []
        var identities = Set<String>()
        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let record: RROrderCorpusRecord
            do {
                record = try decoder.decode(RROrderCorpusRecord.self, from: Data(line.utf8))
            } catch {
                throw RROrderCorpusSummaryError.invalidJSONLine(
                    line: lineNumber,
                    message: String(describing: error)
                )
            }
            guard record.schemaVersion == RROrderCorpusRecord.currentSchemaVersion else {
                throw RROrderCorpusSummaryError.unsupportedRecordSchema(
                    line: lineNumber,
                    version: record.schemaVersion
                )
            }

            let identity = "\(record.deviceKey)\u{1F}\(record.detectedStartTs)\u{1F}\(record.endTs)"
            guard identities.insert(identity).inserted else {
                throw RROrderCorpusSummaryError.duplicateObservation(
                    deviceKey: record.deviceKey,
                    detectedStartTs: record.detectedStartTs,
                    endTs: record.endTs
                )
            }
            records.append(record)
        }
        return records
    }
}

public enum RROrderCorpusSummaryEncoder {
    public static func encode(
        _ summary: RROrderCorpusSummary,
        format: RROrderCorpusSummaryFormat
    ) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(summary)
            data.append(0x0A)
            return data
        case .markdown:
            return Data(markdown(summary).utf8)
        }
    }

    public static func markdown(_ summary: RROrderCorpusSummary) -> String {
        var lines: [String] = []
        lines.append("# R-R order corpus summary")
        lines.append("")
        lines.append("## Scope")
        lines.append("")
        lines.append("- Sessions: \(summary.recordCount)")
        lines.append("- Pseudonymous devices: \(summary.deviceCount)")
        lines.append("- Detected range: \(summary.earliestDetectedStartUTC ?? "n/a") to \(summary.latestEndUTC ?? "n/a")")
        lines.append("- Session duration: \(distribution(summary.durationSeconds, unit: "s"))")
        lines.append("- User-edited sessions: \(summary.userEditedSessionCount)/\(summary.recordCount)")
        lines.append("- Staging sparse: true \(summary.stagingSparse.trueCount), false \(summary.stagingSparse.falseCount), unknown \(summary.stagingSparse.unknownCount)")
        lines.append("")
        lines.append("## Order provenance")
        lines.append("")
        lines.append("- R-R intervals: \(summary.provenance.totalIntervals)")
        lines.append("- Recorded order, interval weighted: \(percent(summary.provenance.weightedRecordedOrderFraction))")
        lines.append("- Trustworthy order among multi-beat intervals, interval weighted: \(percent(summary.provenance.weightedTrustworthyMultiBeatIntervalFraction))")
        lines.append("- Sessions with complete same-second order: \(summary.provenance.sessionsWithCompleteSameSecondOrder)/\(summary.recordCount)")
        lines.append("- Sessions containing legacy-unknown groups: \(summary.provenance.sessionsWithLegacyUnknownGroups)")
        lines.append("- Sessions containing mixed groups: \(summary.provenance.sessionsWithMixedOrderGroups)")
        lines.append("- Sessions containing duplicate-order ambiguity: \(summary.provenance.sessionsWithAmbiguousRecordedOrderGroups)")
        lines.append("- Trustworthy groups changed by magnitude sorting: \(summary.provenance.magnitudeReorderedTrustworthySeconds)/\(summary.provenance.trustworthyMultiBeatSeconds) seconds")
        lines.append("")
        lines.append("## Production-gated RMSSD comparison")
        lines.append("")
        lines.append("- Current RMSSD available: \(summary.hrv.currentProductionAvailableCount)/\(summary.recordCount)")
        lines.append("- Magnitude counterfactual available: \(summary.hrv.magnitudeProductionAvailableCount)/\(summary.recordCount)")
        lines.append("- Paired comparisons: \(summary.hrv.pairedProductionCount)")
        lines.append("- Current RMSSD: \(distribution(summary.hrv.currentProductionRmssdMs, unit: "ms"))")
        lines.append("- Magnitude-order RMSSD: \(distribution(summary.hrv.magnitudeProductionRmssdMs, unit: "ms"))")
        lines.append("- Current minus magnitude, ms: \(signedDistribution(summary.hrv.currentMinusMagnitudeMs, unit: "ms"))")
        lines.append("- Current minus magnitude, percent of current: \(signedDistribution(summary.hrv.currentMinusMagnitudePctOfCurrent, unit: "%"))")
        lines.append("- Direction: positive \(summary.hrv.currentMinusMagnitudeMs.positiveCount), zero \(summary.hrv.currentMinusMagnitudeMs.zeroCount), negative \(summary.hrv.currentMinusMagnitudeMs.negativeCount)")
        lines.append("- Descriptive absolute-delta bins, ms: \(bins(summary.hrv.absoluteDeltaMsExceedance, unit: "ms"))")
        lines.append("- Descriptive absolute-delta bins, percent: \(bins(summary.hrv.absoluteDeltaPctExceedance, unit: "%"))")
        lines.append("- Current clean fraction: \(percentDistribution(summary.hrv.currentCleanFraction))")
        lines.append("- Magnitude clean fraction: \(percentDistribution(summary.hrv.magnitudeCleanFraction))")
        lines.append("")
        lines.append("## Raw diagnostic RMSSD")
        lines.append("")
        lines.append("- Paired raw comparisons: \(summary.hrv.pairedRawCount)")
        lines.append("- Current raw RMSSD: \(distribution(summary.hrv.currentRawRmssdMs, unit: "ms"))")
        lines.append("- Magnitude raw RMSSD: \(distribution(summary.hrv.magnitudeRawRmssdMs, unit: "ms"))")
        lines.append("- Current minus magnitude, raw ms: \(signedDistribution(summary.hrv.rawCurrentMinusMagnitudeMs, unit: "ms"))")
        lines.append("- Current minus magnitude, raw percent: \(signedDistribution(summary.hrv.rawCurrentMinusMagnitudePctOfCurrent, unit: "%"))")
        lines.append("")
        lines.append("## Cached-value context")
        lines.append("")
        lines.append("- Cached nightly HRV available: \(summary.hrv.cachedAvailableCount)/\(summary.recordCount)")
        lines.append("- Paired current and cached: \(summary.hrv.pairedCurrentAndCachedCount)")
        lines.append("- Current minus cached RMSSD: \(signedDistribution(summary.hrv.currentMinusCachedMs, unit: "ms"))")
        lines.append("")
        lines.append("## Per-device summary")
        lines.append("")
        lines.append("| Device | Sessions | Intervals | Complete order | Paired RMSSD | Recorded order | Trustworthy multi-beat | Median delta ms | Median delta % |")
        lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for device in summary.devices {
            lines.append(
                "| \(device.deviceKey) | \(device.sessionCount) | \(device.totalIntervals) | "
                    + "\(device.sessionsWithCompleteSameSecondOrder) | \(device.pairedProductionCount) | "
                    + "\(percent(device.weightedRecordedOrderFraction)) | "
                    + "\(percent(device.weightedTrustworthyMultiBeatIntervalFraction)) | "
                    + "\(number(device.currentMinusMagnitudeMs?.median)) | "
                    + "\(number(device.currentMinusMagnitudePctOfCurrent?.median)) |"
            )
        }
        if summary.devices.isEmpty {
            lines.append("| n/a | 0 | 0 | 0 | 0 | n/a | n/a | n/a | n/a |")
        }
        lines.append("")
        lines.append("## Interpretation limits")
        lines.append("")
        lines.append("- The magnitude-order result is an offline counterfactual over the same stored row population, not a claim about every historical release path.")
        lines.append("- Descriptive exceedance bins are reporting aids, not clinical, release, or score-withholding thresholds.")
        lines.append("- This report contains aggregate statistics only. It does not include raw device IDs, R-R rows, or per-session observations.")
        lines.append("- Effect size should be interpreted alongside device count, paired-session count, order provenance, and downstream Charge/Readiness sensitivity.")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func distribution(_ value: RROrderDistributionSummary?, unit: String) -> String {
        guard let value else { return "n/a" }
        let suffix = unit.isEmpty ? "" : " \(unit)"
        return "n=\(value.count), mean \(number(value.mean))\(suffix), median \(number(value.median))\(suffix), p10-p90 \(number(value.p10))-\(number(value.p90))\(suffix), min-max \(number(value.minimum))-\(number(value.maximum))\(suffix)"
    }

    private static func signedDistribution(_ value: RROrderSignedDifferenceSummary, unit: String) -> String {
        guard let values = value.distribution else { return "n/a" }
        return distribution(values, unit: unit)
    }

    private static func percentDistribution(_ value: RROrderDistributionSummary?) -> String {
        guard let value else { return "n/a" }
        return "n=\(value.count), mean \(percent(value.mean)), median \(percent(value.median)), p10-p90 \(percent(value.p10))-\(percent(value.p90)), min-max \(percent(value.minimum))-\(percent(value.maximum))"
    }

    private static func bins(_ bins: [RROrderExceedanceBin], unit: String) -> String {
        guard !bins.isEmpty else { return "n/a" }
        return bins.map { bin in
            ">= \(number(bin.threshold)) \(unit): \(bin.count) (\(percent(bin.fraction)))"
        }.joined(separator: "; ")
    }

    private static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "n/a" }
        return String(format: "%.1f%%", locale: Locale(identifier: "en_US_POSIX"), value * 100)
    }

    private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "n/a" }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
