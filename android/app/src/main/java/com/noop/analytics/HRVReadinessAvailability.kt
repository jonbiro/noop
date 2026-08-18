package com.noop.analytics

/** Availability-aware facade for the existing opt-in HRV Readiness experiment. */
data class HRVReadinessEvaluation(
    val result: HRVReadinessResult?,
    val availability: MetricAvailability,
    val validNightCount: Int,
)

fun HRVReadiness.evaluateWithAvailability(avgHrv: List<Double?>): HRVReadinessEvaluation {
    val cfg = Baselines.hrvCfg
    val validNightCount = avgHrv.count { value -> value != null && cfg.minVal <= value && value <= cfg.maxVal }
    val result = evaluate(avgHrv)

    return if (result != null) {
        HRVReadinessEvaluation(
            result = result,
            availability = MetricAvailability.experimentalUnvalidated("hrv_readiness"),
            validNightCount = validNightCount,
        )
    } else {
        HRVReadinessEvaluation(
            result = null,
            availability = MetricAvailability.needBaseline(validNightCount, MIN_NIGHTS),
            validNightCount = validNightCount,
        )
    }
}
