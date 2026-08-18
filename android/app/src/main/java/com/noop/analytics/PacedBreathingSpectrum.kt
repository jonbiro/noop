package com.noop.analytics

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/*
 * PacedBreathingSpectrum.kt - transparent spectral concentration during guided breathing.
 * Behavioral twin of StrandAnalytics/PacedBreathingSpectrum.swift.
 *
 * This intentionally avoids branded/proprietary "coherence" scores. It reports
 * the dominant paced-breathing-range PRV frequency and how much total spectral
 * power is concentrated around that peak. No emotional or clinical claim.
 */
object PacedBreathingSpectrum {
    const val SEARCH_LOW_HZ = 0.04
    const val SEARCH_HIGH_HZ = 0.26
    const val TOTAL_HIGH_HZ = 0.40
    const val PEAK_HALF_WIDTH_HZ = 0.015
    const val FREQUENCY_STEP_HZ = 0.002
    const val MINIMUM_SPAN_SECONDS = 60.0
    const val MINIMUM_BEATS = 50
    const val MIN_NN_MS = 300.0
    const val MAX_NN_MS = 2_000.0

    data class Result(
        val peakHz: Double,
        val peakBreathsPerMinute: Double,
        val peakBandPower: Double,
        val totalBandPower: Double,
        val peakPowerFraction: Double,
        val peakToRemainderRatio: Double?,
        val targetBreathsPerMinute: Double?,
        val paceErrorBreathsPerMinute: Double?,
        /** Full duration represented by all supplied RR intervals. */
        val spanSeconds: Double,
        val beatCount: Int,
    )

    fun evaluate(
        cleanedNNMs: List<Double>,
        targetBreathsPerMinute: Double? = null,
    ): Result? {
        if (cleanedNNMs.size < MINIMUM_BEATS ||
            cleanedNNMs.any { !it.isFinite() || it < MIN_NN_MS || it > MAX_NN_MS }
        ) return null
        if (targetBreathsPerMinute != null &&
            (!targetBreathsPerMinute.isFinite() ||
                targetBreathsPerMinute <= 0.0 ||
                targetBreathsPerMinute > 60.0 * SEARCH_HIGH_HZ)
        ) return null

        val times = DoubleArray(cleanedNNMs.size)
        var elapsed = 0.0
        for (i in cleanedNNMs.indices) {
            times[i] = elapsed
            elapsed += cleanedNNMs[i] / 1000.0
        }
        // times[] contains interval start times; elapsed is the end of the final
        // interval and therefore the full duration represented by the RR series.
        val span = elapsed
        if (span < MINIMUM_SPAN_SECONDS) return null

        val mean = cleanedNNMs.sum() / cleanedNNMs.size.toDouble()
        val y = DoubleArray(cleanedNNMs.size) { cleanedNNMs[it] - mean }
        var variance = 0.0
        for (value in y) variance += value * value
        variance /= y.size.toDouble()
        if (!variance.isFinite() || variance <= 0.0) return null

        val resolvableLow = max(SEARCH_LOW_HZ, 1.0 / span)
        if (resolvableLow >= TOTAL_HIGH_HZ) return null

        val points = ArrayList<Point>()
        var f = resolvableLow
        while (f <= TOTAL_HIGH_HZ + 1e-12) {
            val p = lombScarglePower(times, y, f, variance)
            if (!p.isFinite() || p < 0.0) return null
            points.add(Point(f, p))
            f += FREQUENCY_STEP_HZ
        }
        if (points.size < 2) return null

        val searchUpper = min(SEARCH_HIGH_HZ, TOTAL_HIGH_HZ)
        var peak: Point? = null
        for (point in points) {
            if (point.f < SEARCH_LOW_HZ || point.f > searchUpper) continue
            if (peak == null || point.p > peak.p) peak = point
        }
        val chosenPeak = peak ?: return null

        val totalPower = integrate(points, resolvableLow, TOTAL_HIGH_HZ)
        val peakLow = max(resolvableLow, chosenPeak.f - PEAK_HALF_WIDTH_HZ)
        val peakHigh = min(TOTAL_HIGH_HZ, chosenPeak.f + PEAK_HALF_WIDTH_HZ)
        val peakPower = integrate(points, peakLow, peakHigh)
        if (!totalPower.isFinite() || !peakPower.isFinite() || totalPower <= 0.0 || peakPower < 0.0) return null

        val fraction = min(1.0, max(0.0, peakPower / totalPower))
        val remainder = max(0.0, totalPower - peakPower)
        val ratio = if (remainder > 0.0) peakPower / remainder else null
        val peakBpm = chosenPeak.f * 60.0
        val paceError = targetBreathsPerMinute?.let { abs(peakBpm - it) }

        return Result(
            peakHz = chosenPeak.f,
            peakBreathsPerMinute = peakBpm,
            peakBandPower = peakPower,
            totalBandPower = totalPower,
            peakPowerFraction = fraction,
            peakToRemainderRatio = ratio,
            targetBreathsPerMinute = targetBreathsPerMinute,
            paceErrorBreathsPerMinute = paceError,
            spanSeconds = span,
            beatCount = cleanedNNMs.size,
        )
    }

    private data class Point(val f: Double, val p: Double)

    private fun integrate(points: List<Point>, low: Double, high: Double): Double {
        if (high <= low) return 0.0
        val filtered = points.filter { it.f >= low - 1e-12 && it.f <= high + 1e-12 }.sortedBy { it.f }
        if (filtered.size < 2) return 0.0
        var area = 0.0
        for (i in 1 until filtered.size) {
            area += 0.5 * (filtered[i - 1].p + filtered[i].p) * (filtered[i].f - filtered[i - 1].f)
        }
        return area
    }

    private fun lombScarglePower(times: DoubleArray, y: DoubleArray, freqHz: Double, variance: Double): Double {
        val omega = 2.0 * PI * freqHz
        var sin2 = 0.0
        var cos2 = 0.0
        for (t in times) {
            val a = 2.0 * omega * t
            sin2 += sin(a)
            cos2 += cos(a)
        }
        val tau = atan2(sin2, cos2) / (2.0 * omega)
        var cTerm = 0.0
        var cDen = 0.0
        var sTerm = 0.0
        var sDen = 0.0
        for (i in times.indices) {
            val arg = omega * (times[i] - tau)
            val c = cos(arg)
            val s = sin(arg)
            cTerm += y[i] * c
            cDen += c * c
            sTerm += y[i] * s
            sDen += s * s
        }
        val cosPart = if (cDen > 0.0) cTerm * cTerm / cDen else 0.0
        val sinPart = if (sDen > 0.0) sTerm * sTerm / sDen else 0.0
        return (cosPart + sinPart) / (2.0 * variance)
    }
}
