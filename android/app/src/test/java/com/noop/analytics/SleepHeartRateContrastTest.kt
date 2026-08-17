package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** Mirror of SleepHeartRateContrastTests.swift. */
class SleepHeartRateContrastTest {

    @Test fun lowerSleepHRProducesPositiveReduction() {
        val wake: List<Double?> = List(60) { 70.0 }
        val sleep: List<Double?> = List(60) { 60.0 }
        val result = SleepHeartRateContrast.evaluate(wake, sleep)!!

        assertEquals(70.0, result.wakeMeanBpm, 1e-12)
        assertEquals(60.0, result.sleepMeanBpm, 1e-12)
        assertEquals(-10.0, result.sleepMinusWakeBpm, 1e-12)
        assertEquals(100.0 / 7.0, result.sleepReductionPercent, 1e-12)
        assertEquals(1.0, result.wakeCoverage, 1e-12)
        assertEquals(1.0, result.sleepCoverage, 1e-12)
    }

    @Test fun higherSleepHRProducesNegativeReductionWithoutClassification() {
        val wake: List<Double?> = List(40) { 60.0 }
        val sleep: List<Double?> = List(40) { 66.0 }
        val result = SleepHeartRateContrast.evaluate(wake, sleep)!!

        assertEquals(6.0, result.sleepMinusWakeBpm, 1e-12)
        assertEquals(-10.0, result.sleepReductionPercent, 1e-12)
    }

    @Test fun missingAndInvalidEpochsAreExcludedAndReduceCoverage() {
        val wake: MutableList<Double?> = MutableList(40) { 70.0 }
        val sleep: MutableList<Double?> = MutableList(40) { 60.0 }
        wake[0] = null
        wake[1] = 29.0
        wake[2] = 221.0
        wake[3] = Double.NaN
        sleep[0] = null
        sleep[1] = 10.0
        sleep[2] = 500.0
        sleep[3] = Double.POSITIVE_INFINITY

        val result = SleepHeartRateContrast.evaluate(wake, sleep, minimumValidSamples = 30)!!
        assertEquals(36, result.wakeValidSamples)
        assertEquals(36, result.sleepValidSamples)
        assertEquals(0.9, result.wakeCoverage, 1e-12)
        assertEquals(0.9, result.sleepCoverage, 1e-12)
        assertEquals(70.0, result.wakeMeanBpm, 1e-12)
        assertEquals(60.0, result.sleepMeanBpm, 1e-12)
    }

    @Test fun validityRangeEdgesAreIncluded() {
        val wake: List<Double?> = List(30) { 30.0 }
        val sleep: List<Double?> = List(30) { 220.0 }
        val result = SleepHeartRateContrast.evaluate(wake, sleep)!!
        assertEquals(30.0, result.wakeMeanBpm, 1e-12)
        assertEquals(220.0, result.sleepMeanBpm, 1e-12)
    }

    @Test fun minimumValidSampleGateAppliesIndependentlyToBothWindows() {
        val enough: List<Double?> = List(30) { 60.0 }
        val short: List<Double?> = List(29) { 60.0 }
        assertNull(SleepHeartRateContrast.evaluate(short, enough))
        assertNull(SleepHeartRateContrast.evaluate(enough, short))
        assertNotNull(SleepHeartRateContrast.evaluate(short, short, minimumValidSamples = 29))
    }

    @Test fun emptyAndInvalidConfigurationFailClosed() {
        val enough: List<Double?> = List(30) { 60.0 }
        assertNull(SleepHeartRateContrast.evaluate(emptyList(), enough))
        assertNull(SleepHeartRateContrast.evaluate(enough, emptyList()))
        assertNull(SleepHeartRateContrast.evaluate(enough, enough, minimumValidSamples = 0))
    }

    @Test fun unequalWindowLengthsAreAllowedAndCoverageIsPerWindow() {
        val wake: MutableList<Double?> = MutableList(120) { 72.0 }
        val sleep: MutableList<Double?> = MutableList(60) { 60.0 }
        for (i in 0 until 30) wake[i] = null
        for (i in 0 until 15) sleep[i] = null

        val result = SleepHeartRateContrast.evaluate(wake, sleep)!!
        assertEquals(90, result.wakeValidSamples)
        assertEquals(120, result.wakeTotalSamples)
        assertEquals(0.75, result.wakeCoverage, 1e-12)
        assertEquals(45, result.sleepValidSamples)
        assertEquals(60, result.sleepTotalSamples)
        assertEquals(0.75, result.sleepCoverage, 1e-12)
    }
}
