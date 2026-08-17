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
    fun issueExampleShowsMagnitudeOrderBiasAndPermutationSeverity() {
        val emission = listOf(812, 795, 840, 801, 833)
        val rows = emission.mapIndexed { index, value -> row(100, value, ord = index) }

        val report = RrOrderAudit.evaluate(rows)

        assertEquals(2, report.schemaVersion)
        assertEquals(RrOrderIntegrityStatus.COMPLETE, report.integrityStatus)
        assertEquals(34.85, report.currentOrder.rawRmssdMs!!, 0.01)
        assertEquals(12.72, report.magnitudeOrderCounterfactual.rawRmssdMs!!, 0.01)
        assertTrue(report.rawRmssdCurrentMinusMagnitudeMs!! > 20.0)
        assertEquals(5, report.currentOrder.actualCleanCount)
        assertEquals(0, report.currentOrder.nClean)
        assertEquals(4, report.currentOrder.contiguousPairCount)
        assertFalse(report.currentOrder.meetsProductionBeatGate)
        assertEquals(1, report.provenance.trustworthyMultiBeatSeconds)
        assertEquals(1, report.provenance.magnitudeReorderedTrustworthySeconds)
        assertEquals(4, report.permutationImpact.valueInversions)
        assertEquals(10, report.permutationImpact.possibleValueInversions)
        assertEquals(0.4, report.permutationImpact.normalizedValueInversionFraction!!, 1e-12)
        assertTrue(report.rawOrderInvariantPreserved)
        assertTrue(report.flags.contains(RrOrderAuditFlag.CURRENT_BELOW_PRODUCTION_BEAT_GATE))
        assertTrue(report.flags.contains(RrOrderAuditFlag.COUNTERFACTUAL_BELOW_PRODUCTION_BEAT_GATE))
        assertNull(report.currentOrder.rmssdMs)
        assertNull(report.magnitudeOrderCounterfactual.rmssdMs)
    }

    @Test
    fun productionPipelineCounterfactualCoversAllCoreMetrics() {
        val emission = listOf(812, 795, 840, 801, 833)
        val rows = (0 until 4).flatMap { second ->
            emission.mapIndexed { index, value -> row(1_000L + second, value, ord = index) }
        }

        val report = RrOrderAudit.evaluate(rows)

        assertEquals(20, report.currentOrder.nInput)
        assertEquals(20, report.currentOrder.nClean)
        assertEquals(20, report.currentOrder.actualCleanCount)
        assertEquals(0, report.currentOrder.rejectedCount)
        assertEquals(19, report.currentOrder.contiguousPairCount)
        assertTrue(report.currentOrder.meetsProductionBeatGate)
        assertNotNull(report.currentOrder.rmssdMs)
        assertNotNull(report.magnitudeOrderCounterfactual.rmssdMs)
        assertNotNull(report.currentOrder.sdnnMs)
        assertNotNull(report.currentOrder.meanNNMs)
        assertNotNull(report.currentOrder.pnn50Pct)
        assertTrue(report.currentOrder.rmssdMs!! > report.magnitudeOrderCounterfactual.rmssdMs!!)
        assertTrue(report.rmssdCurrentMinusMagnitudeMs!! > 10.0)
        assertNotNull(report.pnn50CurrentMinusMagnitudePercentagePoints)
        assertEquals(4, report.provenance.trustworthyMultiBeatSeconds)
        assertTrue(report.provenance.hasCompleteSameSecondOrder)
        assertTrue(report.rawOrderInvariantPreserved)
        assertTrue(report.flags.contains(RrOrderAuditFlag.MAGNITUDE_ORDER_CHANGES_PRODUCTION_HRV))
    }

    @Test
    fun provenancePartitionsEveryMultiBeatSecondAndAssignsAmbiguousStatus() {
        val rows = listOf(
            row(1, 800, ord = null),
            row(2, 812, ord = 2), row(2, 795, ord = 7),
            row(3, 801, ord = null), row(3, 833, ord = null),
            row(4, 802, ord = null), row(4, 834, ord = 0),
            row(5, 803, ord = 0), row(5, 835, ord = 0),
        )

        val report = RrOrderAudit.evaluate(rows)
        val p = report.provenance

        assertEquals(9, p.totalIntervals)
        assertEquals(5, p.intervalsWithRecordedOrder)
        assertEquals(4, p.intervalsWithUnknownOrder)
        assertEquals(1L, p.firstTs)
        assertEquals(5L, p.lastTs)
        assertEquals(4L, p.spanSeconds)
        assertEquals(5, p.distinctSeconds)
        assertEquals(2, p.maxIntervalsPerSecond)
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
        assertEquals(RrOrderIntegrityStatus.AMBIGUOUS, report.integrityStatus)
        assertTrue(report.flags.contains(RrOrderAuditFlag.LEGACY_MULTI_BEAT_ORDER_UNKNOWN))
        assertTrue(report.flags.contains(RrOrderAuditFlag.MIXED_KNOWN_UNKNOWN_ORDER))
        assertTrue(report.flags.contains(RrOrderAuditFlag.DUPLICATE_RECORDED_ORDER))
    }

    @Test
    fun unknownOrderOnSingleBeatSecondsDoesNotDowngradeStructuralIntegrity() {
        val rows = listOf(
            row(10, 800, ord = null),
            row(11, 810, ord = null),
            row(12, 820, ord = null),
        )
        val report = RrOrderAudit.evaluate(rows)
        assertEquals(RrOrderIntegrityStatus.COMPLETE, report.integrityStatus)
        assertTrue(report.provenance.hasCompleteSameSecondOrder)
        assertFalse(report.flags.contains(RrOrderAuditFlag.LEGACY_MULTI_BEAT_ORDER_UNKNOWN))
    }

    @Test
    fun actualCleanCountSurvivesProductionGateAndReportsRejections() {
        val rows = listOf(
            row(1, 800, ord = 0),
            row(2, 805, ord = 0),
            row(3, 100, ord = 0),
            row(4, 810, ord = 0),
            row(5, 815, ord = 0),
        )
        val report = RrOrderAudit.evaluate(rows)
        assertEquals(0, report.currentOrder.nClean)
        assertEquals(4, report.currentOrder.actualCleanCount)
        assertEquals(1, report.currentOrder.rejectedCount)
        assertEquals(0.2, report.currentOrder.rejectedFraction!!, 1e-12)
        assertFalse(report.currentOrder.meetsProductionBeatGate)
        assertTrue(report.flags.contains(RrOrderAuditFlag.CLEANING_REJECTED_INTERVALS))
    }

    @Test
    fun rawMeanAndSdnnStayInvariantUnderReordering() {
        val rows = listOf(
            row(20, 900, ord = 2),
            row(20, 700, ord = 0),
            row(20, 850, ord = 1),
            row(21, 810, ord = 0),
        )
        val report = RrOrderAudit.evaluate(rows)
        assertEquals(report.currentOrder.rawMeanNNMs!!, report.magnitudeOrderCounterfactual.rawMeanNNMs!!, 1e-12)
        assertEquals(report.currentOrder.rawSdnnMs!!, report.magnitudeOrderCounterfactual.rawSdnnMs!!, 1e-12)
        assertTrue(report.rawOrderInvariantPreserved)
        assertFalse(report.flags.contains(RrOrderAuditFlag.RAW_ORDER_INVARIANT_FAILURE))
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
        val report = RrOrderAudit.evaluate(rows)
        val p = report.provenance
        assertEquals(1, p.trustworthyMultiBeatSeconds)
        assertEquals(0, p.magnitudeReorderedTrustworthySeconds)
        assertEquals(0, p.magnitudeReorderedTrustworthyIntervals)
        assertEquals(0, report.permutationImpact.valueInversions)
        assertEquals(0, report.permutationImpact.possibleValueInversions)
        assertNull(report.permutationImpact.normalizedValueInversionFraction)
    }

    @Test
    fun emptyAuditHasExplicitNoDataStatusAndFlags() {
        val report = RrOrderAudit.evaluate(emptyList())
        assertEquals(0, report.provenance.totalIntervals)
        assertEquals(RrOrderIntegrityStatus.NO_DATA, report.integrityStatus)
        assertNull(report.provenance.recordedOrderFraction)
        assertNull(report.provenance.trustworthyMultiBeatIntervalFraction)
        assertNull(report.provenance.spanSeconds)
        assertTrue(report.provenance.hasCompleteSameSecondOrder)
        assertNull(report.currentOrder.rawRmssdMs)
        assertNull(report.currentOrder.rmssdMs)
        assertNull(report.rawRmssdCurrentMinusMagnitudeMs)
        assertTrue(report.rawOrderInvariantPreserved)
        assertTrue(report.flags.contains(RrOrderAuditFlag.NO_INTERVALS))
    }
}
