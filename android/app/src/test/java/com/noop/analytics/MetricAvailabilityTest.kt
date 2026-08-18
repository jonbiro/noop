package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MetricAvailabilityTest {
    @Test
    fun availableHasValueWithoutReason() {
        assertEquals(MetricAvailability.State.AVAILABLE, MetricAvailability.available.state)
        assertTrue(MetricAvailability.available.hasValue)
        assertNull(MetricAvailability.available.reason)
        assertNull(MetricAvailability.available.wireReason)
    }

    @Test
    fun baselineAndCoverageReasonsAreStable() {
        val baseline = MetricAvailability.needBaseline(5, 14)
        assertEquals(MetricAvailability.State.CALIBRATING, baseline.state)
        assertFalse(baseline.hasValue)
        assertEquals("need_baseline:have=5;need=14", baseline.wireReason)

        val coverage = MetricAvailability.insufficientCoverage(0.42, 0.8)
        assertEquals("insufficient_coverage:have=0.42;need=0.8", coverage.wireReason)
    }

    @Test
    fun itemsAreCanonicalAndExperimentalCarriesValue() {
        val missing = MetricAvailability.missingInputs(listOf("rhr", "", "hrv", "rhr"))
        assertEquals(listOf("hrv", "rhr"), missing.reason!!.canonicalItems)
        assertEquals("missing_inputs:items=hrv,rhr", missing.wireReason)

        val experimental = MetricAvailability.experimentalUnvalidated("hrv_readiness")
        assertTrue(experimental.hasValue)
        assertEquals(MetricAvailability.State.EXPERIMENTAL_AVAILABLE, experimental.state)
        assertEquals("experimental_unvalidated:items=hrv_readiness", experimental.wireReason)
    }

    @Test
    fun withheldUnsupportedAndStaleDoNotClaimValue() {
        assertFalse(MetricAvailability.withheldQuality(listOf("rr_order_unknown")).hasValue)
        assertFalse(MetricAvailability.unsupportedSource("whoop4_spo2").hasValue)
        assertFalse(MetricAvailability.stale("2026-01-01", "2026-01-02").hasValue)
    }

    @Test
    fun hrvReadinessCalibratingExplainsValidNightCount() {
        val input = listOf<Double?>(60.0, 61.0, null, 500.0, 62.0, 63.0)
        val evaluation = HRVReadiness.evaluateWithAvailability(input)
        assertNull(evaluation.result)
        assertEquals(4, evaluation.validNightCount)
        assertEquals(MetricAvailability.State.CALIBRATING, evaluation.availability.state)
        assertEquals("need_baseline:have=4;need=14", evaluation.availability.wireReason)
        assertEquals(HRVReadiness.evaluate(input), evaluation.result)
    }

    @Test
    fun hrvReadinessResultRemainsExplicitlyExperimental() {
        val input = (0 until 14).map { (55 + it).toDouble() as Double? }
        val legacy = HRVReadiness.evaluate(input)
        val evaluation = HRVReadiness.evaluateWithAvailability(input)

        assertTrue(legacy != null)
        assertEquals(legacy, evaluation.result)
        assertEquals(14, evaluation.validNightCount)
        assertEquals(MetricAvailability.State.EXPERIMENTAL_AVAILABLE, evaluation.availability.state)
        assertTrue(evaluation.availability.hasValue)
        assertEquals("experimental_unvalidated:items=hrv_readiness", evaluation.availability.wireReason)
    }
}
