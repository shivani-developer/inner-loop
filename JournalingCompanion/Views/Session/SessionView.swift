import SwiftUI

enum AssistantPhase: Equatable {
    case idle
    case thinking
    case responding
}

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var messages: [MessageModel] = []
    @Published var assistantPhase: AssistantPhase = .idle
    @Published var assistantStreamingText: String = ""
    @Published var voicePartial: String = ""
    @Published var isRecording: Bool = false
    @Published var isTranscribing: Bool = false
    @Published var isClosing: Bool = false
    @Published var sessionSummary: SessionSummary? = nil
    @Published var error: String? = nil

    private let coordinator: SessionCoordinator
    private let transcriber: SpeechTranscriber
    private let ttsService: TTSService
    private let openingPrompt: String

    var isBusy: Bool { assistantPhase != .idle || isTranscribing || isClosing }

    init(
        coordinator: SessionCoordinator,
        transcriber: SpeechTranscriber,
        ttsService: TTSService,
        openingPrompt: String
    ) {
        self.coordinator = coordinator
        self.transcriber = transcriber
        self.ttsService = ttsService
        self.openingPrompt = openingPrompt
    }

    func start() async {
        await coordinator.startSession(with: openingPrompt)
        if !openingPrompt.isEmpty {
            messages.append(MessageModel(
                id: UUID(),
                sessionId: UUID(),
                role: "assistant",
                content: openingPrompt,
                inputMode: "text",
                createdAt: Date()
            ))
        }
    }

    func send(text: String, thinkingEnabled: Bool, inputMode: String = "text") async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, assistantPhase == .idle else { return }

        let userMsg = MessageModel(
            id: UUID(),
            sessionId: UUID(),
            role: "user",
            content: trimmed,
            inputMode: inputMode,
            createdAt: Date()
        )
        messages.append(userMsg)
        // If thinking is on, the model emits <think>...</think> first; the filter will fire
        // .thinking before any visible token. If thinking is off, the first event is .token,
        // so jump straight to .responding.
        assistantPhase = thinkingEnabled ? .thinking : .responding
        assistantStreamingText = ""

        do {
            let response = try await coordinator.send(
                message: trimmed,
                thinkingEnabled: thinkingEnabled,
                onEvent: { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch event {
                        case .thinking:
                            self.assistantPhase = .thinking
                        case .token(let chunk):
                            self.assistantPhase = .responding
                            self.assistantStreamingText += chunk
                        }
                    }
                }
            )
            let assistantMsg = MessageModel(
                id: UUID(),
                sessionId: UUID(),
                role: "assistant",
                content: response,
                inputMode: "text",
                createdAt: Date()
            )
            messages.append(assistantMsg)
            ttsService.speak(response)
        } catch {
            print("[SessionViewModel] send failed:", error)
            self.error = "Couldn't generate a response. \(error.localizedDescription)"
        }
        assistantPhase = .idle
        assistantStreamingText = ""
    }

    func startRecording() {
        guard !isRecording, !isBusy else { return }
        isRecording = true
        Task { [weak self] in
            do {
                try await self?.transcriber.startTranscribing { [weak self] partial in
                    Task { @MainActor [weak self] in
                        self?.voicePartial = partial
                    }
                }
            } catch {
                guard let self else { return }
                await MainActor.run {
                    self.isRecording = false
                    self.error = "Microphone unavailable. Try typing instead."
                }
            }
        }
    }

    func stopRecording(thinkingEnabled: Bool) {
        guard isRecording else { return }
        isRecording = false
        isTranscribing = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let finalText = try await self.transcriber.stopTranscribing()
                await MainActor.run {
                    self.voicePartial = ""
                    self.isTranscribing = false
                }
                await self.send(text: finalText, thinkingEnabled: thinkingEnabled, inputMode: "voice")
            } catch SpeechError.noAudioCaptured {
                await MainActor.run {
                    self.voicePartial = ""
                    self.isTranscribing = false
                    self.error = "I couldn't hear anything. Try recording again or type instead."
                }
            } catch {
                print("[SessionViewModel] stopTranscribing failed:", error)
                await MainActor.run {
                    self.voicePartial = ""
                    self.isTranscribing = false
                    self.error = "Transcription failed. \(error.localizedDescription)"
                }
            }
        }
    }

    func endSession() async {
        isClosing = true
        do {
            sessionSummary = try await coordinator.endSession()
        } catch {
            print("[SessionViewModel] endSession failed:", error)
            self.error = "Failed to save session."
        }
        isClosing = false
    }
}

struct SessionView: View {
    @StateObject private var viewModel: SessionViewModel
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.thinkingMode) private var thinkingMode: Bool = true

    init(
        coordinator: SessionCoordinator,
        transcriber: SpeechTranscriber,
        ttsService: TTSService,
        openingPrompt: String
    ) {
        _viewModel = StateObject(wrappedValue: SessionViewModel(
            coordinator: coordinator,
            transcriber: transcriber,
            ttsService: ttsService,
            openingPrompt: openingPrompt
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageThread
                inputBar
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("End Session") {
                        Task { await viewModel.endSession() }
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .fullScreenCover(item: $viewModel.sessionSummary) { summary in
                SessionCloseView(summary: summary) { dismiss() }
            }
            .task { await viewModel.start() }
        }
        .interactiveDismissDisabled(true)
    }

    private var messageThread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Voice partial transcript (live, while user is recording)
                    if !viewModel.voicePartial.isEmpty {
                        MessageBubble(message: MessageModel(
                            id: UUID(),
                            sessionId: UUID(),
                            role: "user",
                            content: viewModel.voicePartial,
                            inputMode: "voice",
                            createdAt: Date()
                        ))
                        .opacity(0.6)
                    }

                    // After stop button — finalizing transcription
                    if viewModel.isTranscribing {
                        StatusPill(text: "Transcribing...", systemImage: "waveform")
                            .id("status-transcribing")
                    }

                    // Model is reasoning before producing visible response
                    if viewModel.assistantPhase == .thinking {
                        StatusPill(text: "Thinking...", systemImage: "brain")
                            .id("status-thinking")
                    }

                    // Model is streaming visible tokens
                    if viewModel.assistantPhase == .responding {
                        StreamingAssistantBubble(text: viewModel.assistantStreamingText)
                            .id("status-responding")
                    }

                    // Closing the session (generating title + summary)
                    if viewModel.isClosing {
                        StatusPill(text: "Wrapping up...", systemImage: "sparkles")
                            .id("status-closing")
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.assistantPhase) { _, phase in
                let id: String? = {
                    switch phase {
                    case .thinking: return "status-thinking"
                    case .responding: return "status-responding"
                    case .idle: return nil
                    }
                }()
                if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
            .onChange(of: viewModel.assistantStreamingText) { _, _ in
                withAnimation { proxy.scrollTo("status-responding", anchor: .bottom) }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .disabled(viewModel.isRecording || viewModel.isBusy)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isInputFocused = false }
                    }
                }

            if hasTypedText {
                SendButton(isEnabled: !viewModel.isBusy, action: submitText)
            } else {
                MicButton(isRecording: viewModel.isRecording) {
                    if viewModel.isRecording {
                        viewModel.stopRecording(thinkingEnabled: thinkingMode)
                    } else {
                        viewModel.startRecording()
                    }
                }
                .disabled(viewModel.isBusy && !viewModel.isRecording)
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private var hasTypedText: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitText() {
        let text = inputText
        inputText = ""
        isInputFocused = false
        Task { await viewModel.send(text: text, thinkingEnabled: thinkingMode) }
    }
}

struct MessageBubble: View {
    let message: MessageModel

    var body: some View {
        HStack {
            if message.role == "user" { Spacer() }
            Text(message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.role == "user" ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if message.role == "assistant" { Spacer() }
        }
    }
}

struct StreamingAssistantBubble: View {
    let text: String

    var body: some View {
        HStack {
            HStack(alignment: .bottom, spacing: 4) {
                Text(text.isEmpty ? " " : text)
                BlinkingCursor()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer()
        }
    }
}

struct StatusPill: View {
    let text: String
    let systemImage: String
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .scaleEffect(isPulsing ? 1.1 : 1.0)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView()
                .scaleEffect(0.7)
                .padding(.leading, 4)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.secondary)
            .frame(width: 2, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

struct MicButton: View {
    let isRecording: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: isRecording ? "stop.circle.fill" : "mic.fill")
                .font(.title2)
                .foregroundStyle(isRecording ? .red : .primary)
        }
    }
}

struct SendButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title)
                .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
        }
        .disabled(!isEnabled)
    }
}
