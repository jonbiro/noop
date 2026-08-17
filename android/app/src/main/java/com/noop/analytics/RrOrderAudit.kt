package com.noop.analytics

import com.noop.data.RrInterval

/** Counts describing whether same-second R-R emission order is actually known. */
data class RrOrderProvenance(
    val totalIntervals: Int,
    val intervalsWithRecordedOrder: Int,
    val intervalsWithUnknownOrder: Int,
    val singleBeatSeconds: Int,
    val multiBeatSeconds: Int,
    val multiBeatIntervals: Int,
    val trustworthyMultiBeatSeconds: Int,
    val trustworthyMultiBeatIntervals: Int,
    val allUnknownMultiBeatSeconds: Int,
    val allUnknownMultiBeatIntervals: Int,
    val mixedOrderMultiBeatSeconds: Int,
    val mixedOrderMultiBeatIntervals: Int,
    val ambiguousRecordedOrderMultiBeatSeconds: Int,
    val ambiguousRecordedOrderMultiBeatIntervals: Int,
    val magnitudeReorderedTrustworthySeconds: Int,
    val magnitudeReorderedTrustworthyIntervals: Int,
) {
    /** Descriptive only: duplicate recorded orders are still ambiguous. */
    val recordedOrderFraction: Double?
        get() = if (totalIntervals == 0) null
        else intervalsWithRecordedOrder.toDouble() / totalIntervals.toDouble()

    /** Fraction of intervals in multi-beat seconds whose relative order is trustworthy. */
    val trustworthyMultiBeatIntervalFraction: Double?
        get() = if (multiBeatIntervals == 0) null
        else trustworthyMultiBeatIntervals.toDouble() / multiBeatIntervals.toDouble()

    /** True when every same-second group that can affect successive differences has unique order. */
    val hasCompleteSameSecondOrder: Boolean
        get() = multiBeatIntervals == trustworthyMultiBeatIntervals
}

/** HRV output for one ordering of the same stored interval population. */
data class RrOrderHrvSnapshot(
    val rmssdMs: Double?,
    val sdnnMs: Double?,
    val meanNNMs: Double?,
    val pnn50Pct: Double?,
    val nInput: Int,
    val nClean: Int,
    /** Unfiltered RMSSD, useful for diagnostic fixtures below the production 20-beat gate. */
    val rawRmssdMs: Double?,
)

/** Current production ordering and the former magnitude-order counterfactual. */
data class RrOrderAuditReport(
    val provenance: RrOrderProvenance,
    val currentOrder: RrOrderHrvSnapshot,
    val magnitudeOrderCounterfactual: RrOrderHrvSnapshot,
) {
    val rmssdCurrentMinusMagnitudeMs: Double?
        get() = difference(currentOrder.rmssdMs, magnitudeOrderCounterfactual.rmssdMs)

    val rmssdCurrentMinusMagnitudePctOfCurrent: Double?
        get() = percentageDifference(currentOrder.rmssdMs, magnitudeOrderCounterfactual.rmssdMs)

    val rawRmssdCurrentMinusMagnitudeMs: Double?
        get() = difference(currentOrder.rawRmssdMs, magnitudeOrderCounterfactual.rawRmssdMs)

    val rawRmssdCurrentMinusMagnitudePctOfCurrent: Double?
        get() = percentageDifference(currentOrder.rawRmssdMs, magnitudeOrderCounterfactual.rawRmssdMs)

    private fun difference(current: Double?, magnitude: Double?): Double? =
        if (current == null || magnitude == null) null else current - magnitude

    private fun percentageDifference(current: Double?, magnitude: Double?): Double? {
        val delta = difference(current, magnitude) ?: return null
        if (current == null || current == 0.0) return null
        return delta / current * 100.0
    }
}

/**
 * Pure parity twin of Swift `RROrderAudit`.
 *
 * This changes no score. It classifies the order provenance of a bounded R-R population and runs the
 * exact production HRV implementation over both the current SQLite order and the pre-#823 magnitude
 * order. A multi-beat second is trustworthy only when every row has an [RrInterval.ord] and those values
 * are unique. Gaps are allowed because scoring filters may remove rows without changing survivor order.
 */
object RrOrderAudit {
    fun evaluate(rows: List<RrInterval>): RrOrderAuditReport {
        val currentRows = rows.sortedWith(currentComparator)
        val magnitudeRows = rows.sortedWith(magnitudeComparator)
        val groups = currentRows.groupBy { it.ts }.values

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

        for (group in groups) {
            if (group.size == 1) {
                singleBeatSeconds += 1
                continue
            }

            multiBeatSeconds += 1
            multiBeatIntervals += group.size
            val recorded = group.mapNotNull { it.ord }

            when {
                recorded.isEmpty() -> {
                    allUnknownSeconds += 1
                    allUnknownIntervals += group.size
                }
                recorded.size != group.size -> {
                    mixedSeconds += 1
                    mixedIntervals += group.size
                }
                recorded.toSet().size != recorded.size -> {
                    ambiguousSeconds += 1
                    ambiguousIntervals += group.size
                }
                else -> {
                    trustworthySeconds += 1
                    trustworthyIntervals += group.size
                    val byMagnitude = group.sortedWith(magnitudeComparator)
                    if (group.map { it.rrMs } != byMagnitude.map { it.rrMs }) {
                        magnitudeReorderedSeconds += 1
                        magnitudeReorderedIntervals += group.size
                    }
                }
            }
        }

        val recordedCount = currentRows.count { it.ord != null }
        val provenance = RrOrderProvenance(
            totalIntervals = currentRows.size,
            intervalsWithRecordedOrder = recordedCount,
            intervalsWithUnknownOrder = currentRows.size - recordedCount,
            singleBeatSeconds = singleBeatSeconds,
            multiBeatSeconds = multiBeatSeconds,
            multiBeatIntervals = multiBeatIntervals,
            trustworthyMultiBeatSeconds = trustworthySeconds,
            trustworthyMultiBeatIntervals = trustworthyIntervals,
            allUnknownMultiBeatSeconds = allUnknownSeconds,
            allUnknownMultiBeatIntervals = allUnknownIntervals,
            mixedOrderMultiBeatSeconds = mixedSeconds,
            mixedOrderMultiBeatIntervals = mixedIntervals,
            ambiguousRecordedOrderMultiBeatSeconds = ambiguousSeconds,
            ambiguousRecordedOrderMultiBeatIntervals = ambiguousIntervals,
            magnitudeReorderedTrustworthySeconds = magnitudeReorderedSeconds,
            magnitudeReorderedTrustworthyIntervals = magnitudeReorderedIntervals,
        )

        return RrOrderAuditReport(
            provenance = provenance,
            currentOrder = snapshot(currentRows),
            magnitudeOrderCounterfactual = snapshot(magnitudeRows),
        )
    }

    /** Mirrors SQLite `ORDER BY ts ASC, ord ASC, rrMs ASC, seq ASC`, including NULL-first ord. */
    private val currentComparator = Comparator<RrInterval> { left, right ->
        when {
            left.ts != right.ts -> left.ts.compareTo(right.ts)
            left.ord == null && right.ord != null -> -1
            left.ord != null && right.ord == null -> 1
            left.ord != right.ord -> left.ord!!.compareTo(right.ord!!)
            left.rrMs != right.rrMs -> left.rrMs.compareTo(right.rrMs)
            else -> left.seq.compareTo(right.seq)
        }
    }

    /** The pre-#823 read order, retained only as an offline counterfactual. */
    private val magnitudeComparator = Comparator<RrInterval> { left, right ->
        when {
            left.ts != right.ts -> left.ts.compareTo(right.ts)
            left.rrMs != right.rrMs -> left.rrMs.compareTo(right.rrMs)
            else -> left.seq.compareTo(right.seq)
        }
    }

    private fun snapshot(rows: List<RrInterval>): RrOrderHrvSnapshot {
        val values = rows.map { it.rrMs.toDouble() }
        val result = HrvAnalyzer.analyzeRaw(values)
        return RrOrderHrvSnapshot(
            rmssdMs = result.rmssd,
            sdnnMs = result.sdnn,
            meanNNMs = result.meanNN,
            pnn50Pct = result.pnn50,
            nInput = result.nInput,
            nClean = result.nClean,
            rawRmssdMs = HrvAnalyzer.rmssdRaw(values),
        )
    }
}
