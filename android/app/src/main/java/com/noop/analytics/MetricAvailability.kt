package com.noop.analytics

import java.util.Locale

/**
 * Narrow availability envelope for deterministic analytics results.
 *
 * This does not replace ScoreConfidence, fusion provenance/trust, or capture completeness. It answers
 * only whether a metric can honestly return a current value and, when it cannot, why. Twin of Swift
 * MetricAvailability.
 */
data class MetricAvailability(
    val state: State,
    val reason: Reason? = null,
) {
    enum class State {
        AVAILABLE,
        CALIBRATING,
        INSUFFICIENT_DATA,
        UNSUPPORTED,
        WITHHELD_QUALITY,
        EXPERIMENTAL_AVAILABLE,
        STALE,
    }

    enum class ReasonCode(val raw: String) {
        NEED_BASELINE("need_baseline"),
        INSUFFICIENT_COVERAGE("insufficient_coverage"),
        MISSING_INPUTS("missing_inputs"),
        UNSUPPORTED_SOURCE("unsupported_source"),
        WITHHELD_QUALITY("withheld_quality"),
        EXPERIMENTAL_UNVALIDATED("experimental_unvalidated"),
        STALE_INPUT("stale_input"),
    }

    data class Reason(
        val code: ReasonCode,
        val have: Double? = null,
        val need: Double? = null,
        val items: List<String> = emptyList(),
    ) {
        val canonicalItems: List<String> = items.filter { it.isNotEmpty() }.distinct().sorted()

        val wireCode: String
            get() {
                val parts = mutableListOf<String>()
                have?.let { parts += "have=${number(it)}" }
                need?.let { parts += "need=${number(it)}" }
                if (canonicalItems.isNotEmpty()) parts += "items=${canonicalItems.joinToString(",")}" 
                return if (parts.isEmpty()) code.raw else "${code.raw}:${parts.joinToString(";")}" 
            }

        private fun number(value: Double): String {
            if (!value.isFinite()) return "nan"
            if (value % 1.0 == 0.0) return value.toLong().toString()
            return String.format(Locale.US, "%.6f", value).trimEnd('0').trimEnd('.')
        }
    }

    val hasValue: Boolean
        get() = state == State.AVAILABLE || state == State.EXPERIMENTAL_AVAILABLE
    val wireReason: String?
        get() = reason?.wireCode

    companion object {
        val available = MetricAvailability(State.AVAILABLE)

        fun needBaseline(have: Int, need: Int) = MetricAvailability(
            State.CALIBRATING,
            Reason(ReasonCode.NEED_BASELINE, have = maxOf(0, have).toDouble(), need = maxOf(0, need).toDouble()),
        )

        fun insufficientCoverage(have: Double, need: Double) = MetricAvailability(
            State.INSUFFICIENT_DATA,
            Reason(ReasonCode.INSUFFICIENT_COVERAGE, have = have, need = need),
        )

        fun missingInputs(inputs: List<String>) = MetricAvailability(
            State.INSUFFICIENT_DATA, Reason(ReasonCode.MISSING_INPUTS, items = inputs),
        )

        fun unsupportedSource(source: String) = MetricAvailability(
            State.UNSUPPORTED, Reason(ReasonCode.UNSUPPORTED_SOURCE, items = listOf(source)),
        )

        fun withheldQuality(flags: List<String>) = MetricAvailability(
            State.WITHHELD_QUALITY, Reason(ReasonCode.WITHHELD_QUALITY, items = flags),
        )

        fun experimentalUnvalidated(feature: String) = MetricAvailability(
            State.EXPERIMENTAL_AVAILABLE,
            Reason(ReasonCode.EXPERIMENTAL_UNVALIDATED, items = listOf(feature)),
        )

        fun stale(lastDay: String, expectedDay: String) = MetricAvailability(
            State.STALE,
            Reason(ReasonCode.STALE_INPUT, items = listOf("last=$lastDay", "expected=$expectedDay")),
        )
    }
}
