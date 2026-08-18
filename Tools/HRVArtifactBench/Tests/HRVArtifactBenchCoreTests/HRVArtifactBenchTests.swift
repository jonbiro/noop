import XCTest
@testable import HRVArtifactBenchCore

final class HRVArtifactBenchTests: XCTestCase {
    func testCleanRespiratoryVariabilityIsNotOvercorrected() {
        let clean = HRVArtifactBenchmark.builtInScenarios()[0].truth
        let result = ArtifactCandidate.correct(clean)

        XCTAssertEqual(result.classes.count, clean.count)
        XCTAssertEqual(result.classes.filter { $0 != .normal }.count, 0)
        XCTAssertEqual(result.correctedCount, 0)
        XCTAssertEqual(result.droppedCount, 0)
        XCTAssertEqual(result.cleanFraction, 1, accuracy: 1e-12)
        XCTAssertEqual(result.nn, clean)
    }

    func testIsolatedGrossOutlierIsCorrectedRatherThanLeftInSeries() {
        let scenario = HRVArtifactBenchmark.builtInScenarios().first { $0.name == "gross_high_outlier" }!
        let result = ArtifactCandidate.correct(scenario.observed)

        XCTAssertEqual(result.correctedCount, 1)
        XCTAssertEqual(result.droppedCount, 0)
        XCTAssertEqual(result.nn.count, scenario.truth.count)
        XCTAssertNotEqual(result.classes[150], .normal)
        XCTAssertLessThan(abs(result.nn[150] - scenario.truth[150]), 80)
        let truth = HRVArtifactBenchmark.rawRmssd(scenario.truth)!
        let corrected = HRVArtifactBenchmark.rawRmssd(result.nn)!
        XCTAssertLessThan(abs(corrected - truth), 2.0)
    }

    func testTwoBeatArtifactRunIsDroppedAndNeverInterpolated() {
        let scenario = HRVArtifactBenchmark.builtInScenarios().first { $0.name == "two_beat_artifact_run" }!
        let result = ArtifactCandidate.correct(scenario.observed)

        XCTAssertGreaterThanOrEqual(result.droppedCount, 2)
        XCTAssertEqual(result.correctedCount, 0)
        XCTAssertLessThanOrEqual(result.nn.count, scenario.observed.count - 2)
    }

    func testShortSeriesFailsHonestlyWithoutInterpolation() {
        let result = ArtifactCandidate.correct([800, 2_500])
        XCTAssertEqual(result.classes, [.normal, .longShort])
        XCTAssertEqual(result.nn, [800])
        XCTAssertEqual(result.correctedCount, 0)
        XCTAssertEqual(result.droppedCount, 1)
    }

    func testBenchmarkCoversMultipleArtifactClassesAndIsDeterministic() {
        let a = HRVArtifactBenchmark.run()
        let b = HRVArtifactBenchmark.run()
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.schemaVersion, 1)
        XCTAssertEqual(a.measurements.count, 6)
        XCTAssertEqual(a.measurements.map(\.scenario), [
            "clean_respiratory_variability",
            "isolated_long_interval",
            "isolated_short_interval",
            "gross_high_outlier",
            "two_beat_artifact_run",
            "moderate_ectopic_jump",
        ])
        XCTAssertTrue(a.measurements.allSatisfy { $0.noopRmssdMs != nil })
        XCTAssertTrue(a.measurements.allSatisfy { $0.candidateRmssdMs != nil })
    }

    func testCleanScenarioDoesNotCreateArtificialBenchmarkWinner() {
        let clean = HRVArtifactBenchmark.run().measurements.first { $0.scenario == "clean_respiratory_variability" }!
        XCTAssertEqual(clean.truthRmssdMs, clean.candidateRmssdMs!, accuracy: 1e-12)
        XCTAssertEqual(clean.candidateAbsoluteErrorMs!, 0, accuracy: 1e-12)
        XCTAssertEqual(clean.candidateCorrectedCount, 0)
        XCTAssertEqual(clean.candidateDroppedCount, 0)
    }

    func testEncodersAreDeterministicAndExplainCandidateStatus() throws {
        let report = HRVArtifactBenchmark.run()
        XCTAssertEqual(try HRVArtifactBenchmarkEncoder.json(report), try HRVArtifactBenchmarkEncoder.json(report))
        let markdown = String(decoding: HRVArtifactBenchmarkEncoder.markdown(report), as: UTF8.self)
        XCTAssertTrue(markdown.contains("tool-only comparison"))
        XCTAssertTrue(markdown.contains("clean_respiratory_variability"))
        XCTAssertTrue(markdown.contains("Candidate wins:"))
    }
}
