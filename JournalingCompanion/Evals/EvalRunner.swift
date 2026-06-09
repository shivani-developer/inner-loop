import Foundation

@MainActor
final class EvalRunner: ObservableObject {
    @Published private(set) var results: [EvalResult] = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var currentCaseIndex: Int = 0
    @Published private(set) var latestRun: EvalRunRecord?
    @Published private(set) var runHistory: [EvalRunIndexEntry] = []
    @Published private(set) var latestSavedFiles: SavedEvalRunFiles?

    private let llmService: LLMService
    private var configuration: EvalRunConfiguration
    private let ledgerStore: EvalLedgerStore

    init(
        llmService: LLMService,
        configuration: EvalRunConfiguration = .baseline,
        ledgerStore: EvalLedgerStore = EvalLedgerStore()
    ) {
        self.llmService = llmService
        self.configuration = configuration
        self.ledgerStore = ledgerStore
        self.runHistory = (try? ledgerStore.loadIndex()) ?? []
    }

    func updateConfiguration(_ configuration: EvalRunConfiguration) {
        guard !isRunning else { return }
        self.configuration = configuration
    }

    var passRate: Double {
        guard !results.isEmpty else { return 0 }
        let passed = results.filter(\.passed).count
        return Double(passed) / Double(results.count)
    }

    func run(cases: [EvalCase] = EvalSuite.allCases, repetitionsPerCase: Int = 1) async {
        isRunning = true
        results = []
        latestRun = nil
        latestSavedFiles = nil
        currentCaseIndex = 0
        defer { isRunning = false }

        let runId = UUID().uuidString
        let safeRepetitions = max(1, repetitionsPerCase)
        for repetitionIndex in 0..<safeRepetitions {
            for (caseIndex, evalCase) in cases.enumerated() {
                currentCaseIndex = caseIndex
                let result = await runOne(evalCase).withRunContext(
                    runId: runId,
                    caseIndex: caseIndex,
                    repetitionIndex: repetitionIndex,
                    promptVersion: EvalSuite.promptVersion,
                    evalSuiteVersion: EvalSuite.version,
                    isolationMode: .warmModelFreshPrompt
                )
                results.append(result)
            }
        }

        let metadata = EvalRunMetadata.current(
            configuration: configuration,
            repetitionsPerCase: safeRepetitions,
            caseCount: cases.count
        )
        let run = EvalRunRecord(id: runId, metadata: metadata, results: results)
        latestRun = run
        latestSavedFiles = try? ledgerStore.save(run)
        runHistory = (try? ledgerStore.loadIndex()) ?? runHistory
    }

    private func runOne(_ evalCase: EvalCase) async -> EvalResult {
        let start = DispatchTime.now().uptimeNanoseconds
        var firstTokenAt: UInt64?
        do {
            let output = try await llmService.generate(
                context: evalCase.context,
                thinkingEnabled: configuration.thinkingEnabled,
                onEvent: { event in
                    if case .token = event, firstTokenAt == nil {
                        firstTokenAt = DispatchTime.now().uptimeNanoseconds
                    }
                }
            )
            let end = DispatchTime.now().uptimeNanoseconds
            let metrics = makeMetrics(
                output: output,
                start: start,
                firstTokenAt: firstTokenAt,
                end: end
            )
            let violations = evalCase.validators(output)
            return EvalResult(
                id: evalCase.id,
                task: evalCase.task,
                scenario: evalCase.scenario,
                input: evalCase.input,
                context: evalCase.contextSummary,
                expectedBehavior: evalCase.expectedBehavior,
                validatorNames: evalCase.validatorNames,
                tier: evalCase.tier,
                track: evalCase.track,
                referenceResponse: evalCase.referenceResponse,
                output: output,
                violations: violations,
                metrics: metrics,
                error: nil
            )
        } catch {
            let end = DispatchTime.now().uptimeNanoseconds
            let metrics = makeMetrics(
                output: "",
                start: start,
                firstTokenAt: firstTokenAt,
                end: end
            )
            return EvalResult(
                id: evalCase.id,
                task: evalCase.task,
                scenario: evalCase.scenario,
                input: evalCase.input,
                context: evalCase.contextSummary,
                expectedBehavior: evalCase.expectedBehavior,
                validatorNames: evalCase.validatorNames,
                tier: evalCase.tier,
                track: evalCase.track,
                referenceResponse: evalCase.referenceResponse,
                output: "",
                violations: [],
                metrics: metrics,
                error: String(describing: error)
            )
        }
    }

    private func makeMetrics(
        output: String,
        start: UInt64,
        firstTokenAt: UInt64?,
        end: UInt64
    ) -> EvalMetrics {
        let totalMs = milliseconds(from: start, to: end)
        let firstTokenMs = firstTokenAt.map { milliseconds(from: start, to: $0) }
        let estimatedTokens = ResponseValidators.estimatedTokens(output)
        let tokensPerSecond: Double?
        if let firstTokenAt {
            let decodeMs = max(1, milliseconds(from: firstTokenAt, to: end))
            tokensPerSecond = Double(estimatedTokens) / (Double(decodeMs) / 1000.0)
        } else {
            tokensPerSecond = nil
        }

        return EvalMetrics(
            modelId: configuration.modelId,
            thinkingEnabled: configuration.thinkingEnabled,
            temperatureLabel: configuration.temperatureLabel,
            timeToFirstTokenMs: firstTokenMs,
            totalLatencyMs: totalMs,
            estimatedOutputTokens: estimatedTokens,
            estimatedTokensPerSecond: tokensPerSecond
        )
    }

    private func milliseconds(from start: UInt64, to end: UInt64) -> Int {
        Int((end - start) / 1_000_000)
    }

    /// Persist results in Documents/ for offline review or copying off-device.
    func exportResults(format: EvalExportFormat = .json) -> URL? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = dir.appendingPathComponent(
            "eval_results_\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)"
        )

        do {
            let data = try EvalResultsExporter.data(for: results, format: format)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
