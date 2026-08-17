import Foundation
import WhoopStore

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

    /// Trustworthy seconds whose emission-order value sequence differs from `(rrMs, seq)` magnitude order.
    public let magnitudeReorderedTrustworthySeconds: Int
    public let magnitudeReorderedTrustworthyIntervals: Int

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
    public var hasCompleteSameSecondOrder: Bool {
        multiBeatIntervals == trustworthyMultiBeatIntervals
    }
}

/// HRV output for one ordering of the same stored interval population.
public struct RROrderHrvSnapshot: Equatable, Sendable, Codable {
    /// Full production pipeline: range filter, Malik rejection, gap-aware successive differences, 20-beat gate.
    public let rmssdMs: Double?
    public let sdnnMs: Double?
    public let meanNNMs: Double?
    public let pnn50Pct: Double?
    public let nInput: Int
    public let nClean: Int

    /// Unfiltered Task Force RMSSD over the input sequence. Useful even for a small diagnostic fixture.
    public let rawRmssdMs: Double?
}

/// Current production ordering and the former magnitude-order counterfactual over identical rows.
public struct RROrderAuditReport: Equatable, Sendable, Codable {
    public let provenance: RROrderProvenance
    public let currentOrder: RROrderHrvSnapshot
    public let magnitudeOrderCounterfactual: RROrderHrvSnapshot

    public var rmssdCurrentMinusMagnitudeMs: Double? {
        difference(currentOrder.rmssdMs, magnitudeOrderCounterfactual.rmssdMs)
    }

    public var rmssdCurrentMinusMagnitudePctOfCurrent: Double? {
        percentageDifference(currentOrder.rmssdMs, magnitudeOrderCounterfactual.rmssdMs)
    }

    public var rawRmssdCurrentMinusMagnitudeMs: Double? {
        difference(currentOrder.rawRmssdMs, magnitudeOrderCounterfactual.rawRmssdMs)
    }

    public var rawRmssdCurrentMinusMagnitudePctOfCurrent: Double? {
        percentageDifference(currentOrder.rawRmssdMs, magnitudeOrderCounterfactual.rawRmssdMs)
    }

    private func difference(_ current: Double?, _ magnitude: Double?) -> Double? {
        guard let current, let magnitude else { return nil }
        return current - magnitude
    }

    private func percentageDifference(_ current: Double?, _ magnitude: Double?) -> Double? {
        guard let current, current != 0, let delta = difference(current, magnitude) else { return nil }
        return delta / current * 100.0
    }
}

/// Pure, deterministic audit of the R-R ordering fix introduced for #823.
///
/// This does not change scoring. It answers two narrower questions:
/// 1. How much of the requested interval population has trustworthy same-second emission order?
/// 2. What does NOOP's exact HRV implementation produce now versus the former `(ts, rrMs, seq)` read order?
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
            let byMagnitude = group.sorted(by: magnitudeComparator)
            if group.map(\.rrMs) != byMagnitude.map(\.rrMs) {
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

        return RROrderAuditReport(
            provenance: provenance,
            currentOrder: snapshot(currentRows),
            magnitudeOrderCounterfactual: snapshot(magnitudeRows)
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
        let result = HRVAnalyzer.analyze(rawRR: values)
        return RROrderHrvSnapshot(
            rmssdMs: result.rmssd,
            sdnnMs: result.sdnn,
            meanNNMs: result.meanNN,
            pnn50Pct: result.pnn50,
            nInput: result.nInput,
            nClean: result.nClean,
            rawRmssdMs: HRVAnalyzer.rmssdRaw(values)
        )
    }
}
