package com.noop.analytics

import com.noop.data.RrInterval
import kotlin.math.abs

enum class RrOrderIntegrityStatus { NO_DATA, COMPLETE, PARTIAL, AMBIGUOUS }

enum class RrOrderAuditFlag {
    NO_INTERVALS,
    LEGACY_MULTI_BEAT_ORDER_UNKNOWN,
    MIXED_KNOWN_UNKNOWN_ORDER,
    DUPLICATE_RECORDED_ORDER,
    CURRENT_BELOW_PRODUCTION_BEAT_GATE,
    COUNTERFACTUAL_BELOW_PRODUCTION_BEAT_GATE,
    CURRENT_HAS_NO_CONTIGUOUS_PAIRS,
    COUNTERFACTUAL_HAS_NO_CONTIGUOUS_PAIRS,
    CLEANING_REJECTED_INTERVALS,
    COUNTERFACTUAL_CHANGES_CLEANING_OUTCOME,
    MAGNITUDE_ORDER_CHANGES_PRODUCTION_HRV,
    RAW_ORDER_INVARIANT_FAILURE,
    CAPTURE_UNDER_COVERED,
    CAPTURE_SAME_SECOND_OVER_COUNT,
    CAPTURE_CROSS_SECOND_OVER_COUNT,
    BEAT_TIMING_UNTRUSTWORTHY,
    EXACT_DUPLICATE_BEAT_ROWS,
    SAME_SECOND_SHADOW_DROPS_ROWS,
    CROSS_SECOND_UPPER_BOUND_DROPS_ROWS,
}

data class RrOrderCaptureDiagnostics(
    val coverage: Double,
    val collapsedCoverage: Double,
    val coverageVerdict: String,
    val beatSpreadTrustworthy: Boolean,
    val beatAccurateFraction: Double,
    val beatValuesTrustworthy: Boolean,
    val exactDuplicateBeatCount: Int,
    val sameSecondShadowDropped: Int,
    val sameSecondShadowCoverage: Double,
    val sameSecondShadowBeatAccurateFraction: Double,
    val crossSecondUpperBoundDropped: Int,
    val crossSecondUpperBoundCoverage: Double,
    val crossSecondUpperBoundBeatAccurateFraction: Double,
)

data class RrOrderPermutationImpact(
    val trustworthyGroupsCompared: Int,
    val reorderedGroups: Int,
    val reorderedIntervals: Int,
    val valueInversions: Int,
    val possibleValueInversions: Int,
    val maxValueInversionsInGroup: Int,
    val maxTrustworthyGroupSize: Int,
) {
    val reorderedGroupFraction: Double?
        get() = if (trustworthyGroupsCompared == 0) null else reorderedGroups.toDouble() / trustworthyGroupsCompared.toDouble()
    val normalizedValueInversionFraction: Double?
        get() = if (possibleValueInversions == 0) null else valueInversions.toDouble() / possibleValueInversions.toDouble()
}

data class RrOrderProvenance(
    val totalIntervals: Int,
    val intervalsWithRecordedOrder: Int,
    val intervalsWithUnknownOrder: Int,
    val firstTs: Long?,
    val lastTs: Long?,
    val distinctSeconds: Int,
    val maxIntervalsPerSecond: Int,
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
    val spanSeconds: Long? get() = if (firstTs == null || lastTs == null) null else maxOf(0L, lastTs - firstTs)
    val recordedOrderFraction: Double? get() = if (totalIntervals == 0) null else intervalsWithRecordedOrder.toDouble() / totalIntervals
    val trustworthyMultiBeatIntervalFraction: Double? get() = if (multiBeatIntervals == 0) null else trustworthyMultiBeatIntervals.toDouble() / multiBeatIntervals
    val hasCompleteSameSecondOrder: Boolean get() = multiBeatIntervals == trustworthyMultiBeatIntervals
    val integrityStatus: RrOrderIntegrityStatus
        get() = when {
            totalIntervals == 0 -> RrOrderIntegrityStatus.NO_DATA
            ambiguousRecordedOrderMultiBeatSeconds > 0 -> RrOrderIntegrityStatus.AMBIGUOUS
            allUnknownMultiBeatSeconds > 0 || mixedOrderMultiBeatSeconds > 0 -> RrOrderIntegrityStatus.PARTIAL
            else -> RrOrderIntegrityStatus.COMPLETE
        }
}

data class RrOrderHrvSnapshot(
    val rmssdMs: Double?,
    val sdnnMs: Double?,
    val meanNNMs: Double?,
    val pnn50Pct: Double?,
    val nInput: Int,
    val nClean: Int,
    val actualCleanCount: Int,
    val rejectedCount: Int,
    val rejectedFraction: Double?,
    val contiguousPairCount: Int,
    val meetsProductionBeatGate: Boolean,
    val rawRmssdMs: Double?,
    val rawSdnnMs: Double?,
    val rawMeanNNMs: Double?,
    val rawPnn50Pct: Double?,
)

data class RrOrderAuditReport(
    val schemaVersion: Int,
    val integrityStatus: RrOrderIntegrityStatus,
    val flags: List<RrOrderAuditFlag>,
    val provenance: RrOrderProvenance,
    val captureDiagnostics: RrOrderCaptureDiagnostics,
    val permutationImpact: RrOrderPermutationImpact,
    val currentOrder: RrOrderHrvSnapshot,
    val magnitudeOrderCounterfactual: RrOrderHrvSnapshot,
) {
    val rmssdCurrentMinusMagnitudeMs: Double? get() = difference(currentOrder.rmssdMs, magnitudeOrderCounterfactual.rmssdMs)
    val rmssdCurrentMinusMagnitudePctOfCurrent: Double? get() = percentageDifference(currentOrder.rmssdMs, magnitudeOrderCounterfactual.rmssdMs)
    val sdnnCurrentMinusMagnitudeMs: Double? get() = difference(currentOrder.sdnnMs, magnitudeOrderCounterfactual.sdnnMs)
    val sdnnCurrentMinusMagnitudePctOfCurrent: Double? get() = percentageDifference(currentOrder.sdnnMs, magnitudeOrderCounterfactual.sdnnMs)
    val meanNNCurrentMinusMagnitudeMs: Double? get() = difference(currentOrder.meanNNMs, magnitudeOrderCounterfactual.meanNNMs)
    val meanNNCurrentMinusMagnitudePctOfCurrent: Double? get() = percentageDifference(currentOrder.meanNNMs, magnitudeOrderCounterfactual.meanNNMs)
    val pnn50CurrentMinusMagnitudePercentagePoints: Double? get() = difference(currentOrder.pnn50Pct, magnitudeOrderCounterfactual.pnn50Pct)
    val rawRmssdCurrentMinusMagnitudeMs: Double? get() = difference(currentOrder.rawRmssdMs, magnitudeOrderCounterfactual.rawRmssdMs)
    val rawRmssdCurrentMinusMagnitudePctOfCurrent: Double? get() = percentageDifference(currentOrder.rawRmssdMs, magnitudeOrderCounterfactual.rawRmssdMs)
    val rawPnn50CurrentMinusMagnitudePercentagePoints: Double? get() = difference(currentOrder.rawPnn50Pct, magnitudeOrderCounterfactual.rawPnn50Pct)
    val rawOrderInvariantPreserved: Boolean
        get() = approximatelyEqual(currentOrder.rawMeanNNMs, magnitudeOrderCounterfactual.rawMeanNNMs) &&
            approximatelyEqual(currentOrder.rawSdnnMs, magnitudeOrderCounterfactual.rawSdnnMs)

    private fun difference(current: Double?, magnitude: Double?): Double? = if (current == null || magnitude == null) null else current - magnitude
    private fun percentageDifference(current: Double?, magnitude: Double?): Double? {
        val delta = difference(current, magnitude) ?: return null
        if (current == null || current == 0.0) return null
        return delta / current * 100.0
    }
    private fun approximatelyEqual(left: Double?, right: Double?, tolerance: Double = 1e-9): Boolean = when {
        left == null && right == null -> true
        left == null || right == null -> false
        else -> abs(left - right) <= tolerance
    }
}

object RrOrderAudit {
    const val SCHEMA_VERSION: Int = 3

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
        var valueInversions = 0
        var possibleValueInversions = 0
        var maxValueInversions = 0
        var maxTrustworthyGroupSize = 0

        for (group in groups) {
            if (group.size == 1) { singleBeatSeconds++; continue }
            multiBeatSeconds++
            multiBeatIntervals += group.size
            val recorded = group.mapNotNull { it.ord }
            when {
                recorded.isEmpty() -> { allUnknownSeconds++; allUnknownIntervals += group.size }
                recorded.size != group.size -> { mixedSeconds++; mixedIntervals += group.size }
                recorded.toSet().size != recorded.size -> { ambiguousSeconds++; ambiguousIntervals += group.size }
                else -> {
                    trustworthySeconds++
                    trustworthyIntervals += group.size
                    maxTrustworthyGroupSize = maxOf(maxTrustworthyGroupSize, group.size)
                    val values = group.map { it.rrMs }
                    val inversions = valueInversionCount(values)
                    val possible = unequalPairCount(values)
                    valueInversions += inversions
                    possibleValueInversions += possible
                    maxValueInversions = maxOf(maxValueInversions, inversions)
                    if (inversions > 0) { magnitudeReorderedSeconds++; magnitudeReorderedIntervals += group.size }
                }
            }
        }

        val recordedCount = currentRows.count { it.ord != null }
        val provenance = RrOrderProvenance(
            currentRows.size, recordedCount, currentRows.size - recordedCount,
            currentRows.firstOrNull()?.ts, currentRows.lastOrNull()?.ts, groups.size,
            groups.maxOfOrNull { it.size } ?: 0, singleBeatSeconds, multiBeatSeconds, multiBeatIntervals,
            trustworthySeconds, trustworthyIntervals, allUnknownSeconds, allUnknownIntervals,
            mixedSeconds, mixedIntervals, ambiguousSeconds, ambiguousIntervals,
            magnitudeReorderedSeconds, magnitudeReorderedIntervals,
        )
        val capture = captureDiagnostics(currentRows)
        val permutation = RrOrderPermutationImpact(
            trustworthySeconds, magnitudeReorderedSeconds, magnitudeReorderedIntervals,
            valueInversions, possibleValueInversions, maxValueInversions, maxTrustworthyGroupSize,
        )
        val current = snapshot(currentRows)
        val magnitude = snapshot(magnitudeRows)
        val provisional = RrOrderAuditReport(
            SCHEMA_VERSION, provenance.integrityStatus, emptyList(), provenance, capture, permutation, current, magnitude
        )
        return provisional.copy(flags = flags(provisional))
    }

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

    private val magnitudeComparator = Comparator<RrInterval> { left, right ->
        when {
            left.ts != right.ts -> left.ts.compareTo(right.ts)
            left.rrMs != right.rrMs -> left.rrMs.compareTo(right.rrMs)
            else -> left.seq.compareTo(right.seq)
        }
    }

    private fun captureDiagnostics(rows: List<RrInterval>): RrOrderCaptureDiagnostics {
        val ts = rows.map { it.ts }
        val rr = rows.map { it.rrMs.toDouble() }
        val coverage = HrvAnalyzer.rrCoverage(ts, rr)
        val collapsed = HrvAnalyzer.collapsedCoverage(ts, rr)
        val verdict = HrvAnalyzer.classifyCoverage(coverage, collapsed)
        val accurate = HrvAnalyzer.beatAccurateFraction(ts, rr)
        val same = HrvAnalyzer.collapseOverCount(ts, rr, rrTolMs = 40.0, windowSec = 0L)
        val cross = HrvAnalyzer.collapseOverCount(ts, rr, rrTolMs = 40.0, windowSec = 1L)
        return RrOrderCaptureDiagnostics(
            coverage = coverage,
            collapsedCoverage = collapsed,
            coverageVerdict = verdictWire(verdict),
            beatSpreadTrustworthy = HrvAnalyzer.beatSpreadIsTrustworthy(verdict),
            beatAccurateFraction = accurate,
            beatValuesTrustworthy = HrvAnalyzer.beatValuesAreTrustworthy(accurate),
            exactDuplicateBeatCount = HrvAnalyzer.duplicateBeatCount(ts, rr),
            sameSecondShadowDropped = maxOf(0, rr.size - same.second.size),
            sameSecondShadowCoverage = HrvAnalyzer.rrCoverage(same.first, same.second),
            sameSecondShadowBeatAccurateFraction = HrvAnalyzer.beatAccurateFraction(same.first, same.second),
            crossSecondUpperBoundDropped = maxOf(0, rr.size - cross.second.size),
            crossSecondUpperBoundCoverage = HrvAnalyzer.rrCoverage(cross.first, cross.second),
            crossSecondUpperBoundBeatAccurateFraction = HrvAnalyzer.beatAccurateFraction(cross.first, cross.second),
        )
    }

    private fun verdictWire(verdict: RrCoverageVerdict): String = when (verdict) {
        RrCoverageVerdict.PLAUSIBLE -> "plausible"
        RrCoverageVerdict.UNDER_COVERED -> "underCovered"
        RrCoverageVerdict.SAME_SECOND_OVER_COUNT -> "sameSecondOverCount"
        RrCoverageVerdict.CROSS_SECOND_OVER_COUNT -> "crossSecondOverCount"
        RrCoverageVerdict.UNMEASURABLE -> "unmeasurable"
    }

    private fun snapshot(rows: List<RrInterval>): RrOrderHrvSnapshot {
        val values = rows.map { it.rrMs.toDouble() }
        val cleaned = HrvAnalyzer.cleanRRGapAware(values)
        val result = HrvAnalyzer.analyzeRaw(values)
        val actualCleanCount = cleaned.nn.size
        val rejectedCount = maxOf(0, values.size - actualCleanCount)
        val rejectedFraction = if (values.isEmpty()) null else rejectedCount.toDouble() / values.size
        val contiguousPairCount = cleaned.contiguous.drop(1).count { it }
        return RrOrderHrvSnapshot(
            result.rmssd, result.sdnn, result.meanNN, result.pnn50, result.nInput, result.nClean,
            actualCleanCount, rejectedCount, rejectedFraction, contiguousPairCount,
            actualCleanCount >= HrvAnalyzer.MIN_BEATS,
            HrvAnalyzer.rmssdRaw(values), HrvAnalyzer.sdnnRaw(values),
            if (values.isEmpty()) null else values.average(), rawPnn50(values),
        )
    }

    private fun rawPnn50(values: List<Double>): Double? {
        if (values.size < 2) return null
        var nn50 = 0
        for (i in 1 until values.size) if (abs(values[i] - values[i - 1]) > 50.0) nn50++
        return nn50.toDouble() / (values.size - 1) * 100.0
    }

    private fun valueInversionCount(values: List<Int>): Int {
        var count = 0
        for (i in 0 until maxOf(0, values.size - 1)) for (j in i + 1 until values.size) if (values[i] > values[j]) count++
        return count
    }

    private fun unequalPairCount(values: List<Int>): Int {
        var count = 0
        for (i in 0 until maxOf(0, values.size - 1)) for (j in i + 1 until values.size) if (values[i] != values[j]) count++
        return count
    }

    private fun flags(report: RrOrderAuditReport): List<RrOrderAuditFlag> {
        val out = mutableListOf<RrOrderAuditFlag>()
        val p = report.provenance
        val c = report.captureDiagnostics
        val current = report.currentOrder
        val magnitude = report.magnitudeOrderCounterfactual
        if (p.totalIntervals == 0) out += RrOrderAuditFlag.NO_INTERVALS
        if (p.allUnknownMultiBeatSeconds > 0) out += RrOrderAuditFlag.LEGACY_MULTI_BEAT_ORDER_UNKNOWN
        if (p.mixedOrderMultiBeatSeconds > 0) out += RrOrderAuditFlag.MIXED_KNOWN_UNKNOWN_ORDER
        if (p.ambiguousRecordedOrderMultiBeatSeconds > 0) out += RrOrderAuditFlag.DUPLICATE_RECORDED_ORDER
        if (current.actualCleanCount < HrvAnalyzer.MIN_BEATS) out += RrOrderAuditFlag.CURRENT_BELOW_PRODUCTION_BEAT_GATE
        if (magnitude.actualCleanCount < HrvAnalyzer.MIN_BEATS) out += RrOrderAuditFlag.COUNTERFACTUAL_BELOW_PRODUCTION_BEAT_GATE
        if (current.actualCleanCount >= 2 && current.contiguousPairCount == 0) out += RrOrderAuditFlag.CURRENT_HAS_NO_CONTIGUOUS_PAIRS
        if (magnitude.actualCleanCount >= 2 && magnitude.contiguousPairCount == 0) out += RrOrderAuditFlag.COUNTERFACTUAL_HAS_NO_CONTIGUOUS_PAIRS
        if (current.rejectedCount > 0 || magnitude.rejectedCount > 0) out += RrOrderAuditFlag.CLEANING_REJECTED_INTERVALS
        if (current.actualCleanCount != magnitude.actualCleanCount) out += RrOrderAuditFlag.COUNTERFACTUAL_CHANGES_CLEANING_OUTCOME
        if (materiallyDifferent(report.rmssdCurrentMinusMagnitudeMs) || materiallyDifferent(report.sdnnCurrentMinusMagnitudeMs) ||
            materiallyDifferent(report.meanNNCurrentMinusMagnitudeMs) || materiallyDifferent(report.pnn50CurrentMinusMagnitudePercentagePoints)) {
            out += RrOrderAuditFlag.MAGNITUDE_ORDER_CHANGES_PRODUCTION_HRV
        }
        if (!report.rawOrderInvariantPreserved) out += RrOrderAuditFlag.RAW_ORDER_INVARIANT_FAILURE
        when (c.coverageVerdict) {
            "underCovered" -> out += RrOrderAuditFlag.CAPTURE_UNDER_COVERED
            "sameSecondOverCount" -> out += RrOrderAuditFlag.CAPTURE_SAME_SECOND_OVER_COUNT
            "crossSecondOverCount" -> out += RrOrderAuditFlag.CAPTURE_CROSS_SECOND_OVER_COUNT
        }
        if (!c.beatValuesTrustworthy) out += RrOrderAuditFlag.BEAT_TIMING_UNTRUSTWORTHY
        if (c.exactDuplicateBeatCount > 0) out += RrOrderAuditFlag.EXACT_DUPLICATE_BEAT_ROWS
        if (c.sameSecondShadowDropped > 0) out += RrOrderAuditFlag.SAME_SECOND_SHADOW_DROPS_ROWS
        if (c.crossSecondUpperBoundDropped > 0) out += RrOrderAuditFlag.CROSS_SECOND_UPPER_BOUND_DROPS_ROWS
        return out
    }

    private fun materiallyDifferent(value: Double?, tolerance: Double = 1e-9): Boolean = value != null && abs(value) > tolerance
}
