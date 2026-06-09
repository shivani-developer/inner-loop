import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var aiPrompt: String? = nil
    @Published var isLoadingPrompt: Bool = false

    let llmService: LLMService
    let memoryRepository: MemoryRepository

    static let defaultPrompts = [
        "What's on your mind today?",
        "How are you feeling right now?"
    ]

    init(llmService: LLMService, memoryRepository: MemoryRepository) {
        self.llmService = llmService
        self.memoryRepository = memoryRepository
    }

    func loadOpeningPrompt() async {
        isLoadingPrompt = true
        defer { isLoadingPrompt = false }
        do {
            let memoryContext = try await memoryRepository.loadContext(for: Date())
            let promptContext = LLMContext(
                systemPrompt: PromptTemplates.openingPromptContext(date: Date()),
                userProfile: memoryContext.userProfile,
                lifeStory: memoryContext.lifeStory,
                weeklySummaries: memoryContext.weeklySummaries,
                recentSessions: memoryContext.recentSessions,
                currentSession: []
            )
            let result = try await llmService.generate(
                context: promptContext,
                thinkingEnabled: false,
                onEvent: { _ in }
            )
            aiPrompt = result.isEmpty ? nil : result
        } catch {
            aiPrompt = nil
        }
    }
}

/// Wrapper used to drive `fullScreenCover(item:)` for opening a session. Going through an
/// `Identifiable` value (rather than a separate Bool + optional string) avoids a SwiftUI race
/// where the cover renders its content closure before a synchronous `@State` write has
/// propagated, producing a blank screen.
private struct OpeningPrompt: Identifiable {
    let id = UUID()
    let text: String
}

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @State private var freeTextInput: String = ""
    @State private var openingPrompt: OpeningPrompt? = nil

    private let transcriber: SpeechTranscriber
    private let ttsService: TTSService

    init(
        llmService: LLMService,
        memoryRepository: MemoryRepository,
        transcriber: SpeechTranscriber,
        ttsService: TTSService
    ) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(
            llmService: llmService,
            memoryRepository: memoryRepository
        ))
        self.transcriber = transcriber
        self.ttsService = ttsService
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    promptCardsSection
                    freeTextSection
                }
                .padding()
            }
            .navigationBarHidden(true)
            .task { await viewModel.loadOpeningPrompt() }
            .fullScreenCover(item: $openingPrompt) { prompt in
                SessionView(
                    coordinator: DefaultSessionCoord(
                        llmService: viewModel.llmService,
                        memoryRepository: viewModel.memoryRepository
                    ),
                    transcriber: transcriber,
                    ttsService: ttsService,
                    openingPrompt: prompt.text
                )
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.title)
                .fontWeight(.semibold)
            Text(Date(), style: .date)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var promptCardsSection: some View {
        VStack(spacing: 12) {
            if viewModel.isLoadingPrompt {
                PromptCard(text: "Loading today's prompt...", isLoading: true) {}
            } else if let aiPrompt = viewModel.aiPrompt {
                PromptCard(text: aiPrompt, isLoading: false) {
                    openingPrompt = OpeningPrompt(text: aiPrompt)
                }
            }
            ForEach(HomeViewModel.defaultPrompts, id: \.self) { prompt in
                PromptCard(text: prompt, isLoading: false) {
                    openingPrompt = OpeningPrompt(text: prompt)
                }
            }
        }
    }

    private var freeTextSection: some View {
        HStack {
            TextField("Or start writing...", text: $freeTextInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    guard !freeTextInput.isEmpty else { return }
                    openingPrompt = OpeningPrompt(text: freeTextInput)
                    freeTextInput = ""
                }
            Button {
                openingPrompt = OpeningPrompt(text: "")
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
        }
    }
}

struct PromptCard: View {
    let text: String
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.body)
                .foregroundStyle(isLoading ? .secondary : .primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
