import XCTest
@testable import StrandAnalytics

final class PhaseRectifiedSignalAveragingTests: XCTestCase {
    func testLinearIncreasingRRHasExactPositiveDecelerationCapacity() {
        let rr = [900.0, 920, 940, 960, 980, 1000, 1020, 1040, 1060]
        let r = PhaseRectifiedSignalAveraging.decelerationCapacity(cleanedNNMs: rr)!
        XCTAssertEqual(r.capacityMs, 20, accuracy: 1e-12)
        XCTAssertEqual(r.profileMs, [940, 960, 980, 1000])
        XCTAssertEqual(r.anchorCount, 5)
        XCTAssertEqual(r.rejectedLargeChangeAnchors, 0)
    }

    func testLinearDecreasingRRHasExactNegativeAccelerationCapacity() {
        let rr = [1060.0, 1040, 1020, 1000, 980, 960, 940, 920, 900]
        let r = PhaseRectifiedSignalAveraging.accelerationCapacity(cleanedNNMs: rr)!
        XCTAssertEqual(r.capacityMs, -20, accuracy: 1e-12)
        XCTAssertEqual(r.profileMs, [1020, 1000, 980, 960])
        XCTAssertEqual(r.anchorCount, 5)
    }

    func testOppositeKindHasNoAnchors() {
        let rr = [900.0, 920, 940, 960, 980, 1000, 1020, 1040, 1060]
        XCTAssertNil(PhaseRectifiedSignalAveraging.accelerationCapacity(cleanedNNMs: rr))
    }

    func testLargeDirectionalJumpIsRejectedAsAnchor() {
        let rr = [900.0, 920, 940, 1060, 1080, 1100, 1120, 1140, 1160]
        let r = PhaseRectifiedSignalAveraging.decelerationCapacity(cleanedNNMs: rr)!
        XCTAssertEqual(r.anchorCount, 4)
        XCTAssertEqual(r.rejectedLargeChangeAnchors, 1)
    }

    func testCustomAnchorCapAndMinimumAnchorGate() {
        let rr = [900.0, 920, 940, 960, 980, 1000, 1020, 1040, 1060]
        XCTAssertNil(PhaseRectifiedSignalAveraging.decelerationCapacity(cleanedNNMs: rr, anchorRatioCap: 0.01))
        XCTAssertNotNil(PhaseRectifiedSignalAveraging.decelerationCapacity(cleanedNNMs: rr, minimumAnchors: 5))
        XCTAssertNil(PhaseRectifiedSignalAveraging.decelerationCapacity(cleanedNNMs: rr, minimumAnchors: 6))
    }

    func testLargerRadiusPreservesCentralHaarCapacity() {
        let rr = [860.0, 880, 900, 920, 940, 960, 980, 1000, 1020, 1040, 1060, 1080]
        let r = PhaseRectifiedSignalAveraging.decelerationCapacity(cleanedNNMs: rr, radius: 3)!
        XCTAssertEqual(r.capacityMs, 20, accuracy: 1e-12)
        XCTAssertEqual(r.profileMs.count, 6)
    }

    func testInvalidConfigurationAndDirtyNNFailClosed() {
        let valid = [900.0, 920, 940, 960, 980, 1000]
        XCTAssertNil(PhaseRectifiedSignalAveraging.decelerationCapacity(cleanedNNMs: valid, radius: 1))
        XCTAssertNil(PhaseRectifiedSignalAveraging.decelerationCapacity(cleanedNNMs: valid, anchorRatioCap: -0.1))
        XCTAssertNil(PhaseRectifiedSignalAveraging.decelerationCapacity(cleanedNNMs: valid, minimumAnchors: 0))
        XCTAssertNil(PhaseRectifiedSignalAveraging.decelerationCapacity(cleanedNNMs: [900, 920, .nan, 960, 980]))
        XCTAssertNil(PhaseRectifiedSignalAveraging.decelerationCapacity(cleanedNNMs: [900, 920, 0, 960, 980]))
        XCTAssertNil(PhaseRectifiedSignalAveraging.decelerationCapacity(cleanedNNMs: [900, 920, 940, 960]))
    }
}
