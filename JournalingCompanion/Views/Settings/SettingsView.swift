import SwiftUI
import RunAnywhere

/// Centralized `@AppStorage` keys so call sites in different files agree on the same string.
enum SettingsKeys {
    static let ttsEnabled = "ttsEnabled"
    static let faceIDEnabled = "faceIDEnabled"
    static let thinkingMode = "thinkingMode"
}

struct SettingsView: View {
    @AppStorage(SettingsKeys.ttsEnabled) private var ttsEnabled: Bool = true
    @AppStorage(SettingsKeys.faceIDEnabled) private var faceIDEnabled: Bool = true
    @AppStorage(SettingsKeys.thinkingMode) private var thinkingMode: Bool = true
    @AppStorage(ModelConfig.selectedModelIdKey) private var selectedModelId: String = ModelConfig.defaultModelId
    @State private var showingOnboarding = false
    @State private var modelStatus: String?
    @State private var isPreparingModel = false

    let llmService: LLMService
    let memoryRepository: MemoryRepository

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Deep thinking", isOn: $thinkingMode)
                } header: {
                    Text("Conversation")
                } footer: {
                    Text("When on, the model reasons silently before replying. Responses are more thoughtful but take 15-25 seconds. When off, replies arrive in a few seconds but are less considered.")
                }

                Section("Voice") {
                    Toggle("Read responses aloud", isOn: $ttsEnabled)
                }

                Section("Privacy") {
                    Toggle("Require Face ID on launch", isOn: $faceIDEnabled)
                }

                Section("Profile") {
                    Button("Edit profile") {
                        showingOnboarding = true
                    }
                }

                Section("Model") {
                    Picker("Model", selection: $selectedModelId) {
                        ForEach(ModelConfig.availableModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    LabeledContent("Role", value: ModelConfig.selectedModel.role)
                    LabeledContent("Approx size", value: "~\(ModelConfig.selectedModel.approximateSizeMB)MB")
                    LabeledContent("Inference", value: "RunAnywhere SDK")
                    LabeledContent("Speech", value: "WhisperKit")

                    Button {
                        Task { await prepareSelectedModel() }
                    } label: {
                        if isPreparingModel {
                            Label("Preparing model...", systemImage: "hourglass")
                        } else {
                            Label("Download / load selected model", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(isPreparingModel)

                    if let modelStatus {
                        Text(modelStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Developer") {
                    NavigationLink("Model Lab") {
                        EvalView(llmService: llmService)
                    }
                }
            }
            .navigationTitle("Settings")
            .onChange(of: selectedModelId) { _, _ in
                modelStatus = "Selection saved. Download and load it before testing."
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView(
                    llmService: llmService,
                    memoryRepository: memoryRepository,
                    onComplete: { showingOnboarding = false }
                )
            }
        }
    }

    private func prepareSelectedModel() async {
        let model = ModelConfig.selectedModel
        isPreparingModel = true
        modelStatus = "Checking \(model.displayName)..."
        defer { isPreparingModel = false }

        if (try? await RunAnywhere.loadModel(model.id)) != nil {
            modelStatus = "\(model.displayName) is loaded."
            return
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
            modelStatus = "\(model.displayName) is ready."
        } catch {
            modelStatus = "Model setup failed: \(error.localizedDescription)"
        }
    }
}
