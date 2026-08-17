import Foundation
import WhoopStore

/// Structural integrity of same-second R-R ordering.
///
/// This is deliberately about what NOOP actually observed, not whether the resulting HRV happens to look
/// plausible. A window can have a numerically plausible RMSSD and still be `.partial` or `.ambiguous`.
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
}

/// How far trustworthy same-second groups are from ascending `(rrMs, seq)` magnitude order.
///
/// `valueInversions` counts only pairs with unequal R-R values, so swapping equal-valued intervals does not
/// create a false impact signal. `possibleValueInversions` is the number of unequal-valued pairs that could
/// be inverted in the trustworthy groups.
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
///
/// A non-nil `ord` is not sufficient by itself: `ord` is batch-local, so a transport that inserts one
/// beat at a time records `0` for every beat. A multi-beat second is trustworthy only when every row has
/// an order and those orders are unique. Gaps such as `[2, 7]` are allowed because scoring filters can
/// remove rows while preserving the relative order of the survivors.
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

    /// Trustworthy seconds whose R-R value sequence differs from ascending magnitude order.
    public let magnitudeReorderedTrustworthySeconds: Int
    public let magnitudeReorderedTrustworthyIntervals: Int

    public var spanSeconds: Int? {
        guard let firstTs, let lastTs else { return nil }
        return max(0, lastTs - firstTs)
    }

    /// Fraction of every interval whose insertion supplied an `ord`. This is descriptive, not a quality
    /// verdict: duplicate recorded orders remain ambiguous even though every row has a value.
    public var recordedOrderFraction: Double? {
        guard totalIntervals > 0 else { return nil }
        return Double(intervalsWithRecordedOrder) / Double(totalIntervals)
    }

    /// Fraction of intervals in multi-beat seconds whose relative order can be trusted.
    public var trustworthyMultiBeatIntervalFraction: Double? {
        guard multiBeatIntervals > 0 else { return nil }
        return Double(trustworthyMultiBeatIntervals) / Double(multiBeatIntervals)
    }

    /// True when every same-second group that can affect successive differences has a unique recorded order.
    /// Empty data also returns true for this narrow predicate; use `integrityStatus` to distinguish no data.
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
    /// Full production pipeline: range filter, Malik rejection, gap-aware successive differences, 20-beat gate.
    public let rmssdMs: Double?
    public let sdnnMs: Double?
    public let meanNNMs: Double?
    public let pnn50Pct: Double?
    public let nInput: Int

    /// `HRVResult.nClean`, retained for byte-level visibility into the production API. The production result
    /// intentionally reports zero when the minimum-beat gate fails, so do not use this as the physical number
    /// of beats that survived cleaning; use `actualCleanCount` for that diagnostic question.
    public let nClean: Int

    /// Number of beats that actually survive range + ectopic cleaning, even below the 20-beat score gate.
    public let actualCleanCount: Int
    public let rejectedCount: Int
    public let rejectedFraction: Double?
    public let contiguousPairCount: Int
    public let meetsProductionBeatGate: Bool

    /// Unfiltered statistics over the exact stored sequence. Raw mean and SDNN are order-invariant and act as
    /// useful counterfactual sanity checks; RMSSD and pNN50 are order-sensitive.
    public let rawRmssdMs: Double?
    public let rawSdnnMs: Double?
    public let rawMeanNNMs: Double?
    public let rawPnn50Pct: Double?
}

/// Current production ordering and the former magnitude-order counterfactual over identical rows.
public struct RROrderAuditReport: Equatable, Sendable, Codable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let integrityStatus: RROrderIntegrityStatus
    public let flags: [RROrderAuditFlag]
    public let provenance: RROrderProvenance
    public let permutationImpact: RROrderPermutationImpact
    public let currentOrder: RROrderHrvSnapshot
    public let magnitudeOrderCounterfactual: RROrderHrvSnapshot

    public var rmssdCurrentMinusMagnitudeMs: Double? {
        difference(currentOrder.rmssdMs, magnitudeOrderCounterfactual.rmssdMs)
    }

    public var rmssdCurrentMinusMagnitudePctOfCurrent: Double? {
        percentageDifference(currentOrder.rmssdMs, magnitudeOrderCounterfactual.rmssdMs)
    }

    public var sdnnCurrentMinusMagnitudeMs: Double? {
        difference(currentOrder.sdnnMs, magnitudeOrderCounterfactual.sdnnMs)
    }

    public var sdnnCurrentMinusMagnitudePctOfCurrent: Double? {
        percentageDifference(currentOrder.sdnnMs, magnitudeOrderCounterfactual.sdnnMs)
    }

    public var meanNNCurrentMinusMagnitudeMs: Double? {
        difference(currentOrder.meanNNMs, magnitudeOrderCounterfactual.meanNNMs)
    }

    public var meanNNCurrentMinusMagnitudePctOfCurrent: Double? {
        percentageDifference(currentOrder.meanNNMs, magnitudeOrderCounterfactual.meanNNMs)
    }

    /// pNN50 is already a percentage, so the most interpretable delta is percentage points.
    public var pnn50CurrentMinusMagnitudePercentagePoints: Double? {
        difference(currentOrder.pnn50Pct, magnitudeOrderCounterfactual.pnn50Pct)
    }

    public var rawRmssdCurrentMinusMagnitudeMs: Double? {
        difference(currentOrder.rawRmssdMs, magnitudeOrderCounterfactual.rawRmssdMs)
    }

    public var rawRmssdCurrentMinusMagnitudePctOfCurrent: Double? {
        percentageDifference(currentOrder.rawRmssdMs, magnitudeOrderCounterfactual.rawRmssdMs)
    }

    public var rawPnn50CurrentMinusMagnitudePercentagePoints: Double? {
        difference(currentOrder.rawPnn50Pct, magnitudeOrderCounterfactual.rawPnn50Pct)
    }

    /// Reordering an identical multiset must not change raw mean or raw SDNN. A false result indicates an
    /// audit implementation defect rather than physiological behavior.
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

/// Pure, deterministic audit of the R-R ordering fix introduced for #823.
///
/// This does not change scoring. It answers four questions:
/// 1. How much of the requested interval population has trustworthy same-second emission order?
/// 2. How severe is the permutation away from the former magnitude ordering?
/// 3. What does NOOP's exact HRV implementation produce now versus the former order, across all core metrics?
/// 4. Does changing order alter cleaning/gap behavior as well as successive-difference statistics?
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
                allUnknownSeconds += 1
                allUnknownIntervals += group.count
                continue
            }
            if recorded.count != group.count {
                mixedSeconds += 1
                mixedIntervals += group.count
                continue
            }
            if Set(recorded).count != recorded.count {
                ambiguousSeconds += 1
                ambiguousIntervals += group.count
                continue
            }

            trustworthySeconds += 1
            trustworthyIntervals += group.count
            maxTrustworthyGroupSize = max(maxTrustworthyGroupSize, group.count)

            let inversions = valueInversionCount(group.map(\.rrMs))
            let possible = unequalPairCount(group.map(\.rrMs))
            valueInversions += inversions
            possibleValueInversions += possible
            maxValueInversions = max(maxValueInversions, inversions)

            if inversions > 0 {
                magnitudeReorderedSeconds += 1
                magnitudeReorderedIntervals += group.count
            }
        }

        let recordedCount = currentRows.reduce(into: 0) { count, row in
            if row.emissionOrder != nil { count += 1 }
        }
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
            permutationImpact: permutationImpact,
            currentOrder: current,
            magnitudeOrderCounterfactual: magnitude
        )
        return RROrderAuditReport(
            schemaVersion: provisional.schemaVersion,
            integrityStatus: provisional.integrityStatus,
            flags: flags(for: provisional),
            provenance: provenance,
            permutationImpact: permutationImpact,
            currentOrder: current,
            magnitudeOrderCounterfactual: magnitude
        )
    }

    /// Mirror SQLite's `ORDER BY ts ASC, ord ASC, rrMs ASC, seq ASC`, including NULL-first `ord`.
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

    /// The pre-#823 read order used as an offline counterfactual only.
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

    private static func snapshot(_ rows: [RROrderAuditRow]) -> RROrderHrvSnapshot {
        let values = rows.map { Double($0.rrMs) }
        let cleaned = HRVAnalyzer.cleanRRGapAware(values)
        let result = HRVAnalyzer.analyze(rawRR: values)
        let actualCleanCount = cleaned.nn.count
        let rejectedCount = max(0, values.count - actualCleanCount)
        let rejectedFraction = values.isEmpty ? nil : Double(rejectedCount) / Double(values.count)
        let contiguousPairCount = cleaned.contiguous.dropFirst().reduce(into: 0) { count, contiguous in
            if contiguous { count += 1 }
        }
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
        for index in 1..<values.count where abs(values[index] - values[index - 1]) > 50.0 {
            nn50 += 1
        }
        return Double(nn50) / Double(values.count - 1) * 100.0
    }

    /// Number of value pairs whose observed order is descending relative to magnitude order.
    /// Equal values are deliberately ignored because swapping them cannot change any R-R statistic.
    private static func valueInversionCount(_ values: [Int]) -> Int {
        guard values.count >= 2 else { return 0 }
        var count = 0
        for i in 0..<(values.count - 1) {
            for j in (i + 1)..<values.count where values[i] > values[j] {
                count += 1
            }
        }
        return count
    }

    private static func unequalPairCount(_ values: [Int]) -> Int {
        guard values.count >= 2 else { return 0 }
        var count = 0
        for i in 0..<(values.count - 1) {
            for j in (i + 1)..<values.count where values[i] != values[j] {
                count += 1
            }
        }
        return count
    }

    private static func flags(for report: RROrderAuditReport) -> [RROrderAuditFlag] {
        var flags: [RROrderAuditFlag] = []
        let p = report.provenance
        let current = report.currentOrder
        let magnitude = report.magnitudeOrderCounterfactual

        if p.totalIntervals == 0 { flags.append(.noIntervals) }
        if p.allUnknownMultiBeatSeconds > 0 { flags.append(.legacyMultiBeatOrderUnknown) }
        if p.mixedOrderMultiBeatSeconds > 0 { flags.append(.mixedKnownUnknownOrder) }
        if p.ambiguousRecordedOrderMultiBeatSeconds > 0 { flags.append(.duplicateRecordedOrder) }
        if current.actualCleanCount < HRVAnalyzer.minBeats { flags.append(.currentBelowProductionBeatGate) }
        if magnitude.actualCleanCount < HRVAnalyzer.minBeats { flags.append(.counterfactualBelowProductionBeatGate) }
        if current.actualCleanCount >= 2 && current.contiguousPairCount == 0 { flags.append(.currentHasNoContiguousPairs) }
        if magnitude.actualCleanCount >= 2 && magnitude.contiguousPairCount == 0 {
            flags.append(.counterfactualHasNoContiguousPairs)
        }
        if current.rejectedCount > 0 || magnitude.rejectedCount > 0 { flags.append(.cleaningRejectedIntervals) }
        if current.actualCleanCount != magnitude.actualCleanCount {
            flags.append(.counterfactualChangesCleaningOutcome)
        }
        if materiallyDifferent(report.rmssdCurrentMinusMagnitudeMs)
            || materiallyDifferent(report.sdnnCurrentMinusMagnitudeMs)
            || materiallyDifferent(report.meanNNCurrentMinusMagnitudeMs)
            || materiallyDifferent(report.pnn50CurrentMinusMagnitudePercentagePoints) {
            flags.append(.magnitudeOrderChangesProductionHrv)
        }
        if !report.rawOrderInvariantPreserved { flags.append(.rawOrderInvariantFailure) }
        return flags
    }

    private static func materiallyDifferent(_ value: Double?, tolerance: Double = 1e-9) -> Bool {
        guard let value else { return false }
        return abs(value) > tolerance
    }
}
