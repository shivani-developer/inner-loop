import XCTest
@testable import JournalingCompanion

final class EvalLedgerStoreTests: XCTestCase {
    func testSummaryComputesAggregateMetricsAndViolationCounts() {
        let results = [
            Self.result(
                id: "case.one",
                violations: [],
                ttft: 100,
                total: 900,
                tokens: 18,
                tokensPerSecond: 22.5
            ),
            Self.result(
                id: "case.two",
                violations: [
                    ResponseValidators.Violation(kind: .genericResponse, detail: "Too vague"),
                    ResponseValidators.Violation(kind: .notAnchoredToUserInput, detail: "No overlap"),
                ],
                ttft: 200,
                total: 1100,
                tokens: 12,
                tokensPerSecond: 12.0
            ),
        ]

        let summary = EvalRunSummary(results: results)

        XCTAssertEqual(summary.totalAttempts, 2)
        XCTAssertEqual(summary.passedAttempts, 1)
        XCTAssertEqual(summary.passRate, 0.5)
        XCTAssertEqual(summary.averageTimeToFirstTokenMs, 150)
        XCTAssertEqual(summary.averageTotalLatencyMs, 1000)
        XCTAssertEqual(summary.averageEstimatedOutputTokens, 15)
        XCTAssertEqual(summary.failureCountsByViolationKind["genericResponse"], 1)
        XCTAssertEqual(summary.failureCountsByViolationKind["notAnchoredToUserInput"], 1)
    }

    func testSaveRunWritesRunFilesAndIndexEntry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = EvalLedgerStore(rootDirectory: root)
        let metadata = EvalRunMetadata(
            appVersion: "1.0",
            buildNumber: "1",
            deviceName: "Test Device",
            osVersion: "26.0",
            modelId: "qwen-test",
            modelDisplayName: "Qwen Test",
            thinkingEnabled: false,
            temperatureLabel: "0.7",
            promptVersion: "prompt-v1",
            evalSuiteVersion: "suite-v2",
            isolationMode: .warmModelFreshPrompt,
            repetitionsPerCase: 1,
            caseCount: 1,
            notes: nil
        )
        let run = EvalRunRecord(
            id: "run-1",
            createdAt: Date(timeIntervalSince1970: 0),
            metadata: metadata,
            results: [
                Self.result(
                    id: "case.one",
                    violations: [],
                    ttft: 100,
                    total: 900,
                    tokens: 12,
                    tokensPerSecond: 13
                ),
            ]
        )

        let saved = try store.save(run)
        let index = try store.loadIndex()

        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.runJSONURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.resultsCSVURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.resultsJSONURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.summaryJSONURL.path))
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index.first?.id, "run-1")
    }

    private static func result(
        id: String,
        violations: [ResponseValidators.Violation],
        ttft: Int?,
        total: Int,
        tokens: Int,
        tokensPerSecond: Double?
    ) -> EvalResult {
        EvalResult(
            id: id,
            task: .socraticResponse,
            scenario: "Scenario",
            output: "Output",
            violations: violations,
            metrics: EvalMetrics(
                modelId: "test-model",
                thinkingEnabled: false,
                temperatureLabel: "0.7",
                timeToFirstTokenMs: ttft,
                totalLatencyMs: total,
                estimatedOutputTokens: tokens,
                estimatedTokensPerSecond: tokensPerSecond
            ),
            error: nil
        )
    }
}
