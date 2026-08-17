import Foundation

public struct RROrderCaptureAssociationSummary: Equatable, Sendable, Codable {
    public let coveragePairCount: Int
    public let coverageVsAbsoluteRmssdDeltaSpearman: Double?
    public let collapsedCoveragePairCount: Int
    public let collapsedCoverageVsAbsoluteRmssdDeltaSpearman: Double?
    public let beatAccuracyPairCount: Int
    public let beatAccuracyVsAbsoluteRmssdDeltaSpearman: Double?
}

public struct RROrderCaptureVerdictStratum: Equatable, Sendable, Codable {
    public let verdict: String
    public let sessionCount: Int
    public let pairedRmssdCount: Int
    public let rmssdDeltaMs: RROrderSignedDifferenceSummary
    public let coverage: RROrderDistributionSummary?
    public let collapsedCoverage: RROrderDistributionSummary?
    public let beatAccurateFraction: RROrderDistributionSummary?

    init(verdict: String, records: [RROrderCorpusRecord]) {
        self.verdict = verdict
        sessionCount = records.count
        rmssdDeltaMs = RROrderSignedDifferenceSummary(records.compactMap(\.audit.rmssdCurrentMinusMagnitudeMs))
        pairedRmssdCount = rmssdDeltaMs.distribution?.count ?? 0
        coverage = RROrderDistributionSummary(records.map { $0.audit.captureDiagnostics.coverage })
        collapsedCoverage = RROrderDistributionSummary(records.map { $0.audit.captureDiagnostics.collapsedCoverage })
        beatAccurateFraction = RROrderDistributionSummary(records.map { $0.audit.captureDiagnostics.beatAccurateFraction })
    }
}

/// Aggregate view of the native `HRVAnalyzer` coverage/over-count diagnostics carried by audit schema v3.
public struct RROrderCaptureAggregateSummary: Equatable, Sendable, Codable {
    public let verdictCounts: [String: Int]
    public let coverage: RROrderDistributionSummary?
    public let collapsedCoverage: RROrderDistributionSummary?
    public let beatAccurateFraction: RROrderDistributionSummary?
    public let sessionsWithUntrustworthyBeatValues: Int
    public let sessionsWithUntrustworthyBeatSpread: Int

    public let exactDuplicateBeatRows: Int
    public let sessionsWithExactDuplicateBeatRows: Int

    public let sameSecondShadowDroppedRows: Int
    public let sessionsWithSameSecondShadowDrops: Int
    public let sameSecondShadowCoverage: RROrderDistributionSummary?
    public let sameSecondShadowBeatAccurateFraction: RROrderDistributionSummary?

    /// This remains an aggressive upper-bound diagnostic. It must not be interpreted as rows NOOP should
    /// delete in production because a steady real 1-second rhythm can legitimately trigger it.
    public let crossSecondUpperBoundDroppedRows: Int
    public let sessionsWithCrossSecondUpperBoundDrops: Int
    public let crossSecondUpperBoundCoverage: RROrderDistributionSummary?
    public let crossSecondUpperBoundBeatAccurateFraction: RROrderDistributionSummary?

    public let associations: RROrderCaptureAssociationSummary
    public let verdictStrata: [RROrderCaptureVerdictStratum]

    public init(records: [RROrderCorpusRecord]) {
        verdictCounts = records.reduce(into: [:]) { counts, record in
            counts[record.audit.captureDiagnostics.coverageVerdict, default: 0] += 1
        }
        coverage = RROrderDistributionSummary(records.map { $0.audit.captureDiagnostics.coverage })
        collapsedCoverage = RROrderDistributionSummary(records.map { $0.audit.captureDiagnostics.collapsedCoverage })
        beatAccurateFraction = RROrderDistributionSummary(records.map { $0.audit.captureDiagnostics.beatAccurateFraction })
        sessionsWithUntrustworthyBeatValues = records.filter { !$0.audit.captureDiagnostics.beatValuesTrustworthy }.count
        sessionsWithUntrustworthyBeatSpread = records.filter { !$0.audit.captureDiagnostics.beatSpreadTrustworthy }.count

        exactDuplicateBeatRows = records.reduce(0) { $0 + $1.audit.captureDiagnostics.exactDuplicateBeatCount }
        sessionsWithExactDuplicateBeatRows = records.filter { $0.audit.captureDiagnostics.exactDuplicateBeatCount > 0 }.count

        sameSecondShadowDroppedRows = records.reduce(0) { $0 + $1.audit.captureDiagnostics.sameSecondShadowDropped }
        sessionsWithSameSecondShadowDrops = records.filter { $0.audit.captureDiagnostics.sameSecondShadowDropped > 0 }.count
        sameSecondShadowCoverage = RROrderDistributionSummary(records.map { $0.audit.captureDiagnostics.sameSecondShadowCoverage })
        sameSecondShadowBeatAccurateFraction = RROrderDistributionSummary(records.map { $0.audit.captureDiagnostics.sameSecondShadowBeatAccurateFraction })

        crossSecondUpperBoundDroppedRows = records.reduce(0) { $0 + $1.audit.captureDiagnostics.crossSecondUpperBoundDropped }
        sessionsWithCrossSecondUpperBoundDrops = records.filter { $0.audit.captureDiagnostics.crossSecondUpperBoundDropped > 0 }.count
        crossSecondUpperBoundCoverage = RROrderDistributionSummary(records.map { $0.audit.captureDiagnostics.crossSecondUpperBoundCoverage })
        crossSecondUpperBoundBeatAccurateFraction = RROrderDistributionSummary(records.map { $0.audit.captureDiagnostics.crossSecondUpperBoundBeatAccurateFraction })

        associations = Self.associationSummary(records)
        let grouped = Dictionary(grouping: records, by: { $0.audit.captureDiagnostics.coverageVerdict })
        verdictStrata = grouped.keys.sorted().map { verdict in
            RROrderCaptureVerdictStratum(verdict: verdict, records: grouped[verdict] ?? [])
        }
    }

    private static func associationSummary(_ records: [RROrderCorpusRecord]) -> RROrderCaptureAssociationSummary {
        var coverageX: [Double] = [], coverageY: [Double] = []
        var collapsedX: [Double] = [], collapsedY: [Double] = []
        var accuracyX: [Double] = [], accuracyY: [Double] = []
        for record in records {
            guard let delta = record.audit.rmssdCurrentMinusMagnitudeMs else { continue }
            let y = abs(delta)
            let capture = record.audit.captureDiagnostics
            coverageX.append(capture.coverage); coverageY.append(y)
            collapsedX.append(capture.collapsedCoverage); collapsedY.append(y)
            accuracyX.append(capture.beatAccurateFraction); accuracyY.append(y)
        }
        return RROrderCaptureAssociationSummary(
            coveragePairCount: coverageX.count,
            coverageVsAbsoluteRmssdDeltaSpearman: spearman(coverageX, coverageY),
            collapsedCoveragePairCount: collapsedX.count,
            collapsedCoverageVsAbsoluteRmssdDeltaSpearman: spearman(collapsedX, collapsedY),
            beatAccuracyPairCount: accuracyX.count,
            beatAccuracyVsAbsoluteRmssdDeltaSpearman: spearman(accuracyX, accuracyY)
        )
    }

    private static func spearman(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 3 else { return nil }
        return pearson(ranks(x), ranks(y))
    }

    private static func ranks(_ values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var result = Array(repeating: 0.0, count: values.count)
        var i = 0
        while i < order.count {
            var j = i + 1
            while j < order.count && values[order[j]] == values[order[i]] { j += 1 }
            let rank = (Double(i + 1) + Double(j)) / 2.0
            for k in i..<j { result[order[k]] = rank }
            i = j
        }
        return result
    }

    private static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let mx = x.reduce(0, +) / Double(x.count)
        let my = y.reduce(0, +) / Double(y.count)
        var numerator = 0.0, dx2 = 0.0, dy2 = 0.0
        for i in x.indices {
            let dx = x[i] - mx, dy = y[i] - my
            numerator += dx * dy
            dx2 += dx * dx
            dy2 += dy * dy
        }
        guard dx2 > 0, dy2 > 0 else { return nil }
        return numerator / (dx2 * dy2).squareRoot()
    }
}

/// Top-level aggregate artifact. The existing statistical summary stays reusable, while capture quality is
/// kept explicit so reviewers do not conflate R-R ordering with coverage/over-count problems.
public struct RROrderCorpusAnalysisReport: Equatable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let corpus: RROrderCorpusSummary
    public let capture: RROrderCaptureAggregateSummary

    public static func analyze(_ records: [RROrderCorpusRecord], bootstrapIterations: Int = 2_000) throws -> Self {
        Self(
            schemaVersion: currentSchemaVersion,
            corpus: try RROrderCorpusSummary.summarize(records, bootstrapIterations: bootstrapIterations),
            capture: RROrderCaptureAggregateSummary(records: records)
        )
    }
}

public enum RROrderCorpusAnalysisEncoder {
    public static func encode(_ report: RROrderCorpusAnalysisReport, format: RROrderCorpusSummaryFormat) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(report)
            data.append(0x0A)
            return data
        case .markdown:
            var base = RROrderCorpusSummaryEncoder.markdown(report.corpus)
            base += captureMarkdown(report.capture)
            return Data(base.utf8)
        }
    }

    private static func captureMarkdown(_ c: RROrderCaptureAggregateSummary) -> String {
        var lines: [String] = [
            "\n## Capture quality and over-count shadows", "",
            "- Native coverage verdicts: \(dictionary(c.verdictCounts))",
            "- R-R coverage: \(distribution(c.coverage))",
            "- Same-second collapsed coverage: \(distribution(c.collapsedCoverage))",
            "- Beat-accurate fraction: \(percentDistribution(c.beatAccurateFraction))",
            "- Sessions below beat-value trust gate: \(c.sessionsWithUntrustworthyBeatValues)",
            "- Sessions with untrustworthy beat spread: \(c.sessionsWithUntrustworthyBeatSpread)",
            "- Exact duplicate beat rows: \(c.exactDuplicateBeatRows) across \(c.sessionsWithExactDuplicateBeatRows) session(s)",
            "- Same-second shadow drops: \(c.sameSecondShadowDroppedRows) across \(c.sessionsWithSameSecondShadowDrops) session(s)",
            "- Same-second shadow coverage: \(distribution(c.sameSecondShadowCoverage))",
            "- Same-second shadow beat accuracy: \(percentDistribution(c.sameSecondShadowBeatAccurateFraction))",
            "- Cross-second aggressive upper-bound drops: \(c.crossSecondUpperBoundDroppedRows) across \(c.sessionsWithCrossSecondUpperBoundDrops) session(s)",
            "- Cross-second upper-bound coverage: \(distribution(c.crossSecondUpperBoundCoverage))",
            "- Cross-second upper-bound beat accuracy: \(percentDistribution(c.crossSecondUpperBoundBeatAccurateFraction))",
            "", "### Capture/effect associations", "",
            "- Coverage vs |RMSSD delta| Spearman: \(number(c.associations.coverageVsAbsoluteRmssdDeltaSpearman)) (n=\(c.associations.coveragePairCount))",
            "- Collapsed coverage vs |RMSSD delta| Spearman: \(number(c.associations.collapsedCoverageVsAbsoluteRmssdDeltaSpearman)) (n=\(c.associations.collapsedCoveragePairCount))",
            "- Beat accuracy vs |RMSSD delta| Spearman: \(number(c.associations.beatAccuracyVsAbsoluteRmssdDeltaSpearman)) (n=\(c.associations.beatAccuracyPairCount))",
            "", "### Coverage-verdict strata", "",
            "| Verdict | Sessions | Paired RMSSD | Median delta ms | Median coverage | Median beat accuracy |",
            "|---|---:|---:|---:|---:|---:|",
        ]
        for stratum in c.verdictStrata {
            lines.append("| \(stratum.verdict) | \(stratum.sessionCount) | \(stratum.pairedRmssdCount) | \(number(stratum.rmssdDeltaMs.distribution?.median)) | \(number(stratum.coverage?.median)) | \(percent(stratum.beatAccurateFraction?.median)) |")
        }
        lines += ["", "> The 1-second cross-second shadow is intentionally an aggressive upper bound. Drops there are not rows NOOP should automatically de-duplicate.", ""]
        return lines.joined(separator: "\n")
    }

    private static func dictionary(_ values: [String: Int]) -> String {
        values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: ", ")
    }

    private static func distribution(_ d: RROrderDistributionSummary?) -> String {
        guard let d else { return "n/a" }
        return "n=\(d.count), mean \(number(d.mean)), median \(number(d.median)), p10-p90 \(number(d.p10))-\(number(d.p90))"
    }

    private static func percentDistribution(_ d: RROrderDistributionSummary?) -> String {
        guard let d else { return "n/a" }
        return "n=\(d.count), mean \(percent(d.mean)), median \(percent(d.median)), p10-p90 \(percent(d.p10))-\(percent(d.p90))"
    }

    private static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0 * 100) } ?? "n/a"
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(format: "%.3f", $0) } ?? "n/a"
    }
}
