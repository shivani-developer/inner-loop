import XCTest
@testable import JournalingCompanion

@MainActor
final class SessionCoordinatorTests: XCTestCase {
    var coordinator: DefaultSessionCoord!
    var mockLLM: MockLLMService!
    var mockRepo: MockMemoryRepository!

    override func setUp() async throws {
        try await super.setUp()
        mockLLM = MockLLMService()
        mockRepo = MockMemoryRepository()
        coordinator = DefaultSessionCoord(llmService: mockLLM, memoryRepository: mockRepo)
    }

    func testSendMessageReturnsLLMResponse() async throws {
        mockLLM.stubbedResponse = "What made that moment stand out?"
        await coordinator.startSession(with: "I've been feeling overwhelmed.")

        let response = try await coordinator.send(
            message: "Work has been really stressful.",
            thinkingEnabled: false,
            onEvent: { _ in }
        )
        XCTAssertEqual(response, "What made that moment stand out?")
    }

    func testEndSessionGeneratesTitleAndSummary() async throws {
        await coordinator.startSession(with: "I've been feeling overwhelmed.")

        mockLLM.stubbedResponse = "What does that feel like?"
        _ = try await coordinator.send(
            message: "Work has been hard.",
            thinkingEnabled: false,
            onEvent: { _ in }
        )

        mockLLM.stubbedResponse = "Discussed feeling overwhelmed at work."
        let summary = try await coordinator.endSession()

        XCTAssertFalse(summary.title.isEmpty)
        XCTAssertFalse(summary.summary.isEmpty)
    }

    func testEndSessionSavesToRepository() async throws {
        await coordinator.startSession(with: "Hello")
        _ = try? await coordinator.send(
            message: "Something happened.",
            thinkingEnabled: false,
            onEvent: { _ in }
        )
        _ = try? await coordinator.endSession()

        XCTAssertEqual(mockRepo.savedSessions.count, 1)
    }
}
