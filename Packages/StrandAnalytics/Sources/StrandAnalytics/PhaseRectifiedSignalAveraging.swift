import Foundation

// PhaseRectifiedSignalAveraging.swift - experimental PRSA DC/AC over cleaned NN intervals.
//
// Implements the standard beat-to-beat phase-rectified signal averaging substrate
// used for heart-rate deceleration capacity (DC) and acceleration capacity (AC):
// anchor on a small RR increase/decrease, average windows aligned on those anchors,
// and quantify the central profile with the scale-2 Haar contrast
// [X(0)+X(1)-X(-1)-X(-2)]/4.
//
// EXPERIMENTAL / RESEARCH METRIC ONLY. The historical clinical literature around
// DC includes post-MI risk stratification from 24 h ECG Holters. This wearable
// implementation exposes NO risk tier, diagnostic interpretation, or score input.
// PPG-derived RR/PRV is not assumed equivalent to clinical ECG NN intervals.
public enum PhaseRectifiedSignalAveraging {

    public enum Kind: String, Equatable, Sendable {
        case deceleration
        case acceleration
    }

    public static let defaultAnchorRatioCap: Double = 0.05
    public static let minimumRadius: Int = 2

    public struct Result: Equatable, Sendable {
        public let capacityMs: Double
        public let profileMs: [Double]
        public let anchorCount: Int
        public let kind: Kind
        public let radius: Int
        public let anchorRatioCap: Double
        public let rejectedLargeChangeAnchors: Int

        public init(capacityMs: Double, profileMs: [Double], anchorCount: Int,
                    kind: Kind, radius: Int, anchorRatioCap: Double,
                    rejectedLargeChangeAnchors: Int) {
            self.capacityMs = capacityMs
            self.profileMs = profileMs
            self.anchorCount = anchorCount
            self.kind = kind
            self.radius = radius
            self.anchorRatioCap = anchorRatioCap
            self.rejectedLargeChangeAnchors = rejectedLargeChangeAnchors
        }
    }

    public static func decelerationCapacity(
        cleanedNNMs: [Double],
        radius: Int = minimumRadius,
        anchorRatioCap: Double = defaultAnchorRatioCap,
        minimumAnchors: Int = 1
    ) -> Result? {
        evaluate(cleanedNNMs: cleanedNNMs, kind: .deceleration, radius: radius,
                 anchorRatioCap: anchorRatioCap, minimumAnchors: minimumAnchors)
    }

    public static func accelerationCapacity(
        cleanedNNMs: [Double],
        radius: Int = minimumRadius,
        anchorRatioCap: Double = defaultAnchorRatioCap,
        minimumAnchors: Int = 1
    ) -> Result? {
        evaluate(cleanedNNMs: cleanedNNMs, kind: .acceleration, radius: radius,
                 anchorRatioCap: anchorRatioCap, minimumAnchors: minimumAnchors)
    }

    public static func evaluate(
        cleanedNNMs: [Double],
        kind: Kind,
        radius: Int = minimumRadius,
        anchorRatioCap: Double = defaultAnchorRatioCap,
        minimumAnchors: Int = 1
    ) -> Result? {
        guard radius >= minimumRadius,
              anchorRatioCap.isFinite,
              anchorRatioCap >= 0,
              minimumAnchors > 0,
              cleanedNNMs.count >= 2 * radius + 1,
              cleanedNNMs.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }

        var anchors: [Int] = []
        var rejectedLarge = 0
        for i in radius..<(cleanedNNMs.count - radius) {
            let previous = cleanedNNMs[i - 1]
            let current = cleanedNNMs[i]
            let delta = current - previous
            let directional = kind == .deceleration ? delta > 0 : delta < 0
            guard directional else { continue }

            let ratio = abs(current / previous - 1.0)
            if ratio > anchorRatioCap {
                rejectedLarge += 1
                continue
            }
            anchors.append(i)
        }
        guard anchors.count >= minimumAnchors else { return nil }

        var profile = [Double](repeating: 0, count: 2 * radius)
        for anchor in anchors {
            for k in -radius..<radius {
                profile[k + radius] += cleanedNNMs[anchor + k]
            }
        }
        let anchorDenominator = Double(anchors.count)
        for i in profile.indices { profile[i] /= anchorDenominator }

        let x0 = profile[radius]
        let x1 = profile[radius + 1]
        let xm1 = profile[radius - 1]
        let xm2 = profile[radius - 2]
        let capacity = (x0 + x1 - xm1 - xm2) / 4.0
        guard capacity.isFinite else { return nil }

        return Result(capacityMs: capacity, profileMs: profile,
                      anchorCount: anchors.count, kind: kind, radius: radius,
                      anchorRatioCap: anchorRatioCap,
                      rejectedLargeChangeAnchors: rejectedLarge)
    }
}
