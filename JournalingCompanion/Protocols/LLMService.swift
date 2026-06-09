import Foundation

struct ChatMessage: Equatable {
    let role: String
    let content: String
}

struct SessionTranscript {
    let sessionId: UUID
    let messages: [ChatMessage]
}

struct LLMContext {
    let systemPrompt: String
    let userProfile: String?
    let lifeStory: String?
    let weeklySummaries: [String]
    let recentSessions: [SessionTranscript]
    let currentSession: [ChatMessage]
}

/// Events emitted during streaming generation. `thinking` fires when the model has begun a
/// `<think>...</think>` block (so the UI can show a "Thinking..." indicator); `token` fires for
/// each visible response token (everything outside the think block).
enum GenerationEvent {
    case thinking
    case token(String)
}

protocol LLMService {
    func loadModel() async throws
    func generate(
        context: LLMContext,
        thinkingEnabled: Bool,
        onEvent: @escaping (GenerationEvent) -> Void
    ) async throws -> String
}
