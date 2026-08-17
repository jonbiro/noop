package com.noop.analytics

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

/*
 * CircadianRegularityEngine.kt - deterministic sleep-timing regularity and
 * social-clock metrics. Behavioral twin of the Swift engine.
 *
 * Additive to CircadianEngine: this does not change body-clock phase
 * estimation, Vitality, Readiness, or any headline score.
 *
 * Independent implementations of transparent published methods:
 *   - Phillips-style Sleep Regularity Index (SRI), scaled so random timing is
 *     0 and perfect day-to-day agreement is 100
 *   - social jetlag from free-day vs work-day mid-sleep
 *   - sleep-debt-corrected free-day mid-sleep, the mathematical substrate of
 *     MCTQ MSFsc
 *
 * WELLNESS / BEHAVIOURAL AWARENESS ONLY. Missing epochs are never treated as
 * wake. Full MCTQ chronotyping additionally requires an unconstrained free-day
 * wake, which this pure timing engine cannot infer from wearable data alone.
 */
object CircadianRegularityEngine {

    const val SECONDS_PER_DAY: Int = 86_400
    const val DEFAULT_SRI_LAG_SECONDS: Int = SECONDS_PER_DAY
    const val MINIMUM_NIGHTS_PER_SOCIAL_SIDE: Int = 2
    private const val CIRCULAR_RESULTANT_EPSILON: Double = 1e-9

    // Sleep Regularity Index

    data class SleepRegularityResult(
        /** Phillips SRI: perfect = 100, chance-level random timing = 0. */
        val score: Double,
        /** Pairs where both endpoints were observed. */
        val comparablePairs: Int,
        /** Pairs the supplied span could have contributed if fully observed. */
        val possiblePairs: Int,
        /** comparablePairs / possiblePairs, 0..1. Coverage, not confidence. */
        val coverage: Double,
        val matchingPairs: Int,
        /** Span represented by the epoch array, in days. */
        val spanDays: Double,
    )

    /**
     * Sleep Regularity Index over an epoch-aligned sleep/wake series.
     *
     * true = asleep, false = awake, null = unobserved. The lag defaults to 24 h
     * and must be an integer number of epochs. Missing endpoints reduce
     * coverage rather than being imputed.
     *
     * SRI = -100 + 200 * matchingPairs / comparablePairs.
     */
    fun sleepRegularityIndex(
        states: List<Boolean?>,
        epochSeconds: Int,
        lagSeconds: Int = DEFAULT_SRI_LAG_SECONDS,
    ): SleepRegularityResult? {
        if (epochSeconds <= 0 || lagSeconds <= 0 || lagSeconds % epochSeconds != 0) return null
        val lagEpochs = lagSeconds / epochSeconds
        if (lagEpochs <= 0 || states.size <= lagEpochs) return null

        val possible = states.size - lagEpochs
        var comparable = 0
        var matching = 0
        for (i in 0 until possible) {
            val a = states[i]
            val b = states[i + lagEpochs]
            if (a == null || b == null) continue
            comparable++
            if (a == b) matching++
        }
        if (comparable == 0) return null

        val agreement = matching.toDouble() / comparable.toDouble()
        val score = -100.0 + 200.0 * agreement
        val coverage = comparable.toDouble() / possible.toDouble()
        val spanDays = states.size.toDouble() * epochSeconds.toDouble() / SECONDS_PER_DAY.toDouble()
        return SleepRegularityResult(score, comparable, possible, coverage, matching, spanDays)
    }

    // Social jetlag

    data class SocialJetLagResult(
        /** Signed shortest arc free-day minus work-day mid-sleep, (-12, +12]. */
        val signedHours: Double,
        val absoluteHours: Double,
        val freeDayMidSleepHour: Double,
        val workdayMidSleepHour: Double,
        val freeDayNights: Int,
        val workdayNights: Int,
    )

    /**
     * Social jetlag from LOCAL clock-time mid-sleep hours. Each side is
     * summarized with a circular median so times straddling midnight remain
     * close. Returns null for insufficient, non-finite, or circularly
     * degenerate input.
     */
    fun socialJetLag(
        freeDayMidSleepHours: List<Double>,
        workdayMidSleepHours: List<Double>,
        minimumNightsPerSide: Int = MINIMUM_NIGHTS_PER_SOCIAL_SIDE,
    ): SocialJetLagResult? {
        if (minimumNightsPerSide <= 0 ||
            freeDayMidSleepHours.size < minimumNightsPerSide ||
            workdayMidSleepHours.size < minimumNightsPerSide ||
            freeDayMidSleepHours.any { !it.isFinite() } ||
            workdayMidSleepHours.any { !it.isFinite() }
        ) return null

        val free = circularMedianHour(freeDayMidSleepHours) ?: return null
        val work = circularMedianHour(workdayMidSleepHours) ?: return null
        val signed = signedCircularDifference(free, work)
        return SocialJetLagResult(
            signedHours = signed,
            absoluteHours = abs(signed),
            freeDayMidSleepHour = free,
            workdayMidSleepHour = work,
            freeDayNights = freeDayMidSleepHours.size,
            workdayNights = workdayMidSleepHours.size,
        )
    }

    // Sleep-debt-corrected free-day midpoint

    data class CorrectedMidSleepResult(
        val freeDayMidSleepHour: Double,
        val correctedMidSleepHour: Double,
        val medianFreeDaySleepDurationHours: Double,
        val averageWorkdaySleepDurationHours: Double,
        val averageWeekSleepDurationHours: Double,
        val oversleepCorrectionHours: Double,
        val freeDayNights: Int,
    )

    /**
     * Sleep-debt-corrected mid-sleep on free days, the timing substrate used by
     * MCTQ MSFsc.
     *
     * Standard MSFsc logic applies a correction only when free-day sleep exceeds
     * workday sleep. In that case, half of the excess of free-day sleep over
     * average weekly sleep is subtracted from free-day mid-sleep.
     */
    fun correctedFreeDayMidSleep(
        freeDayMidSleepHours: List<Double>,
        freeDaySleepDurationHours: List<Double>,
        averageWorkdaySleepDurationHours: Double,
        averageWeekSleepDurationHours: Double,
        minimumFreeDays: Int = MINIMUM_NIGHTS_PER_SOCIAL_SIDE,
    ): CorrectedMidSleepResult? {
        if (minimumFreeDays <= 0 ||
            freeDayMidSleepHours.size < minimumFreeDays ||
            freeDayMidSleepHours.size != freeDaySleepDurationHours.size ||
            freeDayMidSleepHours.any { !it.isFinite() } ||
            freeDaySleepDurationHours.any { !it.isFinite() || it <= 0.0 || it > 24.0 } ||
            !averageWorkdaySleepDurationHours.isFinite() ||
            averageWorkdaySleepDurationHours <= 0.0 ||
            averageWorkdaySleepDurationHours > 24.0 ||
            !averageWeekSleepDurationHours.isFinite() ||
            averageWeekSleepDurationHours <= 0.0 ||
            averageWeekSleepDurationHours > 24.0
        ) return null

        val midpoint = circularMedianHour(freeDayMidSleepHours) ?: return null
        val freeDuration = median(freeDaySleepDurationHours) ?: return null
        val correction = if (freeDuration > averageWorkdaySleepDurationHours) {
            max(0.0, (freeDuration - averageWeekSleepDurationHours) / 2.0)
        } else {
            0.0
        }
        return CorrectedMidSleepResult(
            freeDayMidSleepHour = midpoint,
            correctedMidSleepHour = wrap24(midpoint - correction),
            medianFreeDaySleepDurationHours = freeDuration,
            averageWorkdaySleepDurationHours = averageWorkdaySleepDurationHours,
            averageWeekSleepDurationHours = averageWeekSleepDurationHours,
            oversleepCorrectionHours = correction,
            freeDayNights = freeDayMidSleepHours.size,
        )
    }

    // Circular helpers

    internal fun circularMeanHour(hours: List<Double>): Double? {
        if (hours.isEmpty() || hours.any { !it.isFinite() }) return null
        var sx = 0.0
        var sy = 0.0
        for (hour in hours) {
            val angle = wrap24(hour) * PI / 12.0
            sx += cos(angle)
            sy += sin(angle)
        }
        if (sqrt(sx * sx + sy * sy) < CIRCULAR_RESULTANT_EPSILON) return null
        return wrap24(atan2(sy, sx) * 12.0 / PI)
    }

    internal fun circularMedianHour(hours: List<Double>): Double? {
        val anchor = circularMeanHour(hours) ?: return null
        val unwrapped = hours.map { anchor + signedCircularDifference(it, anchor) }
        return median(unwrapped)?.let(::wrap24)
    }

    /** Shortest signed arc a - b in (-12, +12]. */
    internal fun signedCircularDifference(a: Double, b: Double): Double {
        var d = (a - b) % 24.0
        if (d < 0.0) d += 24.0
        if (d > 12.0) d -= 24.0
        return d
    }

    internal fun wrap24(hour: Double): Double {
        var h = hour % 24.0
        if (h < 0.0) h += 24.0
        return h
    }

    private fun median(values: List<Double>): Double? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 0) {
            (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            sorted[mid]
        }
    }
}
