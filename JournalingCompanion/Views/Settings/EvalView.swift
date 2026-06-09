import SwiftUI
import RunAnywhere

struct EvalView: View {
    @StateObject private var runner: EvalRunner
    @AppStorage(ModelConfig.selectedModelIdKey) private var selectedModelId: String = ModelConfig.defaultModelId
    @State private var repetitionsPerCase = 5
    @State private var modelStatus: String?
    @State private var isPreparingModel = false

    init(llmService: LLMService) {
        _runner = StateObject(wrappedValue: EvalRunner(llmService: llmService))
    }

    var body: some View {
        List {
            Section("Baseline") {
                Picker("Model", selection: $selectedModelId) {
                    ForEach(ModelConfig.availableModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                LabeledContent("Model ID", value: ModelConfig.modelId)
                LabeledContent("Inference", value: "RunAnywhere SDK")
                LabeledContent("Temperature", value: EvalRunConfiguration.baseline.temperatureLabel ?? "Default")
                LabeledContent("Thinking", value: EvalRunConfiguration.baseline.thinkingEnabled ? "On" : "Off")
                LabeledContent("Suite", value: EvalSuite.version)
                LabeledContent("Prompt", value: EvalSuite.promptVersion)
                LabeledContent("Eval cases", value: "\(EvalSuite.allCases.count)")
                Stepper(value: $repetitionsPerCase, in: 1...5) {
                    LabeledContent("Repetitions", value: "\(repetitionsPerCase) per case")
                }
                .disabled(runner.isRunning || isPreparingModel)
                if let modelStatus {
                    Text(modelStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                summaryRow
                runRow
                exportRow
            }

            if let latestRun = runner.latestRun {
                Section("Latest run") {
                    LabeledContent("Run ID", value: shortRunId(latestRun.id))
                    LabeledContent("Attempts", value: "\(latestRun.summary.totalAttempts)")
                    LabeledContent("Pass rate", value: percent(latestRun.summary.passRate))
                    LabeledContent("Avg TTFT", value: milliseconds(latestRun.summary.averageTimeToFirstTokenMs))
                    LabeledContent("Avg total", value: milliseconds(latestRun.summary.averageTotalLatencyMs))
                    LabeledContent("Avg tok/s", value: tokensPerSecond(latestRun.summary.averageEstimatedTokensPerSecond))
                }
            }

            if !runner.runHistory.isEmpty {
                Section("Run history") {
                    ForEach(runner.runHistory.prefix(8)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(shortRunId(entry.id))
                                    .font(.caption.monospaced())
                                Spacer()
                                Text(percent(entry.passRate))
                                    .font(.caption)
                                    .foregroundStyle(entry.passRate >= 0.8 ? .green : .orange)
                            }
                            Text("\(entry.modelDisplayName) · \(entry.evalSuiteVersion) · \(milliseconds(entry.averageTotalLatencyMs))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ForEach(runner.results) { result in
                Section(header: header(for: result)) {
                    Text(result.scenario)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let error = result.error {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else {
                        Text(result.output.isEmpty ? "(empty)" : result.output)
                            .font(.body)
                    }

                    ForEach(result.violations.indices, id: \.self) { i in
                        let violation = result.violations[i]
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(violation.kind.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(violation.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    metricRow(for: result)
                }
            }
        }
        .navigationTitle("Model Lab")
        .onAppear {
            runner.updateConfiguration(.baseline)
        }
        .onChange(of: selectedModelId) { _, _ in
            modelStatus = "Selection saved. Model Lab will download/load it before the next run."
            runner.updateConfiguration(.baseline)
        }
    }

    // MARK: - Subviews

    private var summaryRow: some View {
        HStack {
            Text("Pass rate")
                .fontWeight(.medium)
            Spacer()
            if runner.results.isEmpty {
                Text("Not run").foregroundStyle(.secondary)
            } else {
                let passed = runner.results.filter(\.passed).count
                Text("\(passed)/\(runner.results.count) (\(Int(runner.passRate * 100))%)")
                    .foregroundStyle(runner.passRate >= 0.8 ? .green : .orange)
            }
        }
    }

    private var runRow: some View {
        Button {
            Task {
                guard await prepareSelectedModel() else { return }
                runner.updateConfiguration(.baseline)
                await runner.run(repetitionsPerCase: repetitionsPerCase)
            }
        } label: {
            if isPreparingModel {
                Label("Preparing model...", systemImage: "hourglass")
            } else if runner.isRunning {
                Label("Running case \(runner.currentCaseIndex + 1)...", systemImage: "hourglass")
            } else {
                Label("Run all evals", systemImage: "play.fill")
            }
        }
        .disabled(runner.isRunning || isPreparingModel)
    }

    private func prepareSelectedModel() async -> Bool {
        let model = ModelConfig.selectedModel
        isPreparingModel = true
        modelStatus = "Checking \(model.displayName)..."
        defer { isPreparingModel = false }

        if (try? await RunAnywhere.loadModel(model.id)) != nil {
            modelStatus = "\(model.displayName) is loaded."
            return true
        }

        do {
            modelStatus = "Downloading \(model.displayName)..."
            let progressStream = try await RunAnywhere.downloadModel(model.id)
            for await update in progressStream {
                modelStatus = "Downloading \(model.displayName): \(Int(update.overallProgress * 100))%"
                if update.stage == .completed { break }
            }
            modelStatus = "Loading \(model.displayName)..."
            try await RunAnywhere.loadModel(model.id)
            modelStatus = "\(model.displayName) is loaded."
            return true
        } catch {
            modelStatus = "Model setup failed: \(error.localizedDescription)"
            return false
        }
    }

    private var exportRow: some View {
        Group {
            if let latestSavedFiles = runner.latestSavedFiles, !runner.isRunning {
                HStack {
                    Text("Export results")
                        .foregroundStyle(.secondary)
                    Spacer()

                    ShareLink(item: latestSavedFiles.resultsJSONURL) {
                        Label("JSON", systemImage: "doc.text")
                    }

                    ShareLink(item: latestSavedFiles.resultsCSVURL) {
                        Label("CSV", systemImage: "tablecells")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func header(for result: EvalResult) -> some View {
        HStack {
            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.passed ? .green : .red)
            Text(result.id)
                .font(.caption.monospaced())
        }
    }

    private func metricRow(for result: EvalResult) -> some View {
        let metrics = result.metrics
        let ttft = metrics.timeToFirstTokenMs.map { "\($0) ms" } ?? "n/a"
        let tokensPerSecond = metrics.estimatedTokensPerSecond.map { String(format: "%.1f tok/s", $0) } ?? "n/a"

        return VStack(alignment: .leading, spacing: 4) {
            Text("TTFT \(ttft) · Total \(metrics.totalLatencyMs) ms · \(tokensPerSecond)")
            Text("\(metrics.estimatedOutputTokens) estimated output tokens")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private func shortRunId(_ id: String) -> String {
        String(id.prefix(8))
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func milliseconds(_ value: Int?) -> String {
        guard let value else { return "n/a" }
        return "\(value) ms"
    }

    private func tokensPerSecond(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f tok/s", value)
    }
}

#Preview {
    NavigationStack {
        EvalView(llmService: PreviewLLMService())
    }
}

private final class PreviewLLMService: LLMService {
    func loadModel() async throws {}

    func generate(
        context: LLMContext,
        thinkingEnabled: Bool,
        onEvent: @escaping (GenerationEvent) -> Void
    ) async throws -> String {
        onEvent(.token("What part of restarting this project feels least clear right now?"))
        return "What part of restarting this project feels least clear right now?"
    }
}
