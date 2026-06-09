import SwiftUI
import CoreData

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isProcessing: Bool = false
    @Published var isComplete: Bool = false

    private let llmService: LLMService

    init(llmService: LLMService) {
        self.llmService = llmService
    }

    func skip() async {
        await saveProfile(summary: nil, skipped: true)
    }

    func submit() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isProcessing = true

        var compressed: String? = nil
        do {
            let context = LLMContext(
                systemPrompt: PromptTemplates.profileCompressionPrompt(rawInput: trimmed),
                userProfile: nil,
                lifeStory: nil,
                weeklySummaries: [],
                recentSessions: [],
                currentSession: []
            )
            compressed = try await llmService.generate(
                context: context,
                thinkingEnabled: false,
                onEvent: { _ in }
            )
        } catch {
            // Save raw input as fallback if LLM is unavailable
            compressed = trimmed
        }

        await saveProfile(summary: compressed, skipped: false)
        isProcessing = false
    }

    private func saveProfile(summary: String?, skipped: Bool) async {
        let ctx = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<CDUserProfile> = CDUserProfile.fetchRequest()
        let profile = (try? ctx.fetch(request))?.first ?? CDUserProfile(context: ctx)
        if profile.id == nil { profile.id = UUID() }
        profile.profileSummary = summary
        profile.onboardingSkipped = skipped
        if profile.createdAt == nil { profile.createdAt = Date() }
        try? ctx.save()
        isComplete = true
    }
}

struct OnboardingView: View {
    @StateObject private var viewModel: OnboardingViewModel
    let onComplete: () -> Void

    init(
        llmService: LLMService,
        memoryRepository: MemoryRepository,
        onComplete: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(llmService: llmService))
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("Before we get started, tell me a bit about yourself. Who you are, what your life looks like right now — whatever feels relevant.")
                .font(.body)
                .padding(.horizontal)

            TextEditor(text: $viewModel.inputText)
                .frame(height: 160)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .disabled(viewModel.isProcessing)

            HStack {
                Button("Skip") {
                    Task { await viewModel.skip() }
                }
                .foregroundStyle(.secondary)
                .disabled(viewModel.isProcessing)

                Spacer()

                Button("Continue") {
                    Task { await viewModel.submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.inputText.isEmpty || viewModel.isProcessing)
            }
            .padding(.horizontal)

            if viewModel.isProcessing {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
            Spacer()
        }
        .onChange(of: viewModel.isComplete) { _, complete in
            if complete { onComplete() }
        }
    }
}
