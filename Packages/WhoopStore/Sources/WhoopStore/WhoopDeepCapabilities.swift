import WhoopProtocol

/// Explicit status vocabulary for WHOOP deep-data substrates tracked by #761.
///
/// This is deliberately separate from `WhoopLiveCapabilities`, which answers a different question:
/// which high-level product metrics a paired WHOOP can contribute. These types describe the current
/// confidence/support state of lower-level data paths so UI and diagnostics can distinguish waiting for
/// data from unsupported or experimental functionality without inventing a value.
public enum WhoopDeepCapability: String, CaseIterable, Sendable {
    case heartRate
    case hrv
    case respiration
    case spo2
    case skinTemperature
    case rawDeepBuffers
    case rawImu
    case battery
    case bodyStatus
    case syncMode
}

public enum WhoopCapabilityState: String, Equatable, Sendable {
    case available
    case unsupported
    case experimental
    case needsData
}

/// Stable, non-clinical explanation for why a capability is in its current state.
public enum WhoopCapabilityReason: String, Equatable, Sendable {
    case observationPresent
    case awaitingUsableData
    case calibratedLiveSpo2Unavailable
    case gatedResearchCapture
    case gatedRealtimeResearchCapture
    case gatedOffloadResearchCapture
    case validatedTransport
}

public struct WhoopCapabilityStatus: Equatable, Sendable {
    public let capability: WhoopDeepCapability
    public let state: WhoopCapabilityState
    public let reason: WhoopCapabilityReason

    public init(
        capability: WhoopDeepCapability,
        state: WhoopCapabilityState,
        reason: WhoopCapabilityReason
    ) {
        self.capability = capability
        self.state = state
        self.reason = reason
    }
}

/// Pure WHOOP capability-status resolver. Twin of Android `WhoopDeepCapabilities`.
///
/// `family` is the already-resolved protocol family from `WhoopProtocol.DeviceFamily`; this layer never
/// reparses registry/model strings or guesses hardware generation. `Whoop5Variant` remains orthogonal and
/// is intentionally not needed by the current axes because 5.0 and MG share these transport states.
///
/// `observed` is explicit caller evidence that a usable value/sample exists for this device/session.
/// It may promote only `needsData -> available`. It can never promote an `unsupported` or
/// `experimental` substrate, which prevents a stray raw/candidate packet from becoming a product claim.
public enum WhoopDeepCapabilities {

    public static func status(
        for capability: WhoopDeepCapability,
        family: DeviceFamily? = nil,
        observed: Set<WhoopDeepCapability> = []
    ) -> WhoopCapabilityStatus {
        switch capability {
        case .spo2:
            // #548: NOOP cannot produce a calibrated SpO2 percentage from a live WHOOP path.
            // Raw/candidate bytes therefore never auto-promote this capability.
            return .init(
                capability: capability,
                state: .unsupported,
                reason: .calibratedLiveSpo2Unavailable
            )

        case .rawDeepBuffers, .rawImu:
            // Instrument-first research paths. A decoder/capture existing is not equivalent to a
            // generally available product substrate, and observing one does not change this state.
            return .init(
                capability: capability,
                state: .experimental,
                reason: researchCaptureReason(for: family)
            )

        case .syncMode:
            return .init(
                capability: capability,
                state: .available,
                reason: .validatedTransport
            )

        case .heartRate, .hrv, .respiration, .skinTemperature, .battery, .bodyStatus:
            if observed.contains(capability) {
                return .init(
                    capability: capability,
                    state: .available,
                    reason: .observationPresent
                )
            }
            return .init(
                capability: capability,
                state: .needsData,
                reason: .awaitingUsableData
            )
        }
    }

    /// Stable roadmap-order profile, suitable for diagnostics/UI adapters without a second source of truth.
    public static func profile(
        family: DeviceFamily? = nil,
        observed: Set<WhoopDeepCapability> = []
    ) -> [WhoopCapabilityStatus] {
        WhoopDeepCapability.allCases.map {
            status(for: $0, family: family, observed: observed)
        }
    }

    private static func researchCaptureReason(for family: DeviceFamily?) -> WhoopCapabilityReason {
        switch family {
        case .some(.whoop5):
            // 5/MG validated high-rate IMU is received through the gated historical/offload path (#423).
            return .gatedOffloadResearchCapture
        case .some(.whoop4):
            // 4.0 high-rate raw streams are realtime and intentionally gated/silenced by default (#423).
            return .gatedRealtimeResearchCapture
        case .none:
            // Unknown family stays unknown. Generation resolution belongs to WhoopProtocol.
            return .gatedResearchCapture
        }
    }
}
