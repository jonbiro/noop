package com.noop.analytics

import kotlin.math.max
import kotlin.math.min

/*
 * NonparametricCircadianEngine.kt - fixed-grid circadian rhythm descriptors.
 * Behavioral twin of StrandAnalytics/NonparametricCircadianEngine.swift.
 *
 * Additive to CircadianEngine and CircadianRegularityEngine. This engine does
 * not change phase estimation, sleep staging, Vitality, Readiness, or any
 * headline score.
 *
 * Implements:
 *   - IS: interdaily stability
 *   - IV: intradaily variability
 *   - M10: most-active contiguous 10 h mean of the average day
 *   - L5: least-active contiguous 5 h mean of the average day
 *   - RA: (M10 - L5) / (M10 + L5)
 *
 * The strongest validation literature is for actigraphy/activity. Callers that
 * use heart rate must label that substrate honestly rather than presenting it
 * as actigraphy-equivalent.
 */
object NonparametricCircadianEngine {

    const val MINIMUM_DAYS: Int = 2

    data class Result(
        val interdailyStability: Double,
        val intradailyVariability: Double,
        val m10: Double,
        val l5: Double,
        val relativeAmplitude: Double,
        val m10StartEpoch: Int,
        val l5StartEpoch: Int,
        val m10StartHour: Double,
        val l5StartHour: Double,
        /** Number of complete nominal days represented by the fixed grid. */
        val daysObserved: Int,
        val epochsPerDay: Int,
    )

    /**
     * Compute nonparametric circadian metrics over consecutive complete days.
     *
     * [signal] contains chronological epoch values; null means unobserved. This
     * first production primitive refuses to impute missing epochs because the
     * published IS/IV formulas assume a complete fixed grid.
     *
     * [epochsPerDay] must be divisible by 24 so the 5 h and 10 h windows are
     * exact integer epoch counts. Partial or DST-short/long local days must be
     * normalized by the caller onto a declared 24 h grid rather than silently
     * compressed here.
     *
     * Consumers decide how much history they require for a particular use.
     * This pure engine reports [Result.daysObserved] and does not invent an
     * "established" threshold.
     */
    fun evaluate(signal: List<Double?>, epochsPerDay: Int): Result? {
        if (epochsPerDay <= 0 ||
            epochsPerDay % 24 != 0 ||
            signal.size < MINIMUM_DAYS * epochsPerDay ||
            signal.size % epochsPerDay != 0
        ) return null

        val x = ArrayList<Double>(signal.size)
        for (item in signal) {
            if (item == null || !item.isFinite() || item < 0.0) return null
            x.add(item)
        }

        val n = x.size
        val days = n / epochsPerDay
        val grandMean = x.sum() / n.toDouble()

        var totalSS = 0.0
        for (value in x) {
            val d = value - grandMean
            totalSS += d * d
        }
        if (!totalSS.isFinite() || totalSS <= 0.0) return null

        val profile = DoubleArray(epochsPerDay)
        for (i in 0 until n) {
            profile[i % epochsPerDay] += x[i]
        }
        for (i in profile.indices) {
            profile[i] /= days.toDouble()
        }

        var profileSS = 0.0
        for (value in profile) {
            val d = value - grandMean
            profileSS += d * d
        }
        val rawIS = n.toDouble() * profileSS / (epochsPerDay.toDouble() * totalSS)
        val isValue = min(1.0, max(0.0, rawIS))

        var successiveSS = 0.0
        for (i in 1 until n) {
            val d = x[i] - x[i - 1]
            successiveSS += d * d
        }
        val ivValue = n.toDouble() * successiveSS / ((n - 1).toDouble() * totalSS)
        if (!ivValue.isFinite() || ivValue < 0.0) return null

        val m10Epochs = epochsPerDay * 10 / 24
        val l5Epochs = epochsPerDay * 5 / 24
        val m10Window = bestCircularWindow(profile, m10Epochs, maximize = true)
        val l5Window = bestCircularWindow(profile, l5Epochs, maximize = false)

        val denominator = m10Window.mean + l5Window.mean
        if (denominator <= 0.0) return null
        val rawRA = (m10Window.mean - l5Window.mean) / denominator
        val raValue = min(1.0, max(0.0, rawRA))
        val hoursPerEpoch = 24.0 / epochsPerDay.toDouble()

        return Result(
            interdailyStability = isValue,
            intradailyVariability = ivValue,
            m10 = m10Window.mean,
            l5 = l5Window.mean,
            relativeAmplitude = raValue,
            m10StartEpoch = m10Window.start,
            l5StartEpoch = l5Window.start,
            m10StartHour = m10Window.start.toDouble() * hoursPerEpoch,
            l5StartHour = l5Window.start.toDouble() * hoursPerEpoch,
            daysObserved = days,
            epochsPerDay = epochsPerDay,
        )
    }

    private data class Window(val mean: Double, val start: Int)

    /** Ties keep the earliest start epoch for deterministic parity. */
    private fun bestCircularWindow(profile: DoubleArray, length: Int, maximize: Boolean): Window {
        require(profile.isNotEmpty() && length > 0 && length <= profile.size)
        var bestMean: Double? = null
        var bestStart = 0
        for (start in profile.indices) {
            var sum = 0.0
            for (offset in 0 until length) {
                sum += profile[(start + offset) % profile.size]
            }
            val mean = sum / length.toDouble()
            if (bestMean == null || if (maximize) mean > bestMean else mean < bestMean) {
                bestMean = mean
                bestStart = start
            }
        }
        return Window(bestMean!!, bestStart)
    }
}
