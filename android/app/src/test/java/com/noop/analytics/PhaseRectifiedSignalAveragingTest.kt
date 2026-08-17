package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** Mirror of PhaseRectifiedSignalAveragingTests.swift. */
class PhaseRectifiedSignalAveragingTest {
    @Test fun linearIncreasingRRHasExactPositiveDecelerationCapacity() {
        val rr = listOf(900.0, 920.0, 940.0, 960.0, 980.0, 1000.0, 1020.0, 1040.0, 1060.0)
        val r = PhaseRectifiedSignalAveraging.decelerationCapacity(rr)!!
        assertEquals(20.0, r.capacityMs, 1e-12)
        assertEquals(listOf(940.0, 960.0, 980.0, 1000.0), r.profileMs)
        assertEquals(5, r.anchorCount)
        assertEquals(0, r.rejectedLargeChangeAnchors)
    }

    @Test fun linearDecreasingRRHasExactNegativeAccelerationCapacity() {
        val rr = listOf(1060.0, 1040.0, 1020.0, 1000.0, 980.0, 960.0, 940.0, 920.0, 900.0)
        val r = PhaseRectifiedSignalAveraging.accelerationCapacity(rr)!!
        assertEquals(-20.0, r.capacityMs, 1e-12)
        assertEquals(listOf(1020.0, 1000.0, 980.0, 960.0), r.profileMs)
        assertEquals(5, r.anchorCount)
    }

    @Test fun oppositeKindHasNoAnchors() {
        val rr = listOf(900.0, 920.0, 940.0, 960.0, 980.0, 1000.0, 1020.0, 1040.0, 1060.0)
        assertNull(PhaseRectifiedSignalAveraging.accelerationCapacity(rr))
    }

    @Test fun largeDirectionalJumpIsRejectedAsAnchor() {
        val rr = listOf(900.0, 920.0, 940.0, 1060.0, 1080.0, 1100.0, 1120.0, 1140.0, 1160.0)
        val r = PhaseRectifiedSignalAveraging.decelerationCapacity(rr)!!
        assertEquals(4, r.anchorCount)
        assertEquals(1, r.rejectedLargeChangeAnchors)
    }

    @Test fun customAnchorCapAndMinimumAnchorGate() {
        val rr = listOf(900.0, 920.0, 940.0, 960.0, 980.0, 1000.0, 1020.0, 1040.0, 1060.0)
        assertNull(PhaseRectifiedSignalAveraging.decelerationCapacity(rr, anchorRatioCap = 0.01))
        assertNotNull(PhaseRectifiedSignalAveraging.decelerationCapacity(rr, minimumAnchors = 5))
        assertNull(PhaseRectifiedSignalAveraging.decelerationCapacity(rr, minimumAnchors = 6))
    }

    @Test fun largerRadiusPreservesCentralHaarCapacity() {
        val rr = listOf(860.0, 880.0, 900.0, 920.0, 940.0, 960.0, 980.0, 1000.0, 1020.0, 1040.0, 1060.0, 1080.0)
        val r = PhaseRectifiedSignalAveraging.decelerationCapacity(rr, radius = 3)!!
        assertEquals(20.0, r.capacityMs, 1e-12)
        assertEquals(6, r.profileMs.size)
    }

    @Test fun invalidConfigurationAndDirtyNNFailClosed() {
        val valid = listOf(900.0, 920.0, 940.0, 960.0, 980.0, 1000.0)
        assertNull(PhaseRectifiedSignalAveraging.decelerationCapacity(valid, radius = 1))
        assertNull(PhaseRectifiedSignalAveraging.decelerationCapacity(valid, anchorRatioCap = -0.1))
        assertNull(PhaseRectifiedSignalAveraging.decelerationCapacity(valid, minimumAnchors = 0))
        assertNull(PhaseRectifiedSignalAveraging.decelerationCapacity(listOf(900.0, 920.0, Double.NaN, 960.0, 980.0)))
        assertNull(PhaseRectifiedSignalAveraging.decelerationCapacity(listOf(900.0, 920.0, 0.0, 960.0, 980.0)))
        assertNull(PhaseRectifiedSignalAveraging.decelerationCapacity(listOf(900.0, 920.0, 940.0, 960.0)))
    }
}
