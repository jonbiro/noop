package com.noop.data

import com.noop.protocol.DeviceFamily
import org.junit.Assert.assertEquals
import org.junit.Test

/** Behavioral parity twin of Swift `WhoopDeepCapabilitiesTests`. */
class WhoopDeepCapabilitiesTest {

    @Test
    fun profileCoversRoadmapAxesInStableOrder() {
        assertEquals(
            listOf(
                "heartRate", "hrv", "respiration", "spo2", "skinTemperature",
                "rawDeepBuffers", "rawImu", "battery", "bodyStatus", "syncMode",
            ),
            WhoopDeepCapabilities.profile(DeviceFamily.WHOOP5).map { it.capability.wireName },
        )
    }

    @Test
    fun observedUsableDataPromotesOnlyNeedsDataCapabilities() {
        val observed = setOf(
            WhoopDeepCapability.HEART_RATE,
            WhoopDeepCapability.HRV,
            WhoopDeepCapability.RESPIRATION,
            WhoopDeepCapability.SKIN_TEMPERATURE,
            WhoopDeepCapability.BATTERY,
            WhoopDeepCapability.BODY_STATUS,
        )
        for (capability in observed) {
            assertEquals(
                WhoopCapabilityStatus(
                    capability,
                    WhoopCapabilityState.AVAILABLE,
                    WhoopCapabilityReason.OBSERVATION_PRESENT,
                ),
                WhoopDeepCapabilities.status(capability, DeviceFamily.WHOOP5, observed),
            )
        }

        val waiting = WhoopDeepCapabilities.status(
            WhoopDeepCapability.RESPIRATION,
            DeviceFamily.WHOOP5,
        )
        assertEquals(WhoopCapabilityState.NEEDS_DATA, waiting.state)
        assertEquals(WhoopCapabilityReason.AWAITING_USABLE_DATA, waiting.reason)
    }

    @Test
    fun spo2RemainsUnsupportedEvenWhenCallerObservedCandidateData() {
        val status = WhoopDeepCapabilities.status(
            WhoopDeepCapability.SPO2,
            DeviceFamily.WHOOP5,
            setOf(WhoopDeepCapability.SPO2),
        )
        assertEquals(WhoopCapabilityState.UNSUPPORTED, status.state)
        assertEquals(WhoopCapabilityReason.CALIBRATED_LIVE_SPO2_UNAVAILABLE, status.reason)
    }

    @Test
    fun researchSubstratesRemainExperimentalEvenWhenObserved() {
        for (capability in listOf(WhoopDeepCapability.RAW_DEEP_BUFFERS, WhoopDeepCapability.RAW_IMU)) {
            val status = WhoopDeepCapabilities.status(
                capability,
                DeviceFamily.WHOOP5,
                setOf(capability),
            )
            assertEquals(WhoopCapabilityState.EXPERIMENTAL, status.state)
            assertEquals(WhoopCapabilityReason.GATED_OFFLOAD_RESEARCH_CAPTURE, status.reason)
        }
    }

    @Test
    fun researchReasonUsesCanonicalFamilyAndAbstainsWhenUnknown() {
        assertEquals(
            WhoopCapabilityReason.GATED_REALTIME_RESEARCH_CAPTURE,
            WhoopDeepCapabilities.status(WhoopDeepCapability.RAW_IMU, DeviceFamily.WHOOP4).reason,
        )
        assertEquals(
            WhoopCapabilityReason.GATED_OFFLOAD_RESEARCH_CAPTURE,
            WhoopDeepCapabilities.status(WhoopDeepCapability.RAW_IMU, DeviceFamily.WHOOP5).reason,
        )
        assertEquals(
            WhoopCapabilityReason.GATED_RESEARCH_CAPTURE,
            WhoopDeepCapabilities.status(WhoopDeepCapability.RAW_IMU, null).reason,
        )
    }

    @Test
    fun syncTransportIsAvailableWithoutMeasurementObservation() {
        val status = WhoopDeepCapabilities.status(WhoopDeepCapability.SYNC_MODE, DeviceFamily.WHOOP4)
        assertEquals(WhoopCapabilityState.AVAILABLE, status.state)
        assertEquals(WhoopCapabilityReason.VALIDATED_TRANSPORT, status.reason)
    }
}
