import Foundation

enum PromptTemplates {

    static let systemPrompt = """
    You are a private journaling companion. Your role is to help the user reflect on their thoughts and feelings.

    Rules you follow without exception:
    - Respond with one question or reflection only.
    - Maximum 2-3 sentences per response.
    - Do not give advice unless the user explicitly asks ("what should I do?").
    - No bullet points, headers, or lists.
    - No clinical or diagnostic language.
    - Validate emotions. Reflect back what you hear. Ask open questions.
    - Speak in plain, warm, conversational language.
    """

    static func openingPromptContext(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        let dateString = formatter.string(from: date)
        return """
        Today is \(dateString). Based on what you know about this person, generate one contextual opening question or reflection to start today's journaling session. The question should feel personal and specific, not generic. Maximum 25 tokens.
        """
    }

    static func socraticResponsePrompt() -> String {
        """
        Continue the journaling session. Respond with one empathetic reflection or open question. Maximum 60 tokens. No advice unless the user asked for it.
        """
    }

    static func sessionTitlePrompt() -> String {
        """
        Generate a short title for this journaling session. 2-5 words max. Just the title, nothing else.
        """
    }

    static func sessionSummaryPrompt() -> String {
        """
        Write a 3-5 sentence summary of this journaling session. Cover what was discussed, any emotional shifts, and recurring themes. Maximum 120 tokens.
        """
    }

    static func weeklySummaryPrompt(summaries: String) -> String {
        """
        The following are summaries of recent journaling sessions:

        \(summaries)

        Write one paragraph (max 100 tokens) summarizing the themes, mood patterns, and recurring topics across these sessions.
        """
    }

    static func lifeStoryRewritePrompt(weeklySummaries: [String]) -> String {
        let combined = weeklySummaries.joined(separator: "\n\n")
        return """
        The following are weekly summaries from this person's journaling history:

        \(combined)

        Rewrite their life story as one paragraph (max 150 tokens). Focus on persistent themes, major life contexts, and emotional patterns.
        """
    }

    static func profileCompressionPrompt(rawInput: String) -> String {
        """
        The user described themselves as follows:

        "\(rawInput)"

        Compress this into a concise factual paragraph (max 150 tokens). Include: age, living situation, work status, major life contexts. No interpretation, just the facts.
        """
    }

    static func closeDetectionPrompt() -> String {
        """
        Based on this conversation, has the user reached a natural resolution or expressed that they are done? If yes, offer a single gentle closing message. If no, respond only with the word CONTINUE.
        """
    }
}
