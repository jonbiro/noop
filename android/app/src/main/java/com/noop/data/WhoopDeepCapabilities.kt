package com.noop.data

import com.noop.protocol.DeviceFamily

/** Explicit status vocabulary for WHOOP deep-data substrates tracked by #761. */
enum class WhoopDeepCapability(val wireName: String) {
    HEART_RATE("heartRate"),
    HRV("hrv"),
    RESPIRATION("respiration"),
    SPO2("spo2"),
    SKIN_TEMPERATURE("skinTemperature"),
    RAW_DEEP_BUFFERS("rawDeepBuffers"),
    RAW_IMU("rawImu"),
    BATTERY("battery"),
    BODY_STATUS("bodyStatus"),
    SYNC_MODE("syncMode"),
}

enum class WhoopCapabilityState(val wireName: String) {
    AVAILABLE("available"),
    UNSUPPORTED("unsupported"),
    EXPERIMENTAL("experimental"),
    NEEDS_DATA("needsData"),
}

enum class WhoopCapabilityReason(val wireName: String) {
    OBSERVATION_PRESENT("observationPresent"),
    AWAITING_USABLE_DATA("awaitingUsableData"),
    CALIBRATED_LIVE_SPO2_UNAVAILABLE("calibratedLiveSpo2Unavailable"),
    GATED_RESEARCH_CAPTURE("gatedResearchCapture"),
    GATED_REALTIME_RESEARCH_CAPTURE("gatedRealtimeResearchCapture"),
    GATED_OFFLOAD_RESEARCH_CAPTURE("gatedOffloadResearchCapture"),
    VALIDATED_TRANSPORT("validatedTransport"),
}

data class WhoopCapabilityStatus(
    val capability: WhoopDeepCapability,
    val state: WhoopCapabilityState,
    val reason: WhoopCapabilityReason,
)

/**
 * Pure WHOOP capability-status resolver. Behavioral twin of Swift `WhoopDeepCapabilities`.
 *
 * This is separate from [WhoopLiveCapabilities]: that registry advertises high-level product metrics,
 * while this model explains the support/confidence state of deep-data substrates. [family] is the
 * already-resolved canonical protocol family; this layer never reparses model labels or guesses a
 * generation. [observed] is explicit caller evidence of usable data and may promote only
 * NEEDS_DATA -> AVAILABLE. It never promotes UNSUPPORTED or EXPERIMENTAL paths.
 */
object WhoopDeepCapabilities {

    fun status(
        capability: WhoopDeepCapability,
        family: DeviceFamily? = null,
        observed: Set<WhoopDeepCapability> = emptySet(),
    ): WhoopCapabilityStatus = when (capability) {
        WhoopDeepCapability.SPO2 -> WhoopCapabilityStatus(
            capability,
            WhoopCapabilityState.UNSUPPORTED,
            WhoopCapabilityReason.CALIBRATED_LIVE_SPO2_UNAVAILABLE,
        )

        WhoopDeepCapability.RAW_DEEP_BUFFERS,
        WhoopDeepCapability.RAW_IMU -> WhoopCapabilityStatus(
            capability,
            WhoopCapabilityState.EXPERIMENTAL,
            researchCaptureReason(family),
        )

        WhoopDeepCapability.SYNC_MODE -> WhoopCapabilityStatus(
            capability,
            WhoopCapabilityState.AVAILABLE,
            WhoopCapabilityReason.VALIDATED_TRANSPORT,
        )

        else -> if (capability in observed) {
            WhoopCapabilityStatus(
                capability,
                WhoopCapabilityState.AVAILABLE,
                WhoopCapabilityReason.OBSERVATION_PRESENT,
            )
        } else {
            WhoopCapabilityStatus(
                capability,
                WhoopCapabilityState.NEEDS_DATA,
                WhoopCapabilityReason.AWAITING_USABLE_DATA,
            )
        }
    }

    /** Stable roadmap-order profile, matching Swift CaseIterable declaration order. */
    fun profile(
        family: DeviceFamily? = null,
        observed: Set<WhoopDeepCapability> = emptySet(),
    ): List<WhoopCapabilityStatus> = WhoopDeepCapability.entries.map {
        status(it, family, observed)
    }

    private fun researchCaptureReason(family: DeviceFamily?): WhoopCapabilityReason = when (family) {
        DeviceFamily.WHOOP5 -> WhoopCapabilityReason.GATED_OFFLOAD_RESEARCH_CAPTURE
        DeviceFamily.WHOOP4 -> WhoopCapabilityReason.GATED_REALTIME_RESEARCH_CAPTURE
        null -> WhoopCapabilityReason.GATED_RESEARCH_CAPTURE
    }
}
