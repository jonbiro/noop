import Foundation

/// Why a deterministic analytics result is or is not currently usable.
///
/// This intentionally does NOT replace NOOP's existing confidence or provenance systems:
/// - `ScoreConfidence` answers how mature/reliable a headline score is.
/// - `FusionTier` / `FusionSource` answer which source won and how much it is trusted.
/// - `CaptureCompleteness` describes Test Centre capture coverage.
///
/// `MetricAvailability` answers a narrower question: "can this metric honestly return a value right now,
/// and if not, why?" Keeping this layer narrow lets engines stop encoding calibration/quality failures as
/// unexplained nils without flattening distinct confidence/source semantics into one mega-model.
public struct MetricAvailability: Equatable, Sendable, Codable {
    public enum State: String, Equatable, Sendable, Codable {
        case available
        case calibrating
        case insufficientData
        case unsupported
        case withheldQuality
        case experimentalAvailable
        case stale
    }

    public enum ReasonCode: String, Equatable, Sendable, Codable {
        case needBaseline = "need_baseline"
        case insufficientCoverage = "insufficient_coverage"
        case missingInputs = "missing_inputs"
        case unsupportedSource = "unsupported_source"
        case withheldQuality = "withheld_quality"
        case experimentalUnvalidated = "experimental_unvalidated"
        case staleInput = "stale_input"
    }

    public struct Reason: Equatable, Sendable, Codable {
        public let code: ReasonCode
        /// Optional observed amount. Counts are encoded as whole-valued Doubles so the same field can also
        /// represent fractional coverage without creating parallel count/ratio reason shapes.
        public let have: Double?
        public let need: Double?
        /// Canonical sorted/deduplicated context tokens: missing input keys, quality flags, source id, etc.
        public let items: [String]

        public init(code: ReasonCode, have: Double? = nil, need: Double? = nil, items: [String] = []) {
            self.code = code
            self.have = have
            self.need = need
            self.items = Array(Set(items.filter { !$0.isEmpty })).sorted()
        }

        /// Stable diagnostic form suitable for logs, JSON-adjacent exports, and cross-platform golden tests.
        /// It is not intended as user-facing copy.
        public var wireCode: String {
            var parts: [String] = []
            if let have { parts.append("have=\(Self.number(have))") }
            if let need { parts.append("need=\(Self.number(need))") }
            if !items.isEmpty { parts.append("items=\(items.joined(separator: ","))") }
            return parts.isEmpty ? code.rawValue : "\(code.rawValue):\(parts.joined(separator: ";"))"
        }

        private static func number(_ value: Double) -> String {
            guard value.isFinite else { return "nan" }
            if value.rounded() == value { return String(Int(value)) }
            return String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
                .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        }
    }

    public let state: State
    public let reason: Reason?

    public init(state: State, reason: Reason? = nil) {
        self.state = state
        self.reason = reason
    }

    /// True only when an engine is offering a current value. Experimental values remain explicitly tagged
    /// but are still values; stale/withheld/calibrating states are not silently treated as usable.
    public var hasValue: Bool { state == .available || state == .experimentalAvailable }
    public var wireReason: String? { reason?.wireCode }

    public static let available = MetricAvailability(state: .available)

    public static func needBaseline(have: Int, need: Int) -> MetricAvailability {
        MetricAvailability(
            state: .calibrating,
            reason: Reason(code: .needBaseline, have: Double(max(0, have)), need: Double(max(0, need)))
        )
    }

    public static func insufficientCoverage(have: Double, need: Double) -> MetricAvailability {
        MetricAvailability(
            state: .insufficientData,
            reason: Reason(code: .insufficientCoverage, have: have, need: need)
        )
    }

    public static func missingInputs(_ inputs: [String]) -> MetricAvailability {
        MetricAvailability(state: .insufficientData, reason: Reason(code: .missingInputs, items: inputs))
    }

    public static func unsupportedSource(_ source: String) -> MetricAvailability {
        MetricAvailability(state: .unsupported, reason: Reason(code: .unsupportedSource, items: [source]))
    }

    public static func withheldQuality(_ flags: [String]) -> MetricAvailability {
        MetricAvailability(state: .withheldQuality, reason: Reason(code: .withheldQuality, items: flags))
    }

    public static func experimentalUnvalidated(_ feature: String) -> MetricAvailability {
        MetricAvailability(
            state: .experimentalAvailable,
            reason: Reason(code: .experimentalUnvalidated, items: [feature])
        )
    }

    public static func stale(lastDay: String, expectedDay: String) -> MetricAvailability {
        MetricAvailability(
            state: .stale,
            reason: Reason(code: .staleInput, items: ["last=\(lastDay)", "expected=\(expectedDay)"])
        )
    }
}
