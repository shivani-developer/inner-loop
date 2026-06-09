import XCTest
import CoreData
@testable import JournalingCompanion

final class CoreDataMemoryRepoTests: XCTestCase {

    func testSaveSessionPersistsAllFields() async throws {
        let repo = CoreDataMemoryRepo(persistence: PersistenceController(inMemory: true))
        let sessionId = UUID()
        let now = Date()
        let message = MessageModel(
            id: UUID(),
            sessionId: sessionId,
            role: "user",
            content: "I feel stressed",
            inputMode: "text",
            createdAt: now
        )
        let session = SessionModel(
            id: sessionId,
            startedAt: now,
            endedAt: now.addingTimeInterval(300),
            title: "Work stress",
            summary: "Feeling overwhelmed.",
            messages: [message]
        )

        try await repo.save(session: session)

        let request: NSFetchRequest<CDSession> = CDSession.fetchRequest()
        let results = try repo.viewContext.fetch(request)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Work stress")
        XCTAssertEqual(results[0].messages?.count, 1)
    }

    func testSaveSessionOverwritesExistingById() async throws {
        let repo = CoreDataMemoryRepo(persistence: PersistenceController(inMemory: true))
        let sessionId = UUID()
        var session = SessionModel(
            id: sessionId,
            startedAt: Date(),
            endedAt: nil,
            title: nil,
            summary: nil,
            messages: []
        )
        try await repo.save(session: session)

        session.title = "Updated title"
        try await repo.save(session: session)

        let request: NSFetchRequest<CDSession> = CDSession.fetchRequest()
        let results = try repo.viewContext.fetch(request)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Updated title")
    }

    func testLoadContextAssemblesRecentSessions() async throws {
        let repo = CoreDataMemoryRepo(persistence: PersistenceController(inMemory: true))
        let sessionId = UUID()
        let msg = MessageModel(
            id: UUID(),
            sessionId: sessionId,
            role: "user",
            content: "Hello",
            inputMode: "text",
            createdAt: Date()
        )
        let session = SessionModel(
            id: sessionId,
            startedAt: Date(),
            endedAt: Date(),
            title: "Test",
            summary: "A test session.",
            messages: [msg]
        )
        try await repo.save(session: session)

        let context = try await repo.loadContext(for: Date())
        XCTAssertFalse(context.systemPrompt.isEmpty)
        XCTAssertEqual(context.recentSessions.count, 1)
    }

    func testTriggerMemoryUpdateGeneratesSummaryAfter7Days() async throws {
        let mockLLM = MockLLMService()
        mockLLM.stubbedResponse = "Week summary paragraph."
        let repo = CoreDataMemoryRepo(
            persistence: PersistenceController(inMemory: true),
            llmService: mockLLM
        )

        let oldSession = SessionModel(
            id: UUID(),
            startedAt: Date().addingTimeInterval(-2 * 86400),
            endedAt: Date().addingTimeInterval(-2 * 86400 + 300),
            title: "Recent session",
            summary: "Something happened.",
            messages: []
        )
        try await repo.save(session: oldSession)

        await repo.triggerMemoryUpdateIfNeeded()

        XCTAssertGreaterThan(mockLLM.callCount, 0)

        let request: NSFetchRequest<CDWeeklySummary> = CDWeeklySummary.fetchRequest()
        let results = try repo.viewContext.fetch(request)
        XCTAssertGreaterThan(results.count, 0)
    }
}
