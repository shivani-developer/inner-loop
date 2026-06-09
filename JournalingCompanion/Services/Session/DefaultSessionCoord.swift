import Foundation

@MainActor
final class DefaultSessionCoord: SessionCoordinator {
    private let llmService: LLMService
    private let memoryRepository: MemoryRepository

    private var baseContext = LLMContext(
        systemPrompt: "",
        userProfile: nil,
        lifeStory: nil,
        weeklySummaries: [],
        recentSessions: [],
        currentSession: []
    )
    private var currentSessionId = UUID()
    private(set) var messages: [MessageModel] = []
    private var sessionStart = Date()

    init(llmService: LLMService, memoryRepository: MemoryRepository) {
        self.llmService = llmService
        self.memoryRepository = memoryRepository
    }

    func startSession(with prompt: String) async {
        currentSessionId = UUID()
        sessionStart = Date()
        messages = []
        baseContext = (try? await memoryRepository.loadContext(for: Date())) ?? baseContext

        if !prompt.isEmpty {
            let opening = MessageModel(
                id: UUID(),
                sessionId: currentSessionId,
                role: "assistant",
                content: prompt,
                inputMode: "text",
                createdAt: Date()
            )
            messages.append(opening)
        }
    }

    func send(
        message: String,
        thinkingEnabled: Bool,
        onEvent: @escaping (GenerationEvent) -> Void
    ) async throws -> String {
        let userMessage = MessageModel(
            id: UUID(),
            sessionId: currentSessionId,
            role: "user",
            content: message,
            inputMode: "text",
            createdAt: Date()
        )
        messages.append(userMessage)

        let context = contextForResponse()
        let responseText = try await llmService.generate(
            context: context,
            thinkingEnabled: thinkingEnabled,
            onEvent: onEvent
        )

        let assistantMessage = MessageModel(
            id: UUID(),
            sessionId: currentSessionId,
            role: "assistant",
            content: responseText,
            inputMode: "text",
            createdAt: Date()
        )
        messages.append(assistantMessage)
        return responseText
    }

    func endSession() async throws -> SessionSummary {
        // Title and summary run after the conversation, with no live UI awaiting tokens.
        // Keep them on the fast (non-thinking) path so users aren't waiting after they hit End.
        let titleContext = contextForTask(taskPrompt: PromptTemplates.sessionTitlePrompt())
        let title = try await llmService.generate(
            context: titleContext,
            thinkingEnabled: false,
            onEvent: { _ in }
        )

        let summaryContext = contextForTask(taskPrompt: PromptTemplates.sessionSummaryPrompt())
        let summary = try await llmService.generate(
            context: summaryContext,
            thinkingEnabled: false,
            onEvent: { _ in }
        )

        let session = SessionModel(
            id: currentSessionId,
            startedAt: sessionStart,
            endedAt: Date(),
            title: title,
            summary: summary,
            messages: messages
        )
        try await memoryRepository.save(session: session)

        Task { await memoryRepository.triggerMemoryUpdateIfNeeded() }

        return SessionSummary(title: title, summary: summary)
    }

    // MARK: - Private

    private func contextForResponse() -> LLMContext {
        LLMContext(
            systemPrompt: baseContext.systemPrompt + "\n\n" + PromptTemplates.socraticResponsePrompt(),
            userProfile: baseContext.userProfile,
            lifeStory: baseContext.lifeStory,
            weeklySummaries: baseContext.weeklySummaries,
            recentSessions: baseContext.recentSessions,
            currentSession: messages.map { ChatMessage(role: $0.role, content: $0.content) }
        )
    }

    private func contextForTask(taskPrompt: String) -> LLMContext {
        LLMContext(
            systemPrompt: taskPrompt,
            userProfile: nil,
            lifeStory: nil,
            weeklySummaries: [],
            recentSessions: [],
            currentSession: messages.map { ChatMessage(role: $0.role, content: $0.content) }
        )
    }
}
