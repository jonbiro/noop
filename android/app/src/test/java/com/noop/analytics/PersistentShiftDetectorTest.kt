package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PersistentShiftDetectorTest {
    private val baseline = listOf(99.0, 100.0, 101.0, 99.0, 100.0, 101.0, 100.0)

    @Test fun upperShiftProgressesNormalWatchSustainedThenRecovers() {
        val values: List<Double?> = (baseline + listOf(106.0, 106.0, 106.0, 100.0, 100.0)).map { it }
        val r = PersistentShiftDetector.evaluate(values, PersistentShiftDetector.Direction.UPPER)!!
        assertEquals(PersistentShiftDetector.State.CALIBRATING, r[6].state)
        assertEquals(PersistentShiftDetector.State.NORMAL, r[7].state)
        assertEquals(PersistentShiftDetector.State.WATCH, r[8].state)
        assertEquals(PersistentShiftDetector.State.SUSTAINED, r[9].state)
        assertEquals(PersistentShiftDetector.State.SUSTAINED, r[10].state)
        assertEquals(PersistentShiftDetector.State.NORMAL, r[11].state)
        assertEquals(0.0, r[11].cusum!!, 1e-12)
        assertEquals(100.0, r[7].baselineMedian!!, 1e-12)
        assertEquals(PersistentShiftDetector.NORMALIZED_MAD_SCALE, r[7].baselineScale!!, 1e-12)
        assertEquals(6.0 / PersistentShiftDetector.NORMALIZED_MAD_SCALE, r[7].orientedZ!!, 1e-12)
    }

    @Test fun lowerDirectionOrientsDropAsPositive() {
        val values: List<Double?> = (baseline + listOf(94.0, 94.0, 94.0)).map { it }
        val r = PersistentShiftDetector.evaluate(values, PersistentShiftDetector.Direction.LOWER)!!
        assertTrue(r[7].orientedZ!! > 0.0)
        assertEquals(PersistentShiftDetector.State.WATCH, r[8].state)
        assertEquals(PersistentShiftDetector.State.SUSTAINED, r[9].state)
    }

    @Test fun missingObservationDoesNotResetState() {
        val values: List<Double?> = baseline.map { it } + listOf(106.0, 106.0, null, 106.0)
        val r = PersistentShiftDetector.evaluate(values, PersistentShiftDetector.Direction.UPPER)!!
        assertEquals(PersistentShiftDetector.State.WATCH, r[8].state)
        assertEquals(PersistentShiftDetector.State.MISSING, r[9].state)
        assertFalse(r[9].observed)
        assertNull(r[9].cusum)
        assertEquals(PersistentShiftDetector.State.SUSTAINED, r[10].state)
    }

    @Test fun degenerateBaselineAbstains() {
        val values: List<Double?> = List(7) { 100.0 } + listOf(105.0)
        val r = PersistentShiftDetector.evaluate(values, PersistentShiftDetector.Direction.UPPER)!!
        assertEquals(PersistentShiftDetector.State.DEGENERATE_BASELINE, r[7].state)
        assertNull(r[7].baselineScale)
        assertNull(r[7].orientedZ)
    }

    @Test fun sampleSDFallbackHandlesZeroMAD() {
        val values: List<Double?> = listOf(100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 101.0, 105.0)
        val r = PersistentShiftDetector.evaluate(values, PersistentShiftDetector.Direction.UPPER)!!
        assertEquals(PersistentShiftDetector.State.WATCH, r[7].state)
        assertNotNull(r[7].baselineScale)
        assertTrue(r[7].baselineScale!! > 0.0)
    }

    @Test fun baselineCountsOnlyPriorObservedValues() {
        val values: List<Double?> = listOf(99.0, null, 100.0, 101.0, 99.0, 100.0, 101.0, 100.0, 106.0)
        val r = PersistentShiftDetector.evaluate(values, PersistentShiftDetector.Direction.UPPER, minimumBaseline = 7)!!
        assertEquals(6, r[7].baselineCount)
        assertEquals(7, r[8].baselineCount)
        assertNotNull(r[8].orientedZ)
    }

    @Test fun customThresholdsAreConfigurable() {
        val values: List<Double?> = (baseline + listOf(104.0, 104.0)).map { it }
        val normal = PersistentShiftDetector.evaluate(values, PersistentShiftDetector.Direction.UPPER)!!
        val sensitive = PersistentShiftDetector.evaluate(values, PersistentShiftDetector.Direction.UPPER,
            referenceK = 0.0, decisionH = 1.0, persistObservations = 1)!!
        assertEquals(PersistentShiftDetector.State.NORMAL, normal[7].state)
        assertEquals(PersistentShiftDetector.State.SUSTAINED, sensitive[7].state)
    }

    @Test fun invalidConfigurationOrNonFiniteInputFails() {
        val values: List<Double?> = baseline.map { it }
        assertNull(PersistentShiftDetector.evaluate(values, PersistentShiftDetector.Direction.UPPER, baselineWindow = 6, minimumBaseline = 7))
        assertNull(PersistentShiftDetector.evaluate(values, PersistentShiftDetector.Direction.UPPER, minimumBaseline = 1))
        assertNull(PersistentShiftDetector.evaluate(values, PersistentShiftDetector.Direction.UPPER, referenceK = -1.0))
        assertNull(PersistentShiftDetector.evaluate(values, PersistentShiftDetector.Direction.UPPER, decisionH = 0.0))
        assertNull(PersistentShiftDetector.evaluate(values + listOf(Double.NaN), PersistentShiftDetector.Direction.UPPER))
    }
}
