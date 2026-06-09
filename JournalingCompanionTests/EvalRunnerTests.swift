import XCTest
@testable import JournalingCompanion

@MainActor
final class EvalRunnerTests: XCTestCase {

    func testRunRecordsStreamingMetricsFromFirstVisibleToken() async throws {
        let llm = StreamingEvalLLMService()
        let runner = EvalRunner(
            llmService: llm,
            configuration: EvalRunConfiguration(
                modelId: "test-model",
                modelDisplayName: "Test Model",
                thinkingEnabled: true,
                temperatureLabel: "test-temp"
            )
        )
        let evalCase = EvalCase(
            id: "metrics.visible_token",
            task: .socraticResponse,
            scenario: "Metrics should ignore thinking and measure visible token timing.",
            context: LLMContext(
                systemPrompt: "Maximum 60 tokens.",
                userProfile: nil,
                lifeStory: nil,
                weeklySummaries: [],
                recentSessions: [],
                currentSession: [
                    ChatMessage(role: "user", content: "My project responses feel too generic.")
                ]
            ),
            validators: { _ in [] }
        )

        await runner.run(cases: [evalCase])

        let result = try XCTUnwrap(runner.results.first)
        XCTAssertEqual(result.metrics.modelId, "test-model")
        XCTAssertTrue(result.metrics.thinkingEnabled)
        XCTAssertEqual(result.metrics.temperatureLabel, "test-temp")
        XCTAssertNotNil(result.metrics.timeToFirstTokenMs)
        XCTAssertGreaterThanOrEqual(result.metrics.timeToFirstTokenMs ?? -1, 0)
        XCTAssertGreaterThanOrEqual(result.metrics.totalLatencyMs, result.metrics.timeToFirstTokenMs ?? 0)
        XCTAssertGreaterThan(result.metrics.estimatedOutputTokens, 0)
        XCTAssertNotNil(result.metrics.estimatedTokensPerSecond)
    }

    func testRunSavesLedgerRunWithRepetitionsAndRunContext() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let ledger = EvalLedgerStore(rootDirectory: root)
        let llm = StreamingEvalLLMService()
        let runner = EvalRunner(llmService: llm, ledgerStore: ledger)
        let evalCase = EvalCase(
            id: "case.one",
            task: .socraticResponse,
            scenario: "Scenario",
            context: LLMContext(
                systemPrompt: "Maximum 60 tokens.",
                userProfile: nil,
                lifeStory: nil,
                weeklySummaries: [],
                recentSessions: [],
                currentSession: [
                    ChatMessage(role: "user", content: "My app responses feel generic.")
                ]
            ),
            validators: { _ in [] }
        )

        await runner.run(cases: [evalCase], repetitionsPerCase: 2)

        let latestRun = try XCTUnwrap(runner.latestRun)
        XCTAssertEqual(latestRun.results.count, 2)
        XCTAssertEqual(latestRun.results.map(\.repetitionIndex), [0, 1])
        XCTAssertEqual(latestRun.results.map(\.caseIndex), [0, 0])
        XCTAssertEqual(latestRun.results.first?.runId, latestRun.id)
        XCTAssertEqual(try ledger.loadIndex().count, 1)
    }
}

private final class StreamingEvalLLMService: LLMService {
    func loadModel() async throws {}

    func generate(
        context: LLMContext,
        thinkingEnabled: Bool,
        onEvent: @escaping (GenerationEvent) -> Void
    ) async throws -> String {
        onEvent(.thinking)
        try await Task.sleep(nanoseconds: 1_000_000)
        onEvent(.token("When your project"))
        try await Task.sleep(nanoseconds: 1_000_000)
        onEvent(.token(" responses feel generic, what specific input exposed that?"))
        return "When your project responses feel generic, what specific input exposed that?"
    }
}
