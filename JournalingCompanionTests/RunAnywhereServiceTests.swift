import XCTest
@testable import JournalingCompanion

/// SDK-agnostic tests for context splitting and max-tokens inference. Real generation
/// requires a loaded model so it's exercised manually on-device via the eval suite, not here.
final class RunAnywhereServiceTests: XCTestCase {

    var service: RunAnywhereService!

    override func setUp() {
        super.setUp()
        service = RunAnywhereService()
    }

    // MARK: - System content

    func testSystemContentIncludesUserProfile() {
        let context = LLMContext(
            systemPrompt: "system base",
            userProfile: "29F software engineer.",
            lifeStory: nil, weeklySummaries: [], recentSessions: [], currentSession: []
        )
        let (system, _) = service.splitContext(context)
        XCTAssertTrue(system.contains("29F software engineer."))
        XCTAssertTrue(system.contains("[About the user]"))
    }

    func testSystemContentIncludesLifeStoryAndWeeklySummaries() {
        let context = LLMContext(
            systemPrompt: "system base",
            userProfile: nil,
            lifeStory: "Has been job searching for two months.",
            weeklySummaries: ["Anxious about interviews this week."],
            recentSessions: [], currentSession: []
        )
        let (system, _) = service.splitContext(context)
        XCTAssertTrue(system.contains("Has been job searching"))
        XCTAssertTrue(system.contains("Anxious about interviews"))
    }

    func testSystemContentIncludesPriorSessionTranscripts() {
        let prior = SessionTranscript(
            sessionId: UUID(),
            messages: [
                ChatMessage(role: "user", content: "Was rough yesterday."),
                ChatMessage(role: "assistant", content: "What happened?"),
            ]
        )
        let context = LLMContext(
            systemPrompt: "system base",
            userProfile: nil, lifeStory: nil, weeklySummaries: [],
            recentSessions: [prior], currentSession: []
        )
        let (system, _) = service.splitContext(context)
        XCTAssertTrue(system.contains("[Previous session]"))
        XCTAssertTrue(system.contains("Was rough yesterday."))
    }

    func testSystemContentIncludesEarlierConversationTurns() {
        let context = LLMContext(
            systemPrompt: "system base",
            userProfile: nil, lifeStory: nil, weeklySummaries: [], recentSessions: [],
            currentSession: [
                ChatMessage(role: "assistant", content: "How are you?"),
                ChatMessage(role: "user", content: "Tired."),
                ChatMessage(role: "assistant", content: "Tired how?"),
                ChatMessage(role: "user", content: "Just drained."),
            ]
        )
        let (system, _) = service.splitContext(context)
        XCTAssertTrue(system.contains("[Conversation so far]"))
        XCTAssertTrue(system.contains("Assistant: How are you?"))
        XCTAssertTrue(system.contains("User: Tired."))
        XCTAssertTrue(system.contains("Assistant: Tired how?"))
        // The latest user message becomes the prompt, not part of system history
        XCTAssertFalse(system.contains("User: Just drained."))
    }

    // MARK: - User prompt

    func testUserPromptIsLatestUserMessageInSocraticTurn() {
        let context = LLMContext(
            systemPrompt: "system base",
            userProfile: nil, lifeStory: nil, weeklySummaries: [], recentSessions: [],
            currentSession: [
                ChatMessage(role: "assistant", content: "How are you?"),
                ChatMessage(role: "user", content: "I'm overwhelmed."),
            ]
        )
        let (_, user) = service.splitContext(context)
        XCTAssertEqual(user, "I'm overwhelmed.")
    }

    func testUserPromptForCloseTaskIsFullTranscript() {
        // For session title/summary tasks the session ends with an assistant turn (the user
        // tapped "End Session" right after a model reply). The transcript becomes the user
        // prompt so the model can react to it as a whole.
        let context = LLMContext(
            systemPrompt: "Generate a title.",
            userProfile: nil, lifeStory: nil, weeklySummaries: [], recentSessions: [],
            currentSession: [
                ChatMessage(role: "user", content: "Tough week."),
                ChatMessage(role: "assistant", content: "What was hardest?"),
                ChatMessage(role: "user", content: "Sleep."),
                ChatMessage(role: "assistant", content: "Sleep matters."),
            ]
        )
        let (system, user) = service.splitContext(context)
        XCTAssertTrue(user.contains("User: Tough week."))
        XCTAssertTrue(user.contains("Assistant: What was hardest?"))
        XCTAssertTrue(user.contains("Assistant: Sleep matters."))
        // Close-time tasks don't duplicate the transcript into the system prompt
        XCTAssertFalse(system.contains("[Conversation so far]"))
    }

    func testUserPromptForSingleShotTaskIsCue() {
        // Tasks like profile compression / weekly summary inline their data into the system
        // prompt and pass an empty currentSession.
        let context = LLMContext(
            systemPrompt: "Compress this paragraph into 150 tokens of facts.",
            userProfile: nil, lifeStory: nil, weeklySummaries: [], recentSessions: [],
            currentSession: []
        )
        let (_, user) = service.splitContext(context)
        XCTAssertEqual(user, "Begin.")
    }

    // MARK: - inferVisibleBudget

    func testInferMaxTokensFallsBackForPromptsWithNoDirective() {
        let titlePrompt = PromptTemplates.sessionTitlePrompt()
        XCTAssertEqual(service.inferVisibleBudget(from: titlePrompt), 80)
    }

    func testInferMaxTokensRespectsExplicitDirective() {
        let prompt = "Maximum 60 tokens. Respond briefly."
        XCTAssertEqual(service.inferVisibleBudget(from: prompt), 76)
    }

    func testInferMaxTokensCapsAt512() {
        XCTAssertEqual(service.inferVisibleBudget(from: "Maximum 9999 tokens."), 512)
    }

    func testInferMaxTokensCaseInsensitive() {
        XCTAssertEqual(service.inferVisibleBudget(from: "Reply briefly. maximum 25 tokens."), 41)
    }
}
