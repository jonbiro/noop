package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Mirror of CircadianRegularityEngineTests.swift. Identical fixtures are the parity guard. */
class CircadianRegularityEngineTest {

    // Sleep Regularity Index

    @Test fun sriPerfectRepeatedDayIs100() {
        val day = (0 until 24).map { hour -> hour < 7 || hour >= 23 }
        val full = day + day
        val states: List<Boolean?> = List(full.size) { full[it] }
        val result = CircadianRegularityEngine.sleepRegularityIndex(states, epochSeconds = 3_600)!!

        assertEquals(100.0, result.score, 1e-12)
        assertEquals(24, result.comparablePairs)
        assertEquals(24, result.possiblePairs)
        assertEquals(1.0, result.coverage, 1e-12)
        assertEquals(24, result.matchingPairs)
        assertEquals(2.0, result.spanDays, 1e-12)
    }

    @Test fun sriOppositeSecondDayIsMinus100() {
        val day = (0 until 24).map { hour -> hour < 7 || hour >= 23 }
        val full = day + day.map { !it }
        val states: List<Boolean?> = List(full.size) { full[it] }
        val result = CircadianRegularityEngine.sleepRegularityIndex(states, epochSeconds = 3_600)!!

        assertEquals(-100.0, result.score, 1e-12)
        assertEquals(0, result.matchingPairs)
        assertEquals(24, result.comparablePairs)
    }

    @Test fun sriHalfAgreementIsZero() {
        val first = List(24) { false }
        val second = List(12) { false } + List(12) { true }
        val full = first + second
        val states: List<Boolean?> = List(full.size) { full[it] }
        val result = CircadianRegularityEngine.sleepRegularityIndex(states, epochSeconds = 3_600)!!
        assertEquals(12, result.matchingPairs)
        assertEquals(0.0, result.score, 1e-12)
    }

    @Test fun sriMissingEpochReducesCoverageWithoutBecomingWake() {
        val day = (0 until 24).map { hour -> hour < 7 || hour >= 23 }
        val full = day + day
        val states: MutableList<Boolean?> = MutableList(full.size) { full[it] }
        states[2] = null
        states[26] = null

        val result = CircadianRegularityEngine.sleepRegularityIndex(states, epochSeconds = 3_600)!!
        assertEquals(100.0, result.score, 1e-12)
        assertEquals(23, result.comparablePairs)
        assertEquals(24, result.possiblePairs)
        assertEquals(23.0 / 24.0, result.coverage, 1e-12)
    }

    @Test fun sriRejectsTooShortOrInvalidGrid() {
        val oneDay: List<Boolean?> = List(24) { false }
        assertNull(CircadianRegularityEngine.sleepRegularityIndex(oneDay, epochSeconds = 3_600))
        assertNull(CircadianRegularityEngine.sleepRegularityIndex(oneDay + oneDay, epochSeconds = 0))
        assertNull(CircadianRegularityEngine.sleepRegularityIndex(
            oneDay + oneDay, epochSeconds = 3_600, lagSeconds = 1_000))
    }

    @Test fun sriRejectsSpanWithNoComparablePairs() {
        val states: MutableList<Boolean?> = MutableList(48) { null }
        states[0] = true
        assertNull(CircadianRegularityEngine.sleepRegularityIndex(states, epochSeconds = 3_600))
    }

    // Circular social jetlag

    @Test fun socialJetLagWrapsAcrossMidnight() {
        val result = CircadianRegularityEngine.socialJetLag(
            freeDayMidSleepHours = listOf(1.0, 1.0),
            workdayMidSleepHours = listOf(23.5, 23.5),
        )!!
        assertEquals(1.0, result.freeDayMidSleepHour, 1e-12)
        assertEquals(23.5, result.workdayMidSleepHour, 1e-12)
        assertEquals(1.5, result.signedHours, 1e-12)
        assertEquals(1.5, result.absoluteHours, 1e-12)
    }

    @Test fun socialJetLagPreservesEarlierFreeDayDirection() {
        val result = CircadianRegularityEngine.socialJetLag(
            freeDayMidSleepHours = listOf(23.0, 23.0),
            workdayMidSleepHours = listOf(1.0, 1.0),
        )!!
        assertEquals(-2.0, result.signedHours, 1e-12)
        assertEquals(2.0, result.absoluteHours, 1e-12)
    }

    @Test fun circularMedianHandlesMidnight() {
        val midpoint = CircadianRegularityEngine.circularMedianHour(listOf(23.5, 0.5))!!
        assertEquals(0.0, midpoint, 1e-12)
    }

    @Test fun socialJetLagRejectsInsufficientOrDegenerateSamples() {
        assertNull(CircadianRegularityEngine.socialJetLag(
            freeDayMidSleepHours = listOf(1.0),
            workdayMidSleepHours = listOf(23.0, 23.0),
        ))
        assertNull(CircadianRegularityEngine.socialJetLag(
            freeDayMidSleepHours = listOf(0.0, 12.0),
            workdayMidSleepHours = listOf(6.0, 6.0),
        ))
        assertNull(CircadianRegularityEngine.socialJetLag(
            freeDayMidSleepHours = listOf(Double.NaN, 1.0),
            workdayMidSleepHours = listOf(23.0, 23.0),
        ))
    }

    // Sleep-debt-corrected free-day midpoint

    @Test fun correctedMidSleepAppliesHalfOversleepCorrection() {
        val result = CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours = listOf(4.0, 4.0),
            freeDaySleepDurationHours = listOf(9.0, 9.0),
            averageWorkdaySleepDurationHours = 7.5,
            averageWeekSleepDurationHours = 8.0,
        )!!
        assertEquals(4.0, result.freeDayMidSleepHour, 1e-12)
        assertEquals(9.0, result.medianFreeDaySleepDurationHours, 1e-12)
        assertEquals(7.5, result.averageWorkdaySleepDurationHours, 1e-12)
        assertEquals(0.5, result.oversleepCorrectionHours, 1e-12)
        assertEquals(3.5, result.correctedMidSleepHour, 1e-12)
    }

    @Test fun correctedMidSleepDoesNotCorrectWhenFreeSleepDoesNotExceedWorkSleep() {
        val result = CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours = listOf(4.0, 4.0),
            freeDaySleepDurationHours = listOf(8.5, 8.5),
            averageWorkdaySleepDurationHours = 9.0,
            averageWeekSleepDurationHours = 8.0,
        )!!
        assertEquals(0.0, result.oversleepCorrectionHours, 1e-12)
        assertEquals(4.0, result.correctedMidSleepHour, 1e-12)
    }

    @Test fun correctedMidSleepUsesCircularMidpointAcrossMidnight() {
        val result = CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours = listOf(23.5, 0.5),
            freeDaySleepDurationHours = listOf(8.0, 8.0),
            averageWorkdaySleepDurationHours = 8.0,
            averageWeekSleepDurationHours = 8.0,
        )!!
        assertEquals(0.0, result.freeDayMidSleepHour, 1e-12)
        assertEquals(0.0, result.correctedMidSleepHour, 1e-12)
    }

    @Test fun correctedMidSleepFailsClosedOnInvalidInput() {
        assertNull(CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours = listOf(4.0, 4.0),
            freeDaySleepDurationHours = listOf(8.0),
            averageWorkdaySleepDurationHours = 7.5,
            averageWeekSleepDurationHours = 8.0,
        ))
        assertNull(CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours = listOf(4.0, 4.0),
            freeDaySleepDurationHours = listOf(8.0, 25.0),
            averageWorkdaySleepDurationHours = 7.5,
            averageWeekSleepDurationHours = 8.0,
        ))
        assertNull(CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours = listOf(4.0, 4.0),
            freeDaySleepDurationHours = listOf(8.0, 8.0),
            averageWorkdaySleepDurationHours = Double.POSITIVE_INFINITY,
            averageWeekSleepDurationHours = 8.0,
        ))
        assertNull(CircadianRegularityEngine.correctedFreeDayMidSleep(
            freeDayMidSleepHours = listOf(4.0, 4.0),
            freeDaySleepDurationHours = listOf(8.0, 8.0),
            averageWorkdaySleepDurationHours = 7.5,
            averageWeekSleepDurationHours = Double.POSITIVE_INFINITY,
        ))
    }
}
