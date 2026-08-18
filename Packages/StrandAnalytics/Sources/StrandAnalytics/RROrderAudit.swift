import Foundation
import WhoopStore

/// Structural integrity of same-second R-R ordering.
public enum RROrderIntegrityStatus: String, Equatable, Sendable, Codable {
    case noData
    case complete
    case partial
    case ambiguous
}

/// Machine-readable audit facts. These are diagnostic observations, not clinical or score-withholding rules.
public enum RROrderAuditFlag: String, Equatable, Sendable, Codable, CaseIterable {
    case noIntervals
    case legacyMultiBeatOrderUnknown
    case mixedKnownUnknownOrder
    case duplicateRecordedOrder
    case currentBelowProductionBeatGate
    case counterfactualBelowProductionBeatGate
    case currentHasNoContiguousPairs
    case counterfactualHasNoContiguousPairs
    case cleaningRejectedIntervals
    case counterfactualChangesCleaningOutcome
    case magnitudeOrderChangesProductionHrv
    case rawOrderInvariantFailure
    case captureUnderCovered
    case captureSameSecondOverCount
    case captureCrossSecondOverCount
    case beatTimingUntrustworthy
    case exactDuplicateBeatRows
    case sameSecondShadowDropsRows
    case crossSecondUpperBoundDropsRows
}

/// NOOP's existing capture/over-count diagnostics applied to the exact audited row population.
///
/// `crossSecondUpperBound*` uses `collapseOverCount(windowSec: 1)`, which upstream explicitly defines as
/// aggressive instrumentation only. It deliberately over-merges a steady real HR and is included here to
/// size the possible cross-second contribution, never as a proposed production de-duplication path.
public struct RROrderCaptureDiagnostics: Equatable, Sendable, Codable {
    public let coverage: Double
    public let collapsedCoverage: Double
    public let coverageVerdict: String
    public let beatSpreadTrustworthy: Bool
    public let beatAccurateFraction: Double
    public let beatValuesTrustworthy: Bool
    public let exactDuplicateBeatCount: Int

    public let sameSecondShadowDropped: Int
    public let sameSecondShadowCoverage: Double
    public let sameSecondShadowBeatAccurateFraction: Double

    public let crossSecondUpperBoundDropped: Int
    public let crossSecondUpperBoundCoverage: Double
    public let crossSecondUpperBoundBeatAccurateFraction: Double
}

/// How far trustworthy same-second groups are from ascending `(rrMs, seq)` magnitude order.
public struct RROrderPermutationImpact: Equatable, Sendable, Codable {
    public let trustworthyGroupsCompared: Int
    public let reorderedGroups: Int
    public let reorderedIntervals: Int
    public let valueInversions: Int
    public let possibleValueInversions: Int
    public let maxValueInversionsInGroup: Int
    public let maxTrustworthyGroupSize: Int

    public var reorderedGroupFraction: Double? {
        guard trustworthyGroupsCompared > 0 else { return nil }
        return Double(reorderedGroups) / Double(trustworthyGroupsCompared)
    }

    public var normalizedValueInversionFraction: Double? {
        guard possibleValueInversions > 0 else { return nil }
        return Double(valueInversions) / Double(possibleValueInversions)
    }
}

/// Counts that describe whether same-second R-R order is actually known.
public struct RROrderProvenance: Equatable, Sendable, Codable {
    public let totalIntervals: Int
    public let intervalsWithRecordedOrder: Int
    public let intervalsWithUnknownOrder: Int
    public let firstTs: Int?
    public let lastTs: Int?
    public let distinctSeconds: Int
    public let maxIntervalsPerSecond: Int
    public let singleBeatSeconds: Int
    public let multiBeatSeconds: Int
    public let multiBeatIntervals: Int
    public let trustworthyMultiBeatSeconds: Int
    public let trustworthyMultiBeatIntervals: Int
    public let allUnknownMultiBeatSeconds: Int
    public let allUnknownMultiBeatIntervals: Int
    public let mixedOrderMultiBeatSeconds: Int
    public let mixedOrderMultiBeatIntervals: Int
    public let ambiguousRecordedOrderMultiBeatSeconds: Int
    public let ambiguousRecordedOrderMultiBeatIntervals: Int
    public let magnitudeReorderedTrustworthySeconds: Int
    public let magnitudeReorderedTrustworthyIntervals: Int

    public var spanSeconds: Int? {
        guard let firstTs, let lastTs else { return nil }
        return max(0, lastTs - firstTs)
    }

    public var recordedOrderFraction: Double? {
        guard totalIntervals > 0 else { return nil }
        return Double(intervalsWithRecordedOrder) / Double(totalIntervals)
    }

    public var trustworthyMultiBeatIntervalFraction: Double? {
        guard multiBeatIntervals > 0 else { return nil }
        return Double(trustworthyMultiBeatIntervals) / Double(multiBeatIntervals)
    }

    public var hasCompleteSameSecondOrder: Bool {
        multiBeatIntervals == trustworthyMultiBeatIntervals
    }

    public var integrityStatus: RROrderIntegrityStatus {
        if totalIntervals == 0 { return .noData }
        if ambiguousRecordedOrderMultiBeatSeconds > 0 { return .ambiguous }
        if allUnknownMultiBeatSeconds > 0 || mixedOrderMultiBeatSeconds > 0 { return .partial }
        return .complete
    }
}

/// HRV output and cleaning diagnostics for one ordering of the same stored interval population.
public struct RROrderHrvSnapshot: Equatable, Sendable, Codable {
    public let rmssdMs: Double?
    public let sdnnMs: Double?
    public let meanNNMs: Double?
    public let pnn50Pct: Double?
    public let nInput: Int
    /// Production `HRVResult.nClean`, which is zero when the minimum-beat gate fails.
    public let nClean: Int
    /// True number of beats that survive range + ectopic cleaning, even below the score gate.
    public let actualCleanCount: Int
    public let rejectedCount: Int
    public let rejectedFraction: Double?
    public let contiguousPairCount: Int
    public let meetsProductionBeatGate: Bool
    public let rawRmssdMs: Double?
    public let rawSdnnMs: Double?
    public let rawMeanNNMs: Double?
    public let rawPnn50Pct: Double?
}

/// Current production ordering and the former magnitude-order counterfactual over identical rows.
public struct RROrderAuditReport: Equatable, Sendable, Codable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let integrityStatus: RROrderIntegrityStatus
    public let flags: [RROrderAuditFlag]
    public let provenance: RROrderProvenance
    public let captureDiagnostics: RROrderCaptureDiagnostics
    public let permutationImpact: RROrderPermutationImpact
    public let currentOrder: RROrderHrvSnapshot
    public let magnitudeOrderCounterfactual: RROrderHrvSnapshot

    public var rmssdCurrentMinusMagnitudeMs: Double? { difference(currentOrder.rmssdMs, magnitudeOrderCounterfactual.rmssdMs) }
    public var rmssdCurrentMinusMagnitudePctOfCurrent: Double? { percentageDifference(currentOrder.rmssdMs, magnitudeOrderCounterfactual.rmssdMs) }
    public var sdnnCurrentMinusMagnitudeMs: Double? { difference(currentOrder.sdnnMs, magnitudeOrderCounterfactual.sdnnMs) }
    public var sdnnCurrentMinusMagnitudePctOfCurrent: Double? { percentageDifference(currentOrder.sdnnMs, magnitudeOrderCounterfactual.sdnnMs) }
    public var meanNNCurrentMinusMagnitudeMs: Double? { difference(currentOrder.meanNNMs, magnitudeOrderCounterfactual.meanNNMs) }
    public var meanNNCurrentMinusMagnitudePctOfCurrent: Double? { percentageDifference(currentOrder.meanNNMs, magnitudeOrderCounterfactual.meanNNMs) }
    public var pnn50CurrentMinusMagnitudePercentagePoints: Double? { difference(currentOrder.pnn50Pct, magnitudeOrderCounterfactual.pnn50Pct) }
    public var rawRmssdCurrentMinusMagnitudeMs: Double? { difference(currentOrder.rawRmssdMs, magnitudeOrderCounterfactual.rawRmssdMs) }
    public var rawRmssdCurrentMinusMagnitudePctOfCurrent: Double? { percentageDifference(currentOrder.rawRmssdMs, magnitudeOrderCounterfactual.rawRmssdMs) }
    public var rawPnn50CurrentMinusMagnitudePercentagePoints: Double? { difference(currentOrder.rawPnn50Pct, magnitudeOrderCounterfactual.rawPnn50Pct) }

    /// Reordering an identical multiset must not change raw mean or raw SDNN.
    public var rawOrderInvariantPreserved: Bool {
        approximatelyEqual(currentOrder.rawMeanNNMs, magnitudeOrderCounterfactual.rawMeanNNMs)
            && approximatelyEqual(currentOrder.rawSdnnMs, magnitudeOrderCounterfactual.rawSdnnMs)
    }

    private func difference(_ current: Double?, _ magnitude: Double?) -> Double? {
        guard let current, let magnitude else { return nil }
        return current - magnitude
    }

    private func percentageDifference(_ current: Double?, _ magnitude: Double?) -> Double? {
        guard let current, current != 0, let delta = difference(current, magnitude) else { return nil }
        return delta / current * 100.0
    }

    private func approximatelyEqual(_ lhs: Double?, _ rhs: Double?, tolerance: Double = 1e-9) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (l?, r?): return abs(l - r) <= tolerance
        default: return false
        }
    }
}

/// Pure, deterministic R-R input-integrity audit.
public enum RROrderAudit {
    public static func evaluate(_ rows: [RROrderAuditRow]) -> RROrderAuditReport {
        let currentRows = rows.sorted(by: currentComparator)
        let magnitudeRows = rows.sorted(by: magnitudeComparator)
        let groups = groupsBySecond(currentRows)

        var singleBeatSeconds = 0
        var multiBeatSeconds = 0
        var multiBeatIntervals = 0
        var trustworthySeconds = 0
        var trustworthyIntervals = 0
        var allUnknownSeconds = 0
        var allUnknownIntervals = 0
        var mixedSeconds = 0
        var mixedIntervals = 0
        var ambiguousSeconds = 0
        var ambiguousIntervals = 0
        var magnitudeReorderedSeconds = 0
        var magnitudeReorderedIntervals = 0
        var valueInversions = 0
        var possibleValueInversions = 0
        var maxValueInversions = 0
        var maxTrustworthyGroupSize = 0

        for group in groups {
            guard group.count > 1 else {
                singleBeatSeconds += 1
                continue
            }
            multiBeatSeconds += 1
            multiBeatIntervals += group.count
            let recorded = group.compactMap(\.emissionOrder)
            if recorded.isEmpty {
                allUnknownSeconds += 1; allUnknownIntervals += group.count; continue
            }
            if recorded.count != group.count {
                mixedSeconds += 1; mixedIntervals += group.count; continue
            }
            if Set(recorded).count != recorded.count {
                ambiguousSeconds += 1; ambiguousIntervals += group.count; continue
            }

            trustworthySeconds += 1
            trustworthyIntervals += group.count
            maxTrustworthyGroupSize = max(maxTrustworthyGroupSize, group.count)
            let values = group.map(\.rrMs)
            let inversions = valueInversionCount(values)
            let possible = unequalPairCount(values)
            valueInversions += inversions
            possibleValueInversions += possible
            maxValueInversions = max(maxValueInversions, inversions)
            if inversions > 0 {
                magnitudeReorderedSeconds += 1
                magnitudeReorderedIntervals += group.count
            }
        }

        let recordedCount = currentRows.reduce(into: 0) { count, row in if row.emissionOrder != nil { count += 1 } }
        let provenance = RROrderProvenance(
            totalIntervals: currentRows.count,
            intervalsWithRecordedOrder: recordedCount,
            intervalsWithUnknownOrder: currentRows.count - recordedCount,
            firstTs: currentRows.first?.ts,
            lastTs: currentRows.last?.ts,
            distinctSeconds: groups.count,
            maxIntervalsPerSecond: groups.map(\.count).max() ?? 0,
            singleBeatSeconds: singleBeatSeconds,
            multiBeatSeconds: multiBeatSeconds,
            multiBeatIntervals: multiBeatIntervals,
            trustworthyMultiBeatSeconds: trustworthySeconds,
            trustworthyMultiBeatIntervals: trustworthyIntervals,
            allUnknownMultiBeatSeconds: allUnknownSeconds,
            allUnknownMultiBeatIntervals: allUnknownIntervals,
            mixedOrderMultiBeatSeconds: mixedSeconds,
            mixedOrderMultiBeatIntervals: mixedIntervals,
            ambiguousRecordedOrderMultiBeatSeconds: ambiguousSeconds,
            ambiguousRecordedOrderMultiBeatIntervals: ambiguousIntervals,
            magnitudeReorderedTrustworthySeconds: magnitudeReorderedSeconds,
            magnitudeReorderedTrustworthyIntervals: magnitudeReorderedIntervals
        )
        let capture = captureDiagnostics(currentRows)
        let permutationImpact = RROrderPermutationImpact(
            trustworthyGroupsCompared: trustworthySeconds,
            reorderedGroups: magnitudeReorderedSeconds,
            reorderedIntervals: magnitudeReorderedIntervals,
            valueInversions: valueInversions,
            possibleValueInversions: possibleValueInversions,
            maxValueInversionsInGroup: maxValueInversions,
            maxTrustworthyGroupSize: maxTrustworthyGroupSize
        )
        let current = snapshot(currentRows)
        let magnitude = snapshot(magnitudeRows)
        let provisional = RROrderAuditReport(
            schemaVersion: RROrderAuditReport.currentSchemaVersion,
            integrityStatus: provenance.integrityStatus,
            flags: [],
            provenance: provenance,
            captureDiagnostics: capture,
            permutationImpact: permutationImpact,
            currentOrder: current,
            magnitudeOrderCounterfactual: magnitude
        )
        return RROrderAuditReport(
            schemaVersion: provisional.schemaVersion,
            integrityStatus: provisional.integrityStatus,
            flags: flags(for: provisional),
            provenance: provenance,
            captureDiagnostics: capture,
            permutationImpact: permutationImpact,
            currentOrder: current,
            magnitudeOrderCounterfactual: magnitude
        )
    }

    private static func currentComparator(_ lhs: RROrderAuditRow, _ rhs: RROrderAuditRow) -> Bool {
        if lhs.ts != rhs.ts { return lhs.ts < rhs.ts }
        switch (lhs.emissionOrder, rhs.emissionOrder) {
        case (nil, .some): return true
        case (.some, nil): return false
        case let (.some(l), .some(r)) where l != r: return l < r
        default: break
        }
        if lhs.rrMs != rhs.rrMs { return lhs.rrMs < rhs.rrMs }
        return lhs.seq < rhs.seq
    }

    private static func magnitudeComparator(_ lhs: RROrderAuditRow, _ rhs: RROrderAuditRow) -> Bool {
        if lhs.ts != rhs.ts { return lhs.ts < rhs.ts }
        if lhs.rrMs != rhs.rrMs { return lhs.rrMs < rhs.rrMs }
        return lhs.seq < rhs.seq
    }

    private static func groupsBySecond(_ rows: [RROrderAuditRow]) -> [[RROrderAuditRow]] {
        var groups: [[RROrderAuditRow]] = []
        for row in rows {
            if let lastTs = groups.last?.first?.ts, lastTs == row.ts {
                groups[groups.count - 1].append(row)
            } else {
                groups.append([row])
            }
        }
        return groups
    }

    private static func captureDiagnostics(_ rows: [RROrderAuditRow]) -> RROrderCaptureDiagnostics {
        let ts = rows.map(\.ts)
        let rr = rows.map { Double($0.rrMs) }
        let coverage = HRVAnalyzer.rrCoverage(tsSec: ts, rrMs: rr)
        let collapsed = HRVAnalyzer.collapsedCoverage(tsSec: ts, rrMs: rr)
        let verdict = HRVAnalyzer.classifyCoverage(coverage: coverage, collapsed: collapsed)
        let accurate = HRVAnalyzer.beatAccurateFraction(tsSec: ts, rrMs: rr)
        let same = HRVAnalyzer.collapseOverCount(tsSec: ts, rrMs: rr, rrTolMs: 40, windowSec: 0)
        let cross = HRVAnalyzer.collapseOverCount(tsSec: ts, rrMs: rr, rrTolMs: 40, windowSec: 1)
        return RROrderCaptureDiagnostics(
            coverage: coverage,
            collapsedCoverage: collapsed,
            coverageVerdict: verdict.rawValue,
            beatSpreadTrustworthy: HRVAnalyzer.beatSpreadIsTrustworthy(verdict),
            beatAccurateFraction: accurate,
            beatValuesTrustworthy: HRVAnalyzer.beatValuesAreTrustworthy(beatAccurateFraction: accurate),
            exactDuplicateBeatCount: HRVAnalyzer.duplicateBeatCount(tsSec: ts, rrMs: rr),
            sameSecondShadowDropped: max(0, rr.count - same.rrMs.count),
            sameSecondShadowCoverage: HRVAnalyzer.rrCoverage(tsSec: same.tsSec, rrMs: same.rrMs),
            sameSecondShadowBeatAccurateFraction: HRVAnalyzer.beatAccurateFraction(tsSec: same.tsSec, rrMs: same.rrMs),
            crossSecondUpperBoundDropped: max(0, rr.count - cross.rrMs.count),
            crossSecondUpperBoundCoverage: HRVAnalyzer.rrCoverage(tsSec: cross.tsSec, rrMs: cross.rrMs),
            crossSecondUpperBoundBeatAccurateFraction: HRVAnalyzer.beatAccurateFraction(tsSec: cross.tsSec, rrMs: cross.rrMs)
        )
    }

    private static func snapshot(_ rows: [RROrderAuditRow]) -> RROrderHrvSnapshot {
        let values = rows.map { Double($0.rrMs) }
        let cleaned = HRVAnalyzer.cleanRRGapAware(values)
        let result = HRVAnalyzer.analyze(rawRR: values)
        let actualCleanCount = cleaned.nn.count
        let rejectedCount = max(0, values.count - actualCleanCount)
        let rejectedFraction = values.isEmpty ? nil : Double(rejectedCount) / Double(values.count)
        let contiguousPairCount = cleaned.contiguous.dropFirst().reduce(into: 0) { count, contiguous in if contiguous { count += 1 } }
        return RROrderHrvSnapshot(
            rmssdMs: result.rmssd,
            sdnnMs: result.sdnn,
            meanNNMs: result.meanNN,
            pnn50Pct: result.pnn50,
            nInput: result.nInput,
            nClean: result.nClean,
            actualCleanCount: actualCleanCount,
            rejectedCount: rejectedCount,
            rejectedFraction: rejectedFraction,
            contiguousPairCount: contiguousPairCount,
            meetsProductionBeatGate: actualCleanCount >= HRVAnalyzer.minBeats,
            rawRmssdMs: HRVAnalyzer.rmssdRaw(values),
            rawSdnnMs: HRVAnalyzer.sdnnRaw(values),
            rawMeanNNMs: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
            rawPnn50Pct: rawPnn50(values)
        )
    }

    private static func rawPnn50(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        var nn50 = 0
        for index in 1..<values.count where abs(values[index] - values[index - 1]) > 50.0 { nn50 += 1 }
        return Double(nn50) / Double(values.count - 1) * 100.0
    }

    private static func valueInversionCount(_ values: [Int]) -> Int {
        guard values.count >= 2 else { return 0 }
        var count = 0
        for i in 0..<(values.count - 1) {
            for j in (i + 1)..<values.count where values[i] > values[j] { count += 1 }
        }
        return count
    }

    private static func unequalPairCount(_ values: [Int]) -> Int {
        guard values.count >= 2 else { return 0 }
        var count = 0
        for i in 0..<(values.count - 1) {
            for j in (i + 1)..<values.count where values[i] != values[j] { count += 1 }
        }
        return count
    }

    private static func flags(for report: RROrderAuditReport) -> [RROrderAuditFlag] {
        var flags: [RROrderAuditFlag] = []
        let p = report.provenance
        let c = report.captureDiagnostics
        let current = report.currentOrder
        let magnitude = report.magnitudeOrderCounterfactual

        if p.totalIntervals == 0 { flags.append(.noIntervals) }
        if p.allUnknownMultiBeatSeconds > 0 { flags.append(.legacyMultiBeatOrderUnknown) }
        if p.mixedOrderMultiBeatSeconds > 0 { flags.append(.mixedKnownUnknownOrder) }
        if p.ambiguousRecordedOrderMultiBeatSeconds > 0 { flags.append(.duplicateRecordedOrder) }
        if current.actualCleanCount < HRVAnalyzer.minBeats { flags.append(.currentBelowProductionBeatGate) }
        if magnitude.actualCleanCount < HRVAnalyzer.minBeats { flags.append(.counterfactualBelowProductionBeatGate) }
        if current.actualCleanCount >= 2 && current.contiguousPairCount == 0 { flags.append(.currentHasNoContiguousPairs) }
        if magnitude.actualCleanCount >= 2 && magnitude.contiguousPairCount == 0 { flags.append(.counterfactualHasNoContiguousPairs) }
        if current.rejectedCount > 0 || magnitude.rejectedCount > 0 { flags.append(.cleaningRejectedIntervals) }
        if current.actualCleanCount != magnitude.actualCleanCount { flags.append(.counterfactualChangesCleaningOutcome) }
        if materiallyDifferent(report.rmssdCurrentMinusMagnitudeMs)
            || materiallyDifferent(report.sdnnCurrentMinusMagnitudeMs)
            || materiallyDifferent(report.meanNNCurrentMinusMagnitudeMs)
            || materiallyDifferent(report.pnn50CurrentMinusMagnitudePercentagePoints) {
            flags.append(.magnitudeOrderChangesProductionHrv)
        }
        if !report.rawOrderInvariantPreserved { flags.append(.rawOrderInvariantFailure) }
        switch c.coverageVerdict {
        case HRVAnalyzer.RrCoverageVerdict.underCovered.rawValue: flags.append(.captureUnderCovered)
        case HRVAnalyzer.RrCoverageVerdict.sameSecondOverCount.rawValue: flags.append(.captureSameSecondOverCount)
        case HRVAnalyzer.RrCoverageVerdict.crossSecondOverCount.rawValue: flags.append(.captureCrossSecondOverCount)
        default: break
        }
        if !c.beatValuesTrustworthy { flags.append(.beatTimingUntrustworthy) }
        if c.exactDuplicateBeatCount > 0 { flags.append(.exactDuplicateBeatRows) }
        if c.sameSecondShadowDropped > 0 { flags.append(.sameSecondShadowDropsRows) }
        if c.crossSecondUpperBoundDropped > 0 { flags.append(.crossSecondUpperBoundDropsRows) }
        return flags
    }

    private static func materiallyDifferent(_ value: Double?, tolerance: Double = 1e-9) -> Bool {
        guard let value else { return false }
        return abs(value) > tolerance
    }
}
