import Foundation
import StrandAnalytics

public enum RROrderCorpusSummaryFormat: String, CaseIterable, Sendable {
    case json
    case markdown
}

public enum RROrderCorpusSummaryError: Error, Equatable, CustomStringConvertible {
    case invalidUTF8
    case invalidJSONLine(line: Int, message: String)
    case unsupportedRecordSchema(line: Int?, version: Int)
    case unsupportedAuditSchema(line: Int?, version: Int)
    case duplicateObservation(String)

    public var description: String {
        switch self {
        case .invalidUTF8: return "Corpus input is not valid UTF-8."
        case .invalidJSONLine(let line, let message): return "Invalid corpus JSON on line \(line): \(message)"
        case .unsupportedRecordSchema(let line, let version):
            return "Unsupported corpus schemaVersion \(version)" + (line.map { " on line \($0)" } ?? "") + "."
        case .unsupportedAuditSchema(let line, let version):
            return "Unsupported audit schemaVersion \(version)" + (line.map { " on line \($0)" } ?? "") + "."
        case .duplicateObservation(let key): return "Duplicate corpus observation: \(key)."
        }
    }
}

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
        let m = finite.reduce(0, +) / Double(finite.count)
        count = finite.count
        minimum = finite[0]
        p10 = Self.quantile(finite, 0.10)
        p25 = Self.quantile(finite, 0.25)
        median = Self.quantile(finite, 0.50)
        p75 = Self.quantile(finite, 0.75)
        p90 = Self.quantile(finite, 0.90)
        maximum = finite[finite.count - 1]
        mean = m
        if finite.count > 1 {
            sampleStdDev = (finite.reduce(0.0) { $0 + ($1 - m) * ($1 - m) } / Double(finite.count - 1)).squareRoot()
        } else {
            sampleStdDev = nil
        }
    }

    static func quantile(_ sorted: [Double], _ p: Double) -> Double {
        precondition(!sorted.isEmpty)
        let position = min(1, max(0, p)) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down)), upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
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

    init(_ values: [Double], zeroTolerance: Double = 1e-9) {
        let finite = values.filter(\.isFinite)
        distribution = RROrderDistributionSummary(finite)
        absoluteDistribution = RROrderDistributionSummary(finite.map(abs))
        positiveCount = finite.filter { $0 > zeroTolerance }.count
        negativeCount = finite.filter { $0 < -zeroTolerance }.count
        zeroCount = finite.count - positiveCount - negativeCount
    }
}

public struct RROrderBootstrapInterval: Equatable, Sendable, Codable {
    public let lower: Double
    public let upper: Double
}

public struct RROrderBootstrapSummary: Equatable, Sendable, Codable {
    public let iterations: Int
    public let mean95: RROrderBootstrapInterval?
    public let median95: RROrderBootstrapInterval?
}

public struct RROrderAssociationSummary: Equatable, Sendable, Codable {
    public let trustworthyCoveragePairCount: Int
    public let trustworthyCoverageVsAbsoluteRmssdDeltaSpearman: Double?
    public let inversionPairCount: Int
    public let inversionFractionVsAbsoluteRmssdDeltaSpearman: Double?
}

public struct RROrderMetricEffectSummary: Equatable, Sendable, Codable {
    public let current: RROrderDistributionSummary?
    public let counterfactual: RROrderDistributionSummary?
    public let delta: RROrderSignedDifferenceSummary
}

public struct RROrderCleaningSummary: Equatable, Sendable, Codable {
    public let currentActualCleanCount: RROrderDistributionSummary?
    public let currentRejectedFraction: RROrderDistributionSummary?
    public let currentContiguousPairs: RROrderDistributionSummary?
    public let counterfactualActualCleanCount: RROrderDistributionSummary?
    public let counterfactualRejectedFraction: RROrderDistributionSummary?
    public let counterfactualContiguousPairs: RROrderDistributionSummary?
    public let sessionsWhereCleaningCountChanged: Int
    public let sessionsBelowCurrentProductionGate: Int
    public let sessionsBelowCounterfactualProductionGate: Int
}

public struct RROrderPermutationSummary: Equatable, Sendable, Codable {
    public let trustworthyGroups: Int
    public let reorderedGroups: Int
    public let reorderedGroupFraction: Double?
    public let valueInversions: Int
    public let possibleValueInversions: Int
    public let normalizedInversionFraction: Double?
    public let inversionFractionBySession: RROrderDistributionSummary?
    public let maxGroupSize: Int
    public let maxInversionsInOneGroup: Int
}

public struct RROrderInputFilterSummary: Equatable, Sendable, Codable {
    public let totalRows: Int
    public let scoringRows: Int
    public let excludedRows: Int
    public let spo2IbiRows: Int
    public let suspectTimestampRows: Int
    public let scoringFraction: Double?
}

public struct RROrderStratumSummary: Equatable, Sendable, Codable {
    public let name: String
    public let sessionCount: Int
    public let pairedRmssdCount: Int
    public let rmssdDeltaMs: RROrderSignedDifferenceSummary
    public let trustworthyCoverage: RROrderDistributionSummary?
    public let inversionFraction: RROrderDistributionSummary?

    init(name: String, records: [RROrderCorpusRecord]) {
        self.name = name
        sessionCount = records.count
        rmssdDeltaMs = RROrderSignedDifferenceSummary(records.compactMap(\.audit.rmssdCurrentMinusMagnitudeMs))
        pairedRmssdCount = rmssdDeltaMs.distribution?.count ?? 0
        trustworthyCoverage = RROrderDistributionSummary(records.compactMap { $0.audit.provenance.trustworthyMultiBeatIntervalFraction })
        inversionFraction = RROrderDistributionSummary(records.compactMap { $0.audit.permutationImpact.normalizedValueInversionFraction })
    }
}

public enum RROrderReadinessHrvFlag: String, Equatable, Sendable, Codable {
    case good, neutral, watch, bad
}

public struct RROrderReadinessHrvSensitivity: Equatable, Sendable, Codable {
    public let evaluatedNights: Int
    public let changedFlagNights: Int
    public let transitionCounts: [String: Int]
    public let currentZ: RROrderDistributionSummary?
    public let counterfactualZ: RROrderDistributionSummary?
    public let zDelta: RROrderSignedDifferenceSummary
}

public struct RROrderChargeHrvSensitivity: Equatable, Sendable, Codable {
    public let evaluatedNights: Int
    public let hrvZDelta: RROrderSignedDifferenceSummary
    public let fullDriverSetScoreDelta: RROrderSignedDifferenceSummary
    public let hrvOnlyScoreDelta: RROrderSignedDifferenceSummary
    public let minimumHrvWeightShare: Double
    public let maximumHrvWeightShare: Double
}

public struct RROrderDownstreamSensitivity: Equatable, Sendable, Codable {
    public let readinessHrv: RROrderReadinessHrvSensitivity
    public let chargeHrv: RROrderChargeHrvSensitivity
}

public struct RROrderDeviceSummary: Equatable, Sendable, Codable {
    public let deviceKey: String
    public let sessionCount: Int
    public let integrityCounts: [String: Int]
    public let totalIntervals: Int
    public let pairedRmssdCount: Int
    public let rmssdDeltaMs: RROrderSignedDifferenceSummary
    public let trustworthyCoverage: Double?
}

public struct RROrderCorpusSummary: Equatable, Sendable, Codable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let inputRecordSchemaVersion: Int
    public let auditSchemaVersion: Int
    public let recordCount: Int
    public let deviceCount: Int
    public let earliestDetectedStartUTC: String?
    public let latestEndUTC: String?
    public let durationSeconds: RROrderDistributionSummary?
    public let userEditedSessionCount: Int
    public let stagingSparseCounts: [String: Int]
    public let integrityCounts: [String: Int]
    public let flagCounts: [String: Int]
    public let rawInvariantFailures: Int
    public let inputFilters: RROrderInputFilterSummary
    public let permutation: RROrderPermutationSummary
    public let rmssd: RROrderMetricEffectSummary
    public let sdnn: RROrderMetricEffectSummary
    public let meanNN: RROrderMetricEffectSummary
    public let pnn50PercentagePoints: RROrderMetricEffectSummary
    public let rawRmssd: RROrderMetricEffectSummary
    public let rawPnn50PercentagePoints: RROrderMetricEffectSummary
    public let cleaning: RROrderCleaningSummary
    public let rmssdDeltaBootstrap95: RROrderBootstrapSummary
    public let associations: RROrderAssociationSummary
    public let downstreamSensitivity: RROrderDownstreamSensitivity
    public let integrityStrata: [RROrderStratumSummary]
    public let coverageStrata: [RROrderStratumSummary]
    public let durationStrata: [RROrderStratumSummary]
    public let stagingStrata: [RROrderStratumSummary]
    public let devices: [RROrderDeviceSummary]

    public static func summarize(_ records: [RROrderCorpusRecord], bootstrapIterations: Int = 2_000) throws -> Self {
        try validate(records)
        let grouped = Dictionary(grouping: records, by: \.deviceKey)
        let rmssdDelta = records.compactMap(\.audit.rmssdCurrentMinusMagnitudeMs)

        return Self(
            schemaVersion: currentSchemaVersion,
            inputRecordSchemaVersion: RROrderCorpusRecord.currentSchemaVersion,
            auditSchemaVersion: RROrderAuditReport.currentSchemaVersion,
            recordCount: records.count,
            deviceCount: grouped.count,
            earliestDetectedStartUTC: records.min(by: { $0.detectedStartTs < $1.detectedStartTs })?.detectedStartUTC,
            latestEndUTC: records.max(by: { $0.endTs < $1.endTs })?.endUTC,
            durationSeconds: RROrderDistributionSummary(records.map { Double($0.durationSeconds) }),
            userEditedSessionCount: records.filter(\.userEdited).count,
            stagingSparseCounts: triStateCounts(records.map(\.stagingSparse)),
            integrityCounts: countBy(records.map { $0.audit.integrityStatus.rawValue }),
            flagCounts: countBy(records.flatMap { $0.audit.flags.map(\.rawValue) }),
            rawInvariantFailures: records.filter { !$0.audit.rawOrderInvariantPreserved }.count,
            inputFilters: inputFilterSummary(records),
            permutation: permutationSummary(records),
            rmssd: metricSummary(records, current: { $0.audit.currentOrder.rmssdMs }, counterfactual: { $0.audit.magnitudeOrderCounterfactual.rmssdMs }, delta: { $0.audit.rmssdCurrentMinusMagnitudeMs }),
            sdnn: metricSummary(records, current: { $0.audit.currentOrder.sdnnMs }, counterfactual: { $0.audit.magnitudeOrderCounterfactual.sdnnMs }, delta: { $0.audit.sdnnCurrentMinusMagnitudeMs }),
            meanNN: metricSummary(records, current: { $0.audit.currentOrder.meanNNMs }, counterfactual: { $0.audit.magnitudeOrderCounterfactual.meanNNMs }, delta: { $0.audit.meanNNCurrentMinusMagnitudeMs }),
            pnn50PercentagePoints: metricSummary(records, current: { $0.audit.currentOrder.pnn50Pct }, counterfactual: { $0.audit.magnitudeOrderCounterfactual.pnn50Pct }, delta: { $0.audit.pnn50CurrentMinusMagnitudePercentagePoints }),
            rawRmssd: metricSummary(records, current: { $0.audit.currentOrder.rawRmssdMs }, counterfactual: { $0.audit.magnitudeOrderCounterfactual.rawRmssdMs }, delta: { $0.audit.rawRmssdCurrentMinusMagnitudeMs }),
            rawPnn50PercentagePoints: metricSummary(records, current: { $0.audit.currentOrder.rawPnn50Pct }, counterfactual: { $0.audit.magnitudeOrderCounterfactual.rawPnn50Pct }, delta: { $0.audit.rawPnn50CurrentMinusMagnitudePercentagePoints }),
            cleaning: cleaningSummary(records),
            rmssdDeltaBootstrap95: bootstrapSummary(rmssdDelta, iterations: bootstrapIterations, seed: 0x4E4F4F505252823),
            associations: associationSummary(records),
            downstreamSensitivity: downstreamSensitivity(records),
            integrityStrata: strata(records, key: { "integrity:\($0.audit.integrityStatus.rawValue)" }),
            coverageStrata: strata(records, key: coverageBucket),
            durationStrata: strata(records, key: durationBucket),
            stagingStrata: strata(records, key: stagingBucket),
            devices: grouped.keys.sorted().map { key in deviceSummary(key, grouped[key] ?? []) }
        )
    }

    private static func validate(_ records: [RROrderCorpusRecord]) throws {
        var seen = Set<String>()
        for record in records {
            guard record.schemaVersion == RROrderCorpusRecord.currentSchemaVersion else {
                throw RROrderCorpusSummaryError.unsupportedRecordSchema(line: nil, version: record.schemaVersion)
            }
            guard record.auditSchemaVersion == RROrderAuditReport.currentSchemaVersion,
                  record.audit.schemaVersion == RROrderAuditReport.currentSchemaVersion else {
                throw RROrderCorpusSummaryError.unsupportedAuditSchema(line: nil, version: record.auditSchemaVersion)
            }
            guard seen.insert(record.observationKey).inserted else {
                throw RROrderCorpusSummaryError.duplicateObservation(record.observationKey)
            }
        }
    }
}

private extension RROrderCorpusSummary {
    static func metricSummary(_ records: [RROrderCorpusRecord],
                              current: (RROrderCorpusRecord) -> Double?,
                              counterfactual: (RROrderCorpusRecord) -> Double?,
                              delta: (RROrderCorpusRecord) -> Double?) -> RROrderMetricEffectSummary {
        RROrderMetricEffectSummary(
            current: RROrderDistributionSummary(records.compactMap(current)),
            counterfactual: RROrderDistributionSummary(records.compactMap(counterfactual)),
            delta: RROrderSignedDifferenceSummary(records.compactMap(delta))
        )
    }

    static func inputFilterSummary(_ records: [RROrderCorpusRecord]) -> RROrderInputFilterSummary {
        let total = records.reduce(0) { $0 + $1.inputCounts.totalRowsInWindow }
        let scoring = records.reduce(0) { $0 + $1.inputCounts.scoringRows }
        return RROrderInputFilterSummary(
            totalRows: total,
            scoringRows: scoring,
            excludedRows: records.reduce(0) { $0 + $1.inputCounts.excludedRows },
            spo2IbiRows: records.reduce(0) { $0 + $1.inputCounts.spo2IbiRows },
            suspectTimestampRows: records.reduce(0) { $0 + $1.inputCounts.suspectTimestampRows },
            scoringFraction: total > 0 ? Double(scoring) / Double(total) : nil
        )
    }

    static func permutationSummary(_ records: [RROrderCorpusRecord]) -> RROrderPermutationSummary {
        let trustworthy = records.reduce(0) { $0 + $1.audit.permutationImpact.trustworthyGroupsCompared }
        let reordered = records.reduce(0) { $0 + $1.audit.permutationImpact.reorderedGroups }
        let inversions = records.reduce(0) { $0 + $1.audit.permutationImpact.valueInversions }
        let possible = records.reduce(0) { $0 + $1.audit.permutationImpact.possibleValueInversions }
        return RROrderPermutationSummary(
            trustworthyGroups: trustworthy,
            reorderedGroups: reordered,
            reorderedGroupFraction: trustworthy > 0 ? Double(reordered) / Double(trustworthy) : nil,
            valueInversions: inversions,
            possibleValueInversions: possible,
            normalizedInversionFraction: possible > 0 ? Double(inversions) / Double(possible) : nil,
            inversionFractionBySession: RROrderDistributionSummary(records.compactMap { $0.audit.permutationImpact.normalizedValueInversionFraction }),
            maxGroupSize: records.map { $0.audit.permutationImpact.maxTrustworthyGroupSize }.max() ?? 0,
            maxInversionsInOneGroup: records.map { $0.audit.permutationImpact.maxValueInversionsInGroup }.max() ?? 0
        )
    }

    static func cleaningSummary(_ records: [RROrderCorpusRecord]) -> RROrderCleaningSummary {
        RROrderCleaningSummary(
            currentActualCleanCount: RROrderDistributionSummary(records.map { Double($0.audit.currentOrder.actualCleanCount) }),
            currentRejectedFraction: RROrderDistributionSummary(records.compactMap { $0.audit.currentOrder.rejectedFraction }),
            currentContiguousPairs: RROrderDistributionSummary(records.map { Double($0.audit.currentOrder.contiguousPairCount) }),
            counterfactualActualCleanCount: RROrderDistributionSummary(records.map { Double($0.audit.magnitudeOrderCounterfactual.actualCleanCount) }),
            counterfactualRejectedFraction: RROrderDistributionSummary(records.compactMap { $0.audit.magnitudeOrderCounterfactual.rejectedFraction }),
            counterfactualContiguousPairs: RROrderDistributionSummary(records.map { Double($0.audit.magnitudeOrderCounterfactual.contiguousPairCount) }),
            sessionsWhereCleaningCountChanged: records.filter { $0.audit.flags.contains(.counterfactualChangesCleaningOutcome) }.count,
            sessionsBelowCurrentProductionGate: records.filter { !$0.audit.currentOrder.meetsProductionBeatGate }.count,
            sessionsBelowCounterfactualProductionGate: records.filter { !$0.audit.magnitudeOrderCounterfactual.meetsProductionBeatGate }.count
        )
    }

    static func countBy(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    static func triStateCounts(_ values: [Bool?]) -> [String: Int] {
        ["true": values.filter { $0 == true }.count,
         "false": values.filter { $0 == false }.count,
         "unknown": values.filter { $0 == nil }.count]
    }

    static func strata(_ records: [RROrderCorpusRecord], key: (RROrderCorpusRecord) -> String) -> [RROrderStratumSummary] {
        let grouped = Dictionary(grouping: records, by: key)
        return grouped.keys.sorted().map { RROrderStratumSummary(name: $0, records: grouped[$0] ?? []) }
    }

    static func coverageBucket(_ record: RROrderCorpusRecord) -> String {
        let p = record.audit.provenance
        guard p.multiBeatIntervals > 0 else { return "coverage:no-multi-beat" }
        let fraction = p.trustworthyMultiBeatIntervalFraction ?? 0
        if fraction >= 0.999_999 { return "coverage:complete" }
        if fraction >= 0.90 { return "coverage:high-90-99" }
        if fraction >= 0.50 { return "coverage:medium-50-89" }
        return "coverage:low-below-50"
    }

    static func durationBucket(_ record: RROrderCorpusRecord) -> String {
        let hours = Double(record.durationSeconds) / 3600.0
        if hours < 4 { return "duration:<4h" }
        if hours < 6 { return "duration:4-6h" }
        if hours < 8 { return "duration:6-8h" }
        return "duration:8h+"
    }

    static func stagingBucket(_ record: RROrderCorpusRecord) -> String {
        switch record.stagingSparse {
        case .some(true): return "staging:sparse"
        case .some(false): return "staging:dense"
        case .none: return "staging:unknown"
        }
    }

    static func deviceSummary(_ key: String, _ records: [RROrderCorpusRecord]) -> RROrderDeviceSummary {
        let total = records.reduce(0) { $0 + $1.audit.provenance.totalIntervals }
        let multi = records.reduce(0) { $0 + $1.audit.provenance.multiBeatIntervals }
        let trustworthy = records.reduce(0) { $0 + $1.audit.provenance.trustworthyMultiBeatIntervals }
        let delta = RROrderSignedDifferenceSummary(records.compactMap(\.audit.rmssdCurrentMinusMagnitudeMs))
        return RROrderDeviceSummary(
            deviceKey: key,
            sessionCount: records.count,
            integrityCounts: countBy(records.map { $0.audit.integrityStatus.rawValue }),
            totalIntervals: total,
            pairedRmssdCount: delta.distribution?.count ?? 0,
            rmssdDeltaMs: delta,
            trustworthyCoverage: multi > 0 ? Double(trustworthy) / Double(multi) : nil
        )
    }
}

private extension RROrderCorpusSummary {
    struct LCG {
        var state: UInt64
        mutating func nextIndex(upperBound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 1) % UInt64(upperBound))
        }
    }

    static func bootstrapSummary(_ values: [Double], iterations: Int, seed: UInt64) -> RROrderBootstrapSummary {
        let finite = values.filter(\.isFinite)
        guard finite.count >= 2, iterations > 0 else {
            return RROrderBootstrapSummary(iterations: max(0, iterations), mean95: nil, median95: nil)
        }
        var rng = LCG(state: seed)
        var means: [Double] = [], medians: [Double] = []
        means.reserveCapacity(iterations); medians.reserveCapacity(iterations)
        for _ in 0..<iterations {
            var sample: [Double] = []
            sample.reserveCapacity(finite.count)
            for _ in 0..<finite.count { sample.append(finite[rng.nextIndex(upperBound: finite.count)]) }
            sample.sort()
            means.append(sample.reduce(0, +) / Double(sample.count))
            medians.append(RROrderDistributionSummary.quantile(sample, 0.5))
        }
        means.sort(); medians.sort()
        return RROrderBootstrapSummary(
            iterations: iterations,
            mean95: RROrderBootstrapInterval(lower: RROrderDistributionSummary.quantile(means, 0.025), upper: RROrderDistributionSummary.quantile(means, 0.975)),
            median95: RROrderBootstrapInterval(lower: RROrderDistributionSummary.quantile(medians, 0.025), upper: RROrderDistributionSummary.quantile(medians, 0.975))
        )
    }

    static func associationSummary(_ records: [RROrderCorpusRecord]) -> RROrderAssociationSummary {
        var coverageX: [Double] = [], coverageY: [Double] = []
        var inversionX: [Double] = [], inversionY: [Double] = []
        for record in records {
            guard let delta = record.audit.rmssdCurrentMinusMagnitudeMs else { continue }
            let y = abs(delta)
            if let x = record.audit.provenance.trustworthyMultiBeatIntervalFraction {
                coverageX.append(x); coverageY.append(y)
            }
            if let x = record.audit.permutationImpact.normalizedValueInversionFraction {
                inversionX.append(x); inversionY.append(y)
            }
        }
        return RROrderAssociationSummary(
            trustworthyCoveragePairCount: coverageX.count,
            trustworthyCoverageVsAbsoluteRmssdDeltaSpearman: spearman(coverageX, coverageY),
            inversionPairCount: inversionX.count,
            inversionFractionVsAbsoluteRmssdDeltaSpearman: spearman(inversionX, inversionY)
        )
    }

    static func spearman(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 3 else { return nil }
        return pearson(ranks(x), ranks(y))
    }

    static func ranks(_ values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var result = Array(repeating: 0.0, count: values.count)
        var i = 0
        while i < order.count {
            var j = i + 1
            while j < order.count && values[order[j]] == values[order[i]] { j += 1 }
            let rank = (Double(i + 1) + Double(j)) / 2.0
            for k in i..<j { result[order[k]] = rank }
            i = j
        }
        return result
    }

    static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let mx = x.reduce(0, +) / Double(x.count), my = y.reduce(0, +) / Double(y.count)
        var numerator = 0.0, dx2 = 0.0, dy2 = 0.0
        for i in x.indices {
            let dx = x[i] - mx, dy = y[i] - my
            numerator += dx * dy; dx2 += dx * dx; dy2 += dy * dy
        }
        guard dx2 > 0, dy2 > 0 else { return nil }
        return numerator / (dx2 * dy2).squareRoot()
    }
}

private extension RROrderCorpusSummary {
    static func downstreamSensitivity(_ records: [RROrderCorpusRecord]) -> RROrderDownstreamSensitivity {
        var readinessCurrentZ: [Double] = [], readinessMagnitudeZ: [Double] = [], readinessDeltaZ: [Double] = []
        var transitions: [String: Int] = [:]
        var changedFlags = 0
        var chargeZDelta: [Double] = [], fullDriverDelta: [Double] = [], hrvOnlyDelta: [Double] = []

        let fullWeight = RecoveryScorer.wHRV + RecoveryScorer.wRHR + RecoveryScorer.wResp
            + RecoveryScorer.wSleep + RecoveryScorer.wSkinTemp + RecoveryScorer.wRecoveryIndex
            + RecoveryScorer.wActivityBalance
        let minShare = RecoveryScorer.wHRV / fullWeight
        let maxShare = 1.0

        for (_, deviceRecords) in Dictionary(grouping: records, by: \.deviceKey) {
            let sorted = deviceRecords.sorted { $0.detectedStartTs < $1.detectedStartTs }
            var priorCurrentRmssd: [Double] = []
            for record in sorted {
                let current = record.audit.currentOrder.rmssdMs
                let magnitude = record.audit.magnitudeOrderCounterfactual.rmssdMs
                if let current, let magnitude {
                    let trailing = Array(priorCurrentRmssd.suffix(30))
                    if trailing.count >= 7 {
                        let logs = trailing.map { log(max($0, 1.0)) }
                        let state = Baselines.foldHistory(logs.map { Optional($0) }, cfg: Baselines.readinessHRVLnCfg, rejectHardOutliers: false)
                        if state.usable {
                            let sigma = max(1.253 * state.spread, 1e-9)
                            let cz = (log(max(current, 1.0)) - state.baseline) / sigma
                            let mz = (log(max(magnitude, 1.0)) - state.baseline) / sigma
                            readinessCurrentZ.append(cz); readinessMagnitudeZ.append(mz); readinessDeltaZ.append(cz - mz)
                            let cf = readinessFlag(cz), mf = readinessFlag(mz)
                            transitions["\(cf.rawValue)->\(mf.rawValue)", default: 0] += 1
                            if cf != mf { changedFlags += 1 }
                        }

                        let rawState = Baselines.foldHistory(trailing.map { Optional($0) }, cfg: Baselines.hrvCfg)
                        if rawState.usable {
                            let sigma = max(1.253 * rawState.spread, 1e-9)
                            let cz = (current - rawState.baseline) / sigma
                            let mz = (magnitude - rawState.baseline) / sigma
                            chargeZDelta.append(cz - mz)
                            fullDriverDelta.append(chargeScore(hrvZ: cz, share: minShare) - chargeScore(hrvZ: mz, share: minShare))
                            hrvOnlyDelta.append(chargeScore(hrvZ: cz, share: maxShare) - chargeScore(hrvZ: mz, share: maxShare))
                        }
                    }
                }
                if let current { priorCurrentRmssd.append(current) }
            }
        }

        return RROrderDownstreamSensitivity(
            readinessHrv: RROrderReadinessHrvSensitivity(
                evaluatedNights: readinessDeltaZ.count,
                changedFlagNights: changedFlags,
                transitionCounts: transitions,
                currentZ: RROrderDistributionSummary(readinessCurrentZ),
                counterfactualZ: RROrderDistributionSummary(readinessMagnitudeZ),
                zDelta: RROrderSignedDifferenceSummary(readinessDeltaZ)
            ),
            chargeHrv: RROrderChargeHrvSensitivity(
                evaluatedNights: chargeZDelta.count,
                hrvZDelta: RROrderSignedDifferenceSummary(chargeZDelta),
                fullDriverSetScoreDelta: RROrderSignedDifferenceSummary(fullDriverDelta),
                hrvOnlyScoreDelta: RROrderSignedDifferenceSummary(hrvOnlyDelta),
                minimumHrvWeightShare: minShare,
                maximumHrvWeightShare: maxShare
            )
        )
    }

    static func readinessFlag(_ z: Double) -> RROrderReadinessHrvFlag {
        if z >= 0.5 { return .good }
        if z >= -0.5 { return .neutral }
        if z >= -1.0 { return .watch }
        return .bad
    }

    static func chargeScore(hrvZ: Double, share: Double) -> Double {
        let composite = hrvZ * share
        let score = 100.0 / (1.0 + exp(-RecoveryScorer.logisticK * (composite - RecoveryScorer.logisticZ0)))
        return max(0, min(100, score))
    }
}

public enum RROrderCorpusSummaryInput {
    public static func decodeJSONLines(_ data: Data) throws -> [RROrderCorpusRecord] {
        guard let text = String(data: data, encoding: .utf8) else { throw RROrderCorpusSummaryError.invalidUTF8 }
        let decoder = JSONDecoder()
        var records: [RROrderCorpusRecord] = [], seen = Set<String>()
        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let record: RROrderCorpusRecord
            do { record = try decoder.decode(RROrderCorpusRecord.self, from: Data(line.utf8)) }
            catch { throw RROrderCorpusSummaryError.invalidJSONLine(line: offset + 1, message: String(describing: error)) }
            guard record.schemaVersion == RROrderCorpusRecord.currentSchemaVersion else {
                throw RROrderCorpusSummaryError.unsupportedRecordSchema(line: offset + 1, version: record.schemaVersion)
            }
            guard record.auditSchemaVersion == RROrderAuditReport.currentSchemaVersion else {
                throw RROrderCorpusSummaryError.unsupportedAuditSchema(line: offset + 1, version: record.auditSchemaVersion)
            }
            guard seen.insert(record.observationKey).inserted else {
                throw RROrderCorpusSummaryError.duplicateObservation(record.observationKey)
            }
            records.append(record)
        }
        return records
    }
}

public enum RROrderCorpusSummaryEncoder {
    public static func encode(_ summary: RROrderCorpusSummary, format: RROrderCorpusSummaryFormat) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(summary); data.append(0x0A); return data
        case .markdown: return Data(markdown(summary).utf8)
        }
    }

    public static func markdown(_ s: RROrderCorpusSummary) -> String {
        var lines: [String] = ["# R-R ordering corpus summary", "", "## Scope", "",
            "- Sessions: \(s.recordCount)", "- Devices: \(s.deviceCount)",
            "- Range: \(s.earliestDetectedStartUTC ?? "n/a") to \(s.latestEndUTC ?? "n/a")",
            "- Duration: \(distribution(s.durationSeconds, unit: "s"))", "",
            "## Input filtering", "",
            "- Rows in windows: \(s.inputFilters.totalRows)", "- Rows used by scoring: \(s.inputFilters.scoringRows) (\(percent(s.inputFilters.scoringFraction)))",
            "- Excluded rows: \(s.inputFilters.excludedRows); SpO2-IBI \(s.inputFilters.spo2IbiRows); suspect timestamp \(s.inputFilters.suspectTimestampRows)", "",
            "## Structural order integrity", "",
            "- Status counts: \(dictionary(s.integrityCounts))", "- Audit flags: \(dictionary(s.flagCounts))",
            "- Raw order-invariant failures: \(s.rawInvariantFailures)", "",
            "## Permutation severity", "",
            "- Trustworthy groups: \(s.permutation.trustworthyGroups)",
            "- Reordered groups: \(s.permutation.reorderedGroups) (\(percent(s.permutation.reorderedGroupFraction)))",
            "- Value inversions: \(s.permutation.valueInversions)/\(s.permutation.possibleValueInversions) (\(percent(s.permutation.normalizedInversionFraction)))",
            "- Session inversion fraction: \(distribution(s.permutation.inversionFractionBySession, unit: ""))", "",
            "## HRV effect", "",
            "- RMSSD delta current - counterfactual: \(signed(s.rmssd.delta, unit: "ms"))",
            "- SDNN delta: \(signed(s.sdnn.delta, unit: "ms"))",
            "- Mean-NN delta: \(signed(s.meanNN.delta, unit: "ms"))",
            "- pNN50 delta: \(signed(s.pnn50PercentagePoints.delta, unit: "percentage points"))",
            "- Raw RMSSD delta: \(signed(s.rawRmssd.delta, unit: "ms"))",
            "- Bootstrap 95% RMSSD mean delta: \(interval(s.rmssdDeltaBootstrap95.mean95, unit: "ms"))",
            "- Bootstrap 95% RMSSD median delta: \(interval(s.rmssdDeltaBootstrap95.median95, unit: "ms"))", "",
            "## Cleaning sensitivity", "",
            "- Current rejected fraction: \(distribution(s.cleaning.currentRejectedFraction, unit: ""))",
            "- Counterfactual rejected fraction: \(distribution(s.cleaning.counterfactualRejectedFraction, unit: ""))",
            "- Sessions where clean-beat count changes: \(s.cleaning.sessionsWhereCleaningCountChanged)", "",
            "## Downstream HRV sensitivity", "",
            "- Readiness-style HRV signal evaluated nights: \(s.downstreamSensitivity.readinessHrv.evaluatedNights)",
            "- Readiness HRV flag changed: \(s.downstreamSensitivity.readinessHrv.changedFlagNights)",
            "- Readiness transitions: \(dictionary(s.downstreamSensitivity.readinessHrv.transitionCounts))",
            "- Charge HRV scenarios evaluated nights: \(s.downstreamSensitivity.chargeHrv.evaluatedNights)",
            "- Charge full-driver neutral-context score delta: \(signed(s.downstreamSensitivity.chargeHrv.fullDriverSetScoreDelta, unit: "points"))",
            "- Charge HRV-only neutral-context score delta: \(signed(s.downstreamSensitivity.chargeHrv.hrvOnlyScoreDelta, unit: "points"))", "",
            "## Associations", "",
            "- Spearman trustworthy coverage vs |RMSSD delta|: \(number(s.associations.trustworthyCoverageVsAbsoluteRmssdDeltaSpearman)) (n=\(s.associations.trustworthyCoveragePairCount))",
            "- Spearman inversion fraction vs |RMSSD delta|: \(number(s.associations.inversionFractionVsAbsoluteRmssdDeltaSpearman)) (n=\(s.associations.inversionPairCount))", "",
            "## Integrity strata", ""]
        lines += stratumLines(s.integrityStrata)
        lines += ["", "## Coverage strata", ""] + stratumLines(s.coverageStrata)
        lines += ["", "## Duration strata", ""] + stratumLines(s.durationStrata)
        lines += ["", "## Staging strata", ""] + stratumLines(s.stagingStrata)
        lines += ["", "## Interpretation limits", "",
            "- The magnitude-order path is an offline counterfactual over identical stored rows, not a claim about every historical release pipeline.",
            "- Bootstrap intervals describe sampling uncertainty of this corpus only; they are not clinical confidence intervals or hypothesis tests.",
            "- Readiness sensitivity covers the HRV signal only, using the same lnRMSSD baseline spine and thresholds, not the full multi-signal Readiness level.",
            "- Charge sensitivity is a scenario envelope with other drivers held at baseline; it is not a reconstruction of the user's actual historical Charge.",
            "- No raw R-R sequence or raw device ID appears in this summary.", ""]
        return lines.joined(separator: "\n")
    }

    private static func stratumLines(_ strata: [RROrderStratumSummary]) -> [String] {
        ["| Stratum | Sessions | Paired RMSSD | Median delta ms | Median trustworthy coverage |", "|---|---:|---:|---:|---:|"]
            + strata.map { "| \($0.name) | \($0.sessionCount) | \($0.pairedRmssdCount) | \(number($0.rmssdDeltaMs.distribution?.median)) | \(percent($0.trustworthyCoverage?.median)) |" }
    }

    private static func distribution(_ d: RROrderDistributionSummary?, unit: String) -> String {
        guard let d else { return "n/a" }; let suffix = unit.isEmpty ? "" : " \(unit)"
        return "n=\(d.count), mean \(number(d.mean))\(suffix), median \(number(d.median))\(suffix), p10-p90 \(number(d.p10))-\(number(d.p90))\(suffix)"
    }
    private static func signed(_ d: RROrderSignedDifferenceSummary, unit: String) -> String { distribution(d.distribution, unit: unit) }
    private static func interval(_ i: RROrderBootstrapInterval?, unit: String) -> String { i.map { "\(number($0.lower)) to \(number($0.upper)) \(unit)" } ?? "n/a" }
    private static func dictionary(_ d: [String: Int]) -> String { d.keys.sorted().map { "\($0)=\(d[$0]!)" }.joined(separator: ", ") }
    private static func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0 * 100) } ?? "n/a" }
    private static func number(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "n/a" }
}
