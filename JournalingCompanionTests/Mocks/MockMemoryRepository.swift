import Foundation
@testable import JournalingCompanion

final class MockMemoryRepository: MemoryRepository {
    var savedSessions: [SessionModel] = []
    var memoryUpdateTriggered: Bool = false
    var stubbedContext = LLMContext(
        systemPrompt: "test system prompt",
        userProfile: nil,
        lifeStory: nil,
        weeklySummaries: [],
        recentSessions: [],
        currentSession: []
    )

    func loadContext(for date: Date) async throws -> LLMContext {
        stubbedContext
    }

    func save(session: SessionModel) async throws {
        savedSessions.append(session)
    }

    func triggerMemoryUpdateIfNeeded() async {
        memoryUpdateTriggered = true
    }
}
