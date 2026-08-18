package com.noop.analytics

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

/*
 * PersistentShiftDetector.kt - generic one-sided longitudinal baseline-shift detector.
 * Behavioral twin of StrandAnalytics/PersistentShiftDetector.swift.
 *
 * Domain-neutral CUSUM over a robust personal baseline. It names no illness,
 * stress, overtraining, or diagnosis; callers supply the domain interpretation.
 */
object PersistentShiftDetector {
    const val DEFAULT_BASELINE_WINDOW = 28
    const val DEFAULT_MINIMUM_BASELINE = 7
    const val DEFAULT_REFERENCE_K = 0.5
    const val DEFAULT_DECISION_H = 4.0
    const val DEFAULT_PERSIST_OBSERVATIONS = 2
    const val DEFAULT_RECOVERY_Z = 0.5
    const val DEFAULT_RECOVERY_OBSERVATIONS = 2
    const val NORMALIZED_MAD_SCALE = 1.482602218505602

    enum class Direction { UPPER, LOWER }
    enum class State { MISSING, CALIBRATING, DEGENERATE_BASELINE, NORMAL, WATCH, SUSTAINED }

    data class Point(
        val index: Int,
        val state: State,
        val orientedZ: Double?,
        val cusum: Double?,
        val baselineMedian: Double?,
        val baselineScale: Double?,
        val baselineCount: Int,
        val observed: Boolean,
    )

    fun evaluate(
        values: List<Double?>,
        direction: Direction,
        baselineWindow: Int = DEFAULT_BASELINE_WINDOW,
        minimumBaseline: Int = DEFAULT_MINIMUM_BASELINE,
        referenceK: Double = DEFAULT_REFERENCE_K,
        decisionH: Double = DEFAULT_DECISION_H,
        persistObservations: Int = DEFAULT_PERSIST_OBSERVATIONS,
        recoveryZ: Double = DEFAULT_RECOVERY_Z,
        recoveryObservations: Int = DEFAULT_RECOVERY_OBSERVATIONS,
    ): List<Point>? {
        if (baselineWindow < minimumBaseline ||
            minimumBaseline < 2 ||
            !referenceK.isFinite() || referenceK < 0.0 ||
            !decisionH.isFinite() || decisionH <= 0.0 ||
            persistObservations <= 0 ||
            !recoveryZ.isFinite() ||
            recoveryObservations <= 0 ||
            values.any { it != null && !it.isFinite() }
        ) return null

        val out = ArrayList<Point>(values.size)
        var cusum = 0.0
        var alertRun = 0
        var recoveryRun = 0

        for (i in values.indices) {
            val lo = max(0, i - baselineWindow)
            val baseline = ArrayList<Double>(i - lo)
            for (j in lo until i) values[j]?.let { baseline.add(it) }

            val current = values[i]
            if (current == null) {
                out.add(Point(i, State.MISSING, null, null, null, null, baseline.size, false))
                continue
            }
            if (baseline.size < minimumBaseline) {
                out.add(Point(i, State.CALIBRATING, null, null, null, null, baseline.size, true))
                continue
            }

            val location = median(baseline)
            var scale = NORMALIZED_MAD_SCALE * median(baseline.map { abs(it - location) })
            if (scale <= 0.0) scale = sampleSD(baseline)
            if (!scale.isFinite() || scale <= 0.0) {
                out.add(Point(i, State.DEGENERATE_BASELINE, null, null, location, null, baseline.size, true))
                continue
            }

            val rawZ = (current - location) / scale
            val z = if (direction == Direction.UPPER) rawZ else -rawZ
            cusum = max(0.0, cusum + z - referenceK)

            if (z < recoveryZ) {
                recoveryRun++
                if (recoveryRun >= recoveryObservations) {
                    cusum = 0.0
                    alertRun = 0
                }
            } else {
                recoveryRun = 0
            }

            val state = if (cusum > decisionH) {
                alertRun++
                if (alertRun >= persistObservations) State.SUSTAINED else State.WATCH
            } else {
                alertRun = 0
                State.NORMAL
            }

            out.add(Point(i, state, z, cusum, location, scale, baseline.size, true))
        }
        return out
    }

    private fun median(values: List<Double>): Double {
        val sorted = values.sorted()
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[mid - 1] + sorted[mid]) / 2.0 else sorted[mid]
    }

    private fun sampleSD(values: List<Double>): Double {
        if (values.size < 2) return 0.0
        val mean = values.sum() / values.size.toDouble()
        var ss = 0.0
        for (value in values) {
            val d = value - mean
            ss += d * d
        }
        return sqrt(ss / (values.size - 1).toDouble())
    }
}
