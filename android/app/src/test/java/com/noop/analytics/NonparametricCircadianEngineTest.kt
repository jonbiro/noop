package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Mirror of NonparametricCircadianEngineTests.swift. */
class NonparametricCircadianEngineTest {

    private fun optionalize(values: List<Double>): List<Double?> = values.map { it }

    private fun stepDay(): List<Double> = List(12) { 0.0 } + List(12) { 10.0 }

    @Test fun repeatedStepRhythmPinsStandardMetrics() {
        val day = stepDay()
        val result = NonparametricCircadianEngine.evaluate(
            optionalize(day + day), epochsPerDay = 24
        )!!

        assertEquals(1.0, result.interdailyStability, 1e-12)
        assertEquals(48.0 * 300.0 / (47.0 * 1_200.0), result.intradailyVariability, 1e-12)
        assertEquals(10.0, result.m10, 1e-12)
        assertEquals(0.0, result.l5, 1e-12)
        assertEquals(1.0, result.relativeAmplitude, 1e-12)
        assertEquals(12, result.m10StartEpoch)
        assertEquals(0, result.l5StartEpoch)
        assertEquals(12.0, result.m10StartHour, 1e-12)
        assertEquals(0.0, result.l5StartHour, 1e-12)
        assertEquals(2, result.daysObserved)
        assertEquals(24, result.epochsPerDay)
    }

    @Test fun circularM10CanCrossMidnight() {
        val day = MutableList(24) { 1.0 }
        for (hour in listOf(20, 21, 22, 23, 0, 1, 2, 3, 4, 5)) day[hour] = 10.0
        val result = NonparametricCircadianEngine.evaluate(
            optionalize(day + day), epochsPerDay = 24
        )!!

        assertEquals(10.0, result.m10, 1e-12)
        assertEquals(20, result.m10StartEpoch)
        assertEquals(20.0, result.m10StartHour, 1e-12)
        assertEquals(1.0, result.l5, 1e-12)
        assertEquals(6, result.l5StartEpoch)
        assertEquals(9.0 / 11.0, result.relativeAmplitude, 1e-12)
    }

    @Test fun quarterHourGridUsesExactFiveAndTenHourWindows() {
        val day = MutableList(96) { 2.0 }
        for (i in 4 until 24) day[i] = 0.5
        for (i in 32 until 72) day[i] = 8.0
        val result = NonparametricCircadianEngine.evaluate(
            optionalize(day + day), epochsPerDay = 96
        )!!

        assertEquals(0.5, result.l5, 1e-12)
        assertEquals(4, result.l5StartEpoch)
        assertEquals(1.0, result.l5StartHour, 1e-12)
        assertEquals(8.0, result.m10, 1e-12)
        assertEquals(32, result.m10StartEpoch)
        assertEquals(8.0, result.m10StartHour, 1e-12)
    }

    @Test fun daysObservedReportsHistoryWithoutInventingMaturityTier() {
        val day = stepDay()
        val signal = optionalize(List(7) { day }.flatten())
        val result = NonparametricCircadianEngine.evaluate(signal, epochsPerDay = 24)!!

        assertEquals(7, result.daysObserved)
        assertEquals(1.0, result.interdailyStability, 1e-12)
        assertEquals(10.0, result.m10, 1e-12)
        assertEquals(0.0, result.l5, 1e-12)
        assertEquals(1.0, result.relativeAmplitude, 1e-12)
    }

    @Test fun oneDayAndPartialDaysFailClosed() {
        val day = optionalize(stepDay())
        assertNull(NonparametricCircadianEngine.evaluate(day, epochsPerDay = 24))
        assertNull(NonparametricCircadianEngine.evaluate(day + day + listOf(1.0), epochsPerDay = 24))
    }

    @Test fun epochGridMustDivideDayIntoWholeHours() {
        val signal: List<Double?> = List(100) { 1.0 }
        assertNull(NonparametricCircadianEngine.evaluate(signal, epochsPerDay = 50))
        assertNull(NonparametricCircadianEngine.evaluate(signal, epochsPerDay = 0))
    }

    @Test fun missingNonFiniteNegativeAndConstantSignalsFailClosed() {
        val missing = optionalize(stepDay() + stepDay()).toMutableList()
        missing[5] = null
        assertNull(NonparametricCircadianEngine.evaluate(missing, epochsPerDay = 24))

        val nonFinite = optionalize(stepDay() + stepDay()).toMutableList()
        nonFinite[5] = Double.NaN
        assertNull(NonparametricCircadianEngine.evaluate(nonFinite, epochsPerDay = 24))

        val negative = optionalize(stepDay() + stepDay()).toMutableList()
        negative[5] = -1.0
        assertNull(NonparametricCircadianEngine.evaluate(negative, epochsPerDay = 24))

        val constant: List<Double?> = List(48) { 5.0 }
        assertNull(NonparametricCircadianEngine.evaluate(constant, epochsPerDay = 24))
    }
}
