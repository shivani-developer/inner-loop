import XCTest
@testable import JournalingCompanion

final class PromptTemplateTests: XCTestCase {
    func testSystemPromptIsUnderTokenBudget() {
        // ~300 tokens budget. Rough estimate: 4 chars/token.
        XCTAssertLessThan(PromptTemplates.systemPrompt.count, 1500)
    }

    func testWeeklySummaryPromptIncludesProvidedText() {
        let prompt = PromptTemplates.weeklySummaryPrompt(summaries: "Session about work stress.")
        XCTAssertTrue(prompt.contains("Session about work stress."))
    }

    func testProfileCompressionPromptIncludesRawInput() {
        let raw = "I'm 29, software engineer."
        let prompt = PromptTemplates.profileCompressionPrompt(rawInput: raw)
        XCTAssertTrue(prompt.contains(raw))
    }
}
