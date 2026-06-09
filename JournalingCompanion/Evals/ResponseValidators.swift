import Foundation

/// Pure functions that score model output against the system prompt rules.
///
/// Each returns nil on success or a `Violation` describing what the model did wrong.
/// These are usable from two places:
///   1. Eval cases — a fixed set of inputs are run through the model and validators flag bad outputs.
///   2. Runtime guardrails — `DefaultSessionCoord` could call these on each response and retry on violation.
enum ResponseValidators {

    struct Violation: Codable, Equatable {
        let kind: Kind
        let detail: String

        enum Kind: String, Codable {
            case exceedsTokenBudget
            case multipleQuestions
            case containsList
            case containsAdvice
            case clinicalLanguage
            case empty
            case genericResponse
            case notAnchoredToUserInput
        }
    }

    // MARK: - Token budget

    /// Approximate token count: GPT-style tokenizers average ~4 chars per token in English.
    /// This is intentionally rough — the goal is catching runaway generation, not exact accounting.
    static func estimatedTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    static func withinTokenBudget(_ text: String, max: Int, toleranceMultiplier: Double = 2.0) -> Violation? {
        let est = estimatedTokens(text)
        let failureThreshold = Int((Double(max) * toleranceMultiplier).rounded(.up))
        guard est <= failureThreshold else {
            return Violation(
                kind: .exceedsTokenBudget,
                detail: "Estimated \(est) tokens, target \(max), failure threshold \(failureThreshold)"
            )
        }
        return nil
    }

    // MARK: - Single question / reflection

    /// The system prompt mandates one question or reflection per response.
    /// More than one `?` in a non-quoted response signals the model is asking multiple questions.
    static func atMostOneQuestion(_ text: String) -> Violation? {
        let questionMarks = text.filter { $0 == "?" }.count
        guard questionMarks <= 1 else {
            return Violation(
                kind: .multipleQuestions,
                detail: "Found \(questionMarks) question marks"
            )
        }
        return nil
    }

    // MARK: - No bullet points or lists

    static func noLists(_ text: String) -> Violation? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                return Violation(kind: .containsList, detail: "Bullet line: \(trimmed.prefix(40))")
            }
            // Numbered list: "1. ", "2. ", etc.
            if let first = trimmed.first, first.isNumber,
               trimmed.count >= 3, trimmed[trimmed.index(trimmed.startIndex, offsetBy: 1)] == "." {
                return Violation(kind: .containsList, detail: "Numbered line: \(trimmed.prefix(40))")
            }
        }
        return nil
    }

    // MARK: - No unsolicited advice

    /// Heuristic: the response is "advice" if it contains imperative phrases that prescribe action.
    /// Used for Socratic responses where advice is forbidden unless the user explicitly asked.
    static func noUnsolicitedAdvice(_ text: String, userAskedForAdvice: Bool) -> Violation? {
        guard !userAskedForAdvice else { return nil }
        let lowered = text.lowercased()
        let advicePhrases = [
            "you should",
            "you need to",
            "you ought to",
            "i recommend",
            "i suggest",
            "try to ",
            "you must ",
            "the best thing",
        ]
        for phrase in advicePhrases {
            if lowered.contains(phrase) {
                return Violation(kind: .containsAdvice, detail: "Phrase: \"\(phrase)\"")
            }
        }
        return nil
    }

    // MARK: - No clinical language

    static func noClinicalLanguage(_ text: String) -> Violation? {
        let lowered = text.lowercased()
        let clinicalTerms = [
            "diagnose",
            "diagnosis",
            "disorder",
            "depression", // discussing emotions is fine but the literal term is clinical
            "anxiety disorder",
            "ptsd",
            "ocd",
            "bipolar",
            "clinically",
            "symptom",
        ]
        for term in clinicalTerms {
            if lowered.contains(term) {
                return Violation(kind: .clinicalLanguage, detail: "Term: \"\(term)\"")
            }
        }
        return nil
    }

    // MARK: - Empty / whitespace

    static func nonEmpty(_ text: String) -> Violation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Violation(kind: .empty, detail: "Response is empty or whitespace")
        }
        return nil
    }

    // MARK: - Socratic specificity

    static func noGenericSocraticResponse(_ text: String) -> Violation? {
        let normalized = normalizedText(text)
        let genericResponses = [
            "how does that feel",
            "how does it feel",
            "how do you feel",
            "how are you feeling",
            "what feels most important to notice right now",
            "what comes up for you",
            "tell me more about that",
            "can you say more about that",
        ]

        guard genericResponses.contains(where: { normalized.contains($0) }) else {
            return nil
        }
        return Violation(
            kind: .genericResponse,
            detail: "Response uses a generic Socratic phrase without enough specificity"
        )
    }

    static func anchoredToUserInput(_ text: String, latestUserInput: String?) -> Violation? {
        guard let latestUserInput else { return nil }

        let userTerms = meaningfulTerms(in: latestUserInput)
        guard !userTerms.isEmpty else { return nil }

        let responseTerms = Set(meaningfulTerms(in: text))
        let overlap = userTerms.filter { responseTerms.contains($0) }
        guard overlap.isEmpty else { return nil }

        return Violation(
            kind: .notAnchoredToUserInput,
            detail: "Response does not reuse or paraphrase any concrete term from the latest user input"
        )
    }

    static func specificityViolations(_ text: String, latestUserInput: String?) -> [Violation] {
        [
            noGenericSocraticResponse(text),
            anchoredToUserInput(text, latestUserInput: latestUserInput),
        ].compactMap { $0 }
    }

    // MARK: - Bundled rule sets per task

    /// Rules that apply to every Socratic response during a session.
    /// Semantic Socratic checks (atMostOneQuestion, noGenericSocraticResponse, anchoredToUserInput)
    /// are intentionally excluded here — they are scored by the LLM judge, not the hard-rule layer.
    static func socraticResponseViolations(
        _ text: String,
        userAskedForAdvice: Bool = false,
        latestUserInput: String? = nil
    ) -> [Violation] {
        _ = latestUserInput // kept for API stability; semantic scoring moves to the judge
        return [
            nonEmpty(text),
            withinTokenBudget(text, max: 60),
            noLists(text),
            noUnsolicitedAdvice(text, userAskedForAdvice: userAskedForAdvice),
            noClinicalLanguage(text),
        ].compactMap { $0 }
    }

    static func openingPromptViolations(_ text: String) -> [Violation] {
        [
            nonEmpty(text),
            withinTokenBudget(text, max: 25),
            noLists(text),
            noClinicalLanguage(text),
        ].compactMap { $0 }
    }

    static func sessionTitleViolations(_ text: String) -> [Violation] {
        [
            nonEmpty(text),
            withinTokenBudget(text, max: 10),
        ].compactMap { $0 }
    }

    static func sessionSummaryViolations(_ text: String) -> [Violation] {
        [
            nonEmpty(text),
            withinTokenBudget(text, max: 120),
            noLists(text),
            noClinicalLanguage(text),
        ].compactMap { $0 }
    }

    static func profileCompressionViolations(_ text: String) -> [Violation] {
        [
            nonEmpty(text),
            withinTokenBudget(text, max: 150),
        ].compactMap { $0 }
    }

    // MARK: - Helpers

    private static func normalizedText(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func meaningfulTerms(in text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "about", "after", "again", "away", "because", "been", "being", "could",
            "does", "doing", "feel", "feeling", "from", "gave", "have", "into",
            "just", "keeps", "like", "made", "months", "more", "most", "much",
            "open", "part", "really", "right", "saying", "that", "their", "them",
            "there", "these", "thing", "this", "those", "time", "what", "when",
            "where", "which", "with", "work", "would", "your", "youre"
        ]

        let words = normalizedText(text).split(separator: " ").map(String.init)
        return Set(words.filter { word in
            word.count >= 4 && !stopWords.contains(word)
        })
    }
}
