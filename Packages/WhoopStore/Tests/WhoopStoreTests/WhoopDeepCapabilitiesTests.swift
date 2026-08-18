import XCTest
import WhoopProtocol
@testable import WhoopStore

final class WhoopDeepCapabilitiesTests: XCTestCase {

    func testProfileCoversRoadmapAxesInStableOrder() {
        XCTAssertEqual(
            WhoopDeepCapabilities.profile(family: .whoop5).map(\.capability),
            [
                .heartRate, .hrv, .respiration, .spo2, .skinTemperature,
                .rawDeepBuffers, .rawImu, .battery, .bodyStatus, .syncMode,
            ]
        )
    }

    func testObservedUsableDataPromotesOnlyNeedsDataCapabilities() {
        let observed: Set<WhoopDeepCapability> = [
            .heartRate, .hrv, .respiration, .skinTemperature, .battery, .bodyStatus,
        ]
        for capability in observed {
            XCTAssertEqual(
                WhoopDeepCapabilities.status(
                    for: capability,
                    family: .whoop5,
                    observed: observed
                ),
                WhoopCapabilityStatus(
                    capability: capability,
                    state: .available,
                    reason: .observationPresent
                )
            )
        }

        let waiting = WhoopDeepCapabilities.status(
            for: .respiration,
            family: .whoop5
        )
        XCTAssertEqual(waiting.state, .needsData)
        XCTAssertEqual(waiting.reason, .awaitingUsableData)
    }

    func testSpo2RemainsUnsupportedEvenWhenCallerObservedCandidateData() {
        let status = WhoopDeepCapabilities.status(
            for: .spo2,
            family: .whoop5,
            observed: [.spo2]
        )
        XCTAssertEqual(status.state, .unsupported)
        XCTAssertEqual(status.reason, .calibratedLiveSpo2Unavailable)
    }

    func testResearchSubstratesRemainExperimentalEvenWhenObserved() {
        for capability in [WhoopDeepCapability.rawDeepBuffers, .rawImu] {
            let status = WhoopDeepCapabilities.status(
                for: capability,
                family: .whoop5,
                observed: [capability]
            )
            XCTAssertEqual(status.state, .experimental)
            XCTAssertEqual(status.reason, .gatedOffloadResearchCapture)
        }
    }

    func testResearchReasonUsesCanonicalFamilyAndAbstainsWhenUnknown() {
        XCTAssertEqual(
            WhoopDeepCapabilities.status(for: .rawImu, family: .whoop4).reason,
            .gatedRealtimeResearchCapture
        )
        XCTAssertEqual(
            WhoopDeepCapabilities.status(for: .rawImu, family: .whoop5).reason,
            .gatedOffloadResearchCapture
        )
        XCTAssertEqual(
            WhoopDeepCapabilities.status(for: .rawImu, family: nil).reason,
            .gatedResearchCapture
        )
    }

    func testSyncTransportIsAvailableWithoutMeasurementObservation() {
        let status = WhoopDeepCapabilities.status(for: .syncMode, family: .whoop4)
        XCTAssertEqual(status.state, .available)
        XCTAssertEqual(status.reason, .validatedTransport)
    }
}
