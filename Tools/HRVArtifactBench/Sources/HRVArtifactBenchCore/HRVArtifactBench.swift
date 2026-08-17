import Foundation
import StrandAnalytics

/// Tool-only candidate inspired by the Lipponen–Tarvainen classification family and the MIT-licensed
/// OpenStrap reference implementation (`OpenStrap/analytics@cef6fe4.../rr_correction.dart`).
///
/// This code is intentionally isolated under Tools/. It is NOT a shipped NOOP cleaning path. Its only job
/// is to make candidate behavior measurable against `HRVAnalyzer` before anyone proposes a production port.
public enum ArtifactCandidate {
    public enum BeatClass: String, Codable, Sendable, Equatable {
        case normal
        case ectopic
        case longShort
        case missed
        case extra
    }

    public struct Result: Codable, Sendable, Equatable {
        public let nn: [Double]
        public let classes: [BeatClass]
        public let cleanFraction: Double
        public let correctedCount: Int
        public let droppedCount: Int
    }

    public static func correct(_ rr: [Double], alpha: Double = 5.2,
                               windowBeats: Int = 91, thresholdFloorMs: Double = 100) -> Result {
        guard !rr.isEmpty else {
            return Result(nn: [], classes: [], cleanFraction: 0, correctedCount: 0, droppedCount: 0)
        }
        guard rr.count >= 3 else {
            let classes = rr.map { (300...2000).contains($0) ? BeatClass.normal : .longShort }
            let kept = zip(rr, classes).compactMap { value, cls in cls == .normal ? value : nil }
            return Result(nn: kept, classes: classes,
                          cleanFraction: Double(kept.count) / Double(rr.count),
                          correctedCount: 0, droppedCount: rr.count - kept.count)
        }

        let n = rr.count
        var dRR = Array(repeating: 0.0, count: n)
        for i in 1..<n { dRR[i] = rr[i] - rr[i - 1] }
        let th1 = slidingThreshold(dRR, window: windowBeats, alpha: alpha, floor: thresholdFloorMs)
        let med = slidingMedian(rr, window: windowBeats)
        let mRR = (0..<n).map { index -> Double in
            let deviation = rr[index] - med[index]
            return deviation < 0 ? deviation * 2 : deviation
        }
        let th2 = slidingThreshold(mRR, window: windowBeats, alpha: alpha, floor: thresholdFloorMs)

        var classes = Array(repeating: BeatClass.normal, count: n)
        for i in 0..<n {
            let hardLong = rr[i] > 2000
            let hardShort = rr[i] < 300
            let bigJump = abs(dRR[i]) > th1[i]
            let bigDeviation = abs(mRR[i]) > th2[i]

            if hardLong || (bigDeviation && mRR[i] > 0) {
                classes[i] = med[i] > 0 && rr[i] > 1.5 * med[i] ? .missed : .longShort
            } else if hardShort || (bigDeviation && mRR[i] < 0) {
                classes[i] = med[i] > 0 && rr[i] < 0.6 * med[i] ? .extra : .longShort
            } else if bigJump {
                classes[i] = .ectopic
            }
        }

        // A recovery beat after a single opposite-sign disturbance can be flagged by dRR alone. If that
        // recovery value is itself close to the local median, keep it normal so one event does not turn into
        // a fake two-beat run.
        if n > 1 {
            for i in 1..<n where classes[i] == .ectopic {
                let previousBad = classes[i - 1] != .normal
                let opposite = dRR[i] * dRR[i - 1] < 0
                let valueNormal = med[i] > 0 && rr[i] >= 300 && rr[i] <= 2000
                    && abs(rr[i] - med[i]) <= 0.2 * med[i]
                if previousBad && opposite && valueNormal { classes[i] = .normal }
            }
        }

        let artifact = classes.map { $0 != .normal }
        var output: [Double] = []
        output.reserveCapacity(n)
        var corrected = 0
        var dropped = 0
        var i = 0
        while i < n {
            if !artifact[i] {
                output.append(rr[i])
                i += 1
                continue
            }
            var end = i
            while end < n && artifact[end] { end += 1 }
            let runLength = end - i
            if runLength == 1, let estimate = catmullRomCorrection(rr, artifact: artifact, index: i) {
                output.append(estimate)
                corrected += 1
            } else {
                dropped += runLength
            }
            i = end
        }

        let normalCount = classes.filter { $0 == .normal }.count
        return Result(
            nn: output,
            classes: classes,
            cleanFraction: Double(normalCount) / Double(n),
            correctedCount: corrected,
            droppedCount: dropped
        )
    }

    private static func slidingThreshold(_ values: [Double], window: Int,
                                         alpha: Double, floor: Double) -> [Double] {
        let half = max(1, window) / 2
        return values.indices.map { index in
            let lo = max(0, index - half)
            let hi = min(values.count - 1, index + half)
            let segment = Array(values[lo...hi]).sorted()
            let q1 = percentile(segment, fraction: 0.25)
            let q3 = percentile(segment, fraction: 0.75)
            return max(alpha * (q3 - q1) / 2, floor)
        }
    }

    private static func slidingMedian(_ values: [Double], window: Int) -> [Double] {
        let half = max(1, window) / 2
        return values.indices.map { index in
            let lo = max(0, index - half)
            let hi = min(values.count - 1, index + half)
            var segment: [Double] = []
            segment.reserveCapacity(hi - lo)
            for j in lo...hi where j != index { segment.append(values[j]) }
            return median(segment) ?? values[index]
        }
    }

    private static func percentile(_ sorted: [Double], fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let position = min(1, max(0, fraction)) * Double(sorted.count - 1)
        let lo = Int(floor(position))
        let hi = Int(ceil(position))
        if lo == hi { return sorted[lo] }
        let weight = position - Double(lo)
        return sorted[lo] * (1 - weight) + sorted[hi] * weight
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private static func catmullRomCorrection(_ rr: [Double], artifact: [Bool], index: Int) -> Double? {
        var left: [Double] = []
        var cursor = index - 1
        while cursor >= 0 && left.count < 2 {
            if !artifact[cursor] { left.insert(rr[cursor], at: 0) }
            cursor -= 1
        }
        var right: [Double] = []
        cursor = index + 1
        while cursor < rr.count && right.count < 2 {
            if !artifact[cursor] { right.append(rr[cursor]) }
            cursor += 1
        }
        guard let p1 = left.last, let p2 = right.first else { return nil }
        let p0 = left.count >= 2 ? left[0] : p1
        let p3 = right.count >= 2 ? right[1] : p2
        let t = 0.5, t2 = t * t, t3 = t2 * t
        return 0.5 * ((2 * p1) + (-p0 + p2) * t
                      + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                      + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }
}

public enum HRVArtifactBenchmark {
    public struct Scenario: Sendable, Equatable {
        public let name: String
        public let truth: [Double]
        public let observed: [Double]
        public init(name: String, truth: [Double], observed: [Double]) {
            self.name = name; self.truth = truth; self.observed = observed
        }
    }

    public struct Measurement: Codable, Sendable, Equatable {
        public let scenario: String
        public let truthRmssdMs: Double
        public let noopRmssdMs: Double?
        public let candidateRmssdMs: Double?
        public let noopAbsoluteErrorMs: Double?
        public let candidateAbsoluteErrorMs: Double?
        public let candidateCleanFraction: Double
        public let candidateCorrectedCount: Int
        public let candidateDroppedCount: Int
        public let candidateClassCounts: [String: Int]

        public var candidateImprovementMs: Double? {
            guard let noopAbsoluteErrorMs, let candidateAbsoluteErrorMs else { return nil }
            return noopAbsoluteErrorMs - candidateAbsoluteErrorMs
        }
    }

    public struct Report: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let measurements: [Measurement]
        public var candidateWins: Int {
            measurements.filter { ($0.candidateImprovementMs ?? 0) > 1e-9 }.count
        }
        public var noopWins: Int {
            measurements.filter { ($0.candidateImprovementMs ?? 0) < -1e-9 }.count
        }
    }

    public static func run(_ scenarios: [Scenario] = builtInScenarios()) -> Report {
        let measurements = scenarios.map { scenario -> Measurement in
            let truth = rawRmssd(scenario.truth) ?? 0
            let noop = HRVAnalyzer.analyzeRaw(scenario.observed).rmssd
            let corrected = ArtifactCandidate.correct(scenario.observed)
            let candidate = rawRmssd(corrected.nn)
            var counts: [String: Int] = [:]
            for cls in corrected.classes { counts[cls.rawValue, default: 0] += 1 }
            return Measurement(
                scenario: scenario.name,
                truthRmssdMs: truth,
                noopRmssdMs: noop,
                candidateRmssdMs: candidate,
                noopAbsoluteErrorMs: noop.map { abs($0 - truth) },
                candidateAbsoluteErrorMs: candidate.map { abs($0 - truth) },
                candidateCleanFraction: corrected.cleanFraction,
                candidateCorrectedCount: corrected.correctedCount,
                candidateDroppedCount: corrected.droppedCount,
                candidateClassCounts: counts
            )
        }
        return Report(schemaVersion: 1, measurements: measurements)
    }

    public static func builtInScenarios() -> [Scenario] {
        let clean = (0..<300).map { index -> Double in
            800 + 36 * sin(2 * .pi * Double(index) / 11)
                + 14 * sin(2 * .pi * Double(index) / 37)
        }

        func replacing(_ source: [Double], _ replacements: [Int: Double]) -> [Double] {
            source.enumerated().map { replacements[$0.offset] ?? $0.element }
        }

        var isolatedLong = clean
        isolatedLong[150] = 1_650

        var isolatedShort = clean
        isolatedShort[150] = 260

        var grossHigh = clean
        grossHigh[150] = 2_500

        var twoBeatRun = clean
        twoBeatRun[149] = 250
        twoBeatRun[150] = 2_400

        let moderateJump = replacing(clean, [150: clean[150] + 240])

        return [
            Scenario(name: "clean_respiratory_variability", truth: clean, observed: clean),
            Scenario(name: "isolated_long_interval", truth: clean, observed: isolatedLong),
            Scenario(name: "isolated_short_interval", truth: clean, observed: isolatedShort),
            Scenario(name: "gross_high_outlier", truth: clean, observed: grossHigh),
            Scenario(name: "two_beat_artifact_run", truth: clean, observed: twoBeatRun),
            Scenario(name: "moderate_ectopic_jump", truth: clean, observed: moderateJump),
        ]
    }

    public static func rawRmssd(_ nn: [Double]) -> Double? {
        guard nn.count >= 2 else { return nil }
        var sum = 0.0
        for i in 1..<nn.count {
            let delta = nn[i] - nn[i - 1]
            sum += delta * delta
        }
        return sqrt(sum / Double(nn.count - 1))
    }
}

public enum HRVArtifactBenchmarkEncoder {
    public static func json(_ report: HRVArtifactBenchmark.Report) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    public static func markdown(_ report: HRVArtifactBenchmark.Report) -> Data {
        var lines = [
            "# HRV artifact-cleaning differential benchmark",
            "",
            "This is a tool-only comparison. The candidate is not a production NOOP cleaning path.",
            "",
            "| Scenario | Truth RMSSD | NOOP RMSSD | Candidate RMSSD | NOOP abs error | Candidate abs error | Δ error (positive = candidate better) | Corrected | Dropped |",
            "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
        ]
        for m in report.measurements {
            lines.append("| \(m.scenario) | \(f(m.truthRmssdMs)) | \(f(m.noopRmssdMs)) | \(f(m.candidateRmssdMs)) | \(f(m.noopAbsoluteErrorMs)) | \(f(m.candidateAbsoluteErrorMs)) | \(f(m.candidateImprovementMs)) | \(m.candidateCorrectedCount) | \(m.candidateDroppedCount) |")
        }
        lines += ["", "Candidate wins: \(report.candidateWins); NOOP wins: \(report.noopWins).", ""]
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func f(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
