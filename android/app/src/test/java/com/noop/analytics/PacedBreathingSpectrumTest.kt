package com.noop.analytics

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirror of PacedBreathingSpectrumTests.swift. */
class PacedBreathingSpectrumTest {
    private fun syntheticRR(seconds: Double, components: List<Pair<Double, Double>>): List<Double> {
        val out = ArrayList<Double>()
        var t = 0.0
        while (t < seconds) {
            var rr = 1_000.0
            for ((hz, amplitudeMs) in components) {
                rr += amplitudeMs * sin(2.0 * PI * hz * t)
            }
            out.add(rr)
            t += rr / 1_000.0
        }
        return out
    }

    @Test fun singleSixBreathsPerMinuteRhythmFindsExpectedPeak() {
        val rr = syntheticRR(180.0, listOf(0.10 to 80.0))
        val result = PacedBreathingSpectrum.evaluate(rr, targetBreathsPerMinute = 6.0)!!

        assertEquals(0.10, result.peakHz, 0.004)
        assertEquals(6.0, result.peakBreathsPerMinute, 0.24)
        assertTrue(result.paceErrorBreathsPerMinute!! < 0.25)
        assertTrue(result.peakPowerFraction > 0.20)
        assertTrue(result.totalBandPower > 0.0)
        assertTrue(result.peakBandPower > 0.0)
        assertEquals(rr.sum() / 1_000.0, result.spanSeconds, 1e-12)
        assertEquals(rr.size, result.beatCount)
    }

    @Test fun targetContextDoesNotMoveSpectrum() {
        val rr = syntheticRR(180.0, listOf(0.10 to 80.0))
        val plain = PacedBreathingSpectrum.evaluate(rr)!!
        val targeted = PacedBreathingSpectrum.evaluate(rr, targetBreathsPerMinute = 6.0)!!

        assertEquals(plain.peakHz, targeted.peakHz, 1e-12)
        assertEquals(plain.peakBandPower, targeted.peakBandPower, 1e-12)
        assertEquals(plain.totalBandPower, targeted.totalBandPower, 1e-12)
        assertEquals(plain.peakPowerFraction, targeted.peakPowerFraction, 1e-12)
        assertNull(plain.targetBreathsPerMinute)
        assertNull(plain.paceErrorBreathsPerMinute)
    }

    @Test fun twoFrequencySignalIsLessConcentratedThanSinglePeak() {
        val single = syntheticRR(180.0, listOf(0.10 to 80.0))
        val mixed = syntheticRR(180.0, listOf(0.10 to 60.0, 0.20 to 60.0))
        val singleResult = PacedBreathingSpectrum.evaluate(single)!!
        val mixedResult = PacedBreathingSpectrum.evaluate(mixed)!!

        assertTrue(singleResult.peakPowerFraction > mixedResult.peakPowerFraction)
    }

    @Test fun offPaceTargetReportsAbsoluteErrorOnly() {
        val rr = syntheticRR(180.0, listOf(0.10 to 80.0))
        val result = PacedBreathingSpectrum.evaluate(rr, targetBreathsPerMinute = 5.0)!!
        assertEquals(5.0, result.targetBreathsPerMinute!!, 0.0)
        assertEquals(abs(result.peakBreathsPerMinute - 5.0), result.paceErrorBreathsPerMinute!!, 1e-12)
    }

    @Test fun shortConstantDirtyAndInvalidTargetFailClosed() {
        val short = syntheticRR(50.0, listOf(0.10 to 80.0))
        assertNull(PacedBreathingSpectrum.evaluate(short))
        assertNull(PacedBreathingSpectrum.evaluate(List(180) { 1_000.0 }))

        val dirty = syntheticRR(180.0, listOf(0.10 to 80.0)).toMutableList()
        dirty[5] = Double.NaN
        assertNull(PacedBreathingSpectrum.evaluate(dirty))

        val outOfRange = syntheticRR(180.0, listOf(0.10 to 80.0)).toMutableList()
        outOfRange[5] = 250.0
        assertNull(PacedBreathingSpectrum.evaluate(outOfRange))

        val valid = syntheticRR(180.0, listOf(0.10 to 80.0))
        assertNull(PacedBreathingSpectrum.evaluate(valid, targetBreathsPerMinute = 0.0))
        assertNull(PacedBreathingSpectrum.evaluate(valid, targetBreathsPerMinute = 20.0))
    }
}
