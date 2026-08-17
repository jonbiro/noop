package com.noop.analytics

import com.noop.data.RrInterval
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RrOrderAuditTest {
    private fun row(ts: Long, rrMs: Int, seq: Int = 0, ord: Int?): RrInterval =
        RrInterval(deviceId = "d", ts = ts, rrMs = rrMs, seq = seq, ord = ord)

    @Test
    fun issueExampleShowsMagnitudeOrderBiasInRawRmssd() {
        val emission = listOf(812, 795, 840, 801, 833)
        val rows = emission.mapIndexed { index, value -> row(100, value, ord = index) }

        val report = RrOrderAudit.evaluate(rows)

        assertEquals(34.85, report.currentOrder.rawRmssdMs!!, 0.01)
        assertEquals(12.72, report.magnitudeOrderCounterfactual.rawRmssdMs!!, 0.01)
        assertTrue(report.rawRmssdCurrentMinusMagnitudeMs!! > 20.0)
        assertEquals(1, report.provenance.trustworthyMultiBeatSeconds)
        assertEquals(1, report.provenance.magnitudeReorderedTrustworthySeconds)
        assertNull(report.currentOrder.rmssdMs)
        assertNull(report.magnitudeOrderCounterfactual.rmssdMs)
    }

    @Test
    fun productionPipelineCounterfactualUsesTwentyBeatGateAndCleaning() {
        val emission = listOf(812, 795, 840, 801, 833)
        val rows = (0 until 4).flatMap { second ->
            emission.mapIndexed { index, value -> row(1_000L + second, value, ord = index) }
        }

        val report = RrOrderAudit.evaluate(rows)

        assertEquals(20, report.currentOrder.nInput)
        assertEquals(20, report.currentOrder.nClean)
        assertNotNull(report.currentOrder.rmssdMs)
        assertNotNull(report.magnitudeOrderCounterfactual.rmssdMs)
        assertTrue(report.currentOrder.rmssdMs!! > report.magnitudeOrderCounterfactual.rmssdMs!!)
        assertTrue(report.rmssdCurrentMinusMagnitudeMs!! > 10.0)
        assertEquals(4, report.provenance.trustworthyMultiBeatSeconds)
        assertTrue(report.provenance.hasCompleteSameSecondOrder)
    }

    @Test
    fun provenancePartitionsEveryMultiBeatSecond() {
        val rows = listOf(
            row(1, 800, ord = null),
            row(2, 812, ord = 2), row(2, 795, ord = 7),
            row(3, 801, ord = null), row(3, 833, ord = null),
            row(4, 802, ord = null), row(4, 834, ord = 0),
            row(5, 803, ord = 0), row(5, 835, ord = 0),
        )

        val p = RrOrderAudit.evaluate(rows).provenance

        assertEquals(9, p.totalIntervals)
        assertEquals(5, p.intervalsWithRecordedOrder)
        assertEquals(4, p.intervalsWithUnknownOrder)
        assertEquals(1, p.singleBeatSeconds)
        assertEquals(4, p.multiBeatSeconds)
        assertEquals(8, p.multiBeatIntervals)
        assertEquals(1, p.trustworthyMultiBeatSeconds)
        assertEquals(2, p.trustworthyMultiBeatIntervals)
        assertEquals(1, p.allUnknownMultiBeatSeconds)
        assertEquals(2, p.allUnknownMultiBeatIntervals)
        assertEquals(1, p.mixedOrderMultiBeatSeconds)
        assertEquals(2, p.mixedOrderMultiBeatIntervals)
        assertEquals(1, p.ambiguousRecordedOrderMultiBeatSeconds)
        assertEquals(2, p.ambiguousRecordedOrderMultiBeatIntervals)
        assertEquals(1, p.magnitudeReorderedTrustworthySeconds)
        assertEquals(2, p.magnitudeReorderedTrustworthyIntervals)
        assertEquals(5.0 / 9.0, p.recordedOrderFraction!!, 1e-12)
        assertEquals(0.25, p.trustworthyMultiBeatIntervalFraction!!, 1e-12)
        assertFalse(p.hasCompleteSameSecondOrder)
    }

    @Test
    fun inputOrderDoesNotChangeReport() {
        val rows = listOf(
            row(11, 840, ord = 2),
            row(10, 812, ord = 0),
            row(11, 795, ord = 0),
            row(10, 801, ord = 1),
            row(11, 833, ord = 1),
        )
        assertEquals(RrOrderAudit.evaluate(rows), RrOrderAudit.evaluate(rows.reversed()))
    }

    @Test
    fun equalValuesDoNotCountAsMagnitudeAffected() {
        val rows = listOf(
            row(20, 812, seq = 0, ord = 1),
            row(20, 812, seq = 1, ord = 0),
        )
        val p = RrOrderAudit.evaluate(rows).provenance
        assertEquals(1, p.trustworthyMultiBeatSeconds)
        assertEquals(0, p.magnitudeReorderedTrustworthySeconds)
        assertEquals(0, p.magnitudeReorderedTrustworthyIntervals)
    }

    @Test
    fun emptyAuditHasNoFractionsOrHrv() {
        val report = RrOrderAudit.evaluate(emptyList())
        assertEquals(0, report.provenance.totalIntervals)
        assertNull(report.provenance.recordedOrderFraction)
        assertNull(report.provenance.trustworthyMultiBeatIntervalFraction)
        assertTrue(report.provenance.hasCompleteSameSecondOrder)
        assertNull(report.currentOrder.rawRmssdMs)
        assertNull(report.currentOrder.rmssdMs)
        assertNull(report.rawRmssdCurrentMinusMagnitudeMs)
    }
}
