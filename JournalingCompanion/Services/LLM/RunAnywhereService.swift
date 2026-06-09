import Foundation
import RunAnywhere
import LlamaCPPRuntime

enum LLMError: Error {
    case modelNotLoaded
    case generationFailed(String)
}

/// Concrete `LLMService` backed by [RunAnywhere SDK](https://github.com/RunanywhereAI/runanywhere-sdks)
/// running llama.cpp on-device.
///
/// One-time SDK setup (`RunAnywhere.initialize`, `LlamaCPP.register`, `registerModel`) lives in
/// `JournalingCompanionApp.init`. Model download and load are handled by `ModelDownloadView` on
/// first launch.
///
/// **Prompt structure:** `RunAnywhere.generateStream(prompt:, systemPrompt:)` applies Qwen3's
/// ChatML template internally. It expects `prompt` to be the latest *user-role* turn, not a
/// pre-formatted multi-turn transcript. So we split:
///   - `systemPrompt` = base instructions + memory tiers + prior session transcripts +
///                       earlier turns of the current conversation
///   - `prompt` = the latest user message (or transcript/data for close-time tasks)
final class RunAnywhereService: LLMService {

    func loadModel() async throws {
        try await RunAnywhere.loadModel(ModelConfig.modelId)
    }

    func generate(
        context: LLMContext,
        thinkingEnabled: Bool,
        onEvent: @escaping (GenerationEvent) -> Void
    ) async throws -> String {
        let (systemContent, userPrompt) = splitContext(context)
        let maxTokens = computeMaxTokens(
            systemPrompt: context.systemPrompt,
            thinkingEnabled: thinkingEnabled
        )

        // Qwen3 thinks by default. `/no_think` opts out — used when latency matters more than
        // depth (e.g. quick acknowledgements, fast helper tasks). With thinking on, the model
        // produces a `<think>...</think>` block before its visible reply, which we filter out
        // of the live token stream.
        let systemForModel = thinkingEnabled
            ? systemContent
            : systemContent + "\n\n/no_think"

        let result = try await RunAnywhere.generateStream(
            userPrompt,
            options: LLMGenerationOptions(
                maxTokens: maxTokens,
                temperature: 0.7,
                systemPrompt: systemForModel
            )
        )

        let filter = ThinkTagStreamFilter()
        for try await token in result.stream {
            filter.process(
                token,
                onThinking: { onEvent(.thinking) },
                onVisible: { visible in onEvent(.token(visible)) }
            )
        }
        filter.flush(onVisible: { visible in onEvent(.token(visible)) })

        return filter.visibleResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Context split

    /// Splits an `LLMContext` into the two strings RunAnywhere expects.
    ///
    /// - The system half carries everything that's "background": role rules, memory tiers,
    ///   prior session transcripts, and any earlier turns from the current session.
    /// - The user half is whatever the model should treat as the immediate user input.
    ///   For Socratic responses that's the latest user message. For close-time tasks
    ///   (title/summary/close detection) — where there's no "latest user message" — it's
    ///   the full transcript laid out as a record the model is asked to react to. For
    ///   single-shot tasks (weekly summary, life story rewrite, profile compression) the
    ///   data is already inlined in the system prompt by `PromptTemplates`, so we send a
    ///   short cue.
    func splitContext(_ context: LLMContext) -> (system: String, user: String) {
        let system = buildSystemContent(context)
        let user = buildUserPrompt(context)
        return (system, user)
    }

    private func buildSystemContent(_ context: LLMContext) -> String {
        var parts: [String] = [context.systemPrompt]

        var memoryParts: [String] = []
        if let profile = context.userProfile {
            memoryParts.append("[About the user] \(profile)")
        }
        if let story = context.lifeStory {
            memoryParts.append("[Life context] \(story)")
        }
        if !context.weeklySummaries.isEmpty {
            memoryParts.append("[Recent weeks] \(context.weeklySummaries.joined(separator: " | "))")
        }
        if !memoryParts.isEmpty {
            parts.append(memoryParts.joined(separator: "\n"))
        }

        for session in context.recentSessions {
            var lines = ["[Previous session]"]
            for msg in session.messages {
                lines.append("\(roleLabel(msg.role)): \(msg.content)")
            }
            parts.append(lines.joined(separator: "\n"))
        }

        // Earlier turns of the current session (everything before the latest user message).
        let history = currentSessionHistory(context.currentSession)
        if !history.isEmpty {
            var lines = ["[Conversation so far]"]
            for msg in history {
                lines.append("\(roleLabel(msg.role)): \(msg.content)")
            }
            parts.append(lines.joined(separator: "\n"))
        }

        return parts.joined(separator: "\n\n")
    }

    private func buildUserPrompt(_ context: LLMContext) -> String {
        let session = context.currentSession

        // Empty session → single-shot task. Instruction + data are already in the system
        // prompt; we just need to start generation.
        guard !session.isEmpty else { return "Begin." }

        // Session ends with a user turn → socratic case. The latest user message is the
        // immediate prompt; earlier turns are conversation history (rendered into system).
        if session.last?.role == "user", let latest = session.last {
            return latest.content
        }

        // Session ends with an assistant turn → close-time task (title/summary/etc.). The
        // model is being asked to react to the whole transcript, so we render the full
        // conversation as the user-side content.
        return session.map { "\(roleLabel($0.role)): \($0.content)" }
            .joined(separator: "\n")
    }

    /// For socratic responses, returns earlier turns (everything before the latest user
    /// message). For close-time tasks, returns nothing — the full transcript is the prompt
    /// itself, not background.
    private func currentSessionHistory(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard messages.last?.role == "user" else { return [] }
        return Array(messages.dropLast())
    }

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "user": return "User"
        case "assistant": return "Assistant"
        case "system": return "System"
        default: return role.capitalized
        }
    }

    /// Computes the maxTokens cap. Templates carry a "Maximum N tokens" hint that refers to the
    /// *visible* response budget. When thinking is enabled, we add a reasoning budget on top so
    /// the visible reply isn't truncated by a long `<think>` block.
    func computeMaxTokens(systemPrompt: String, thinkingEnabled: Bool) -> Int {
        let visibleBudget = inferVisibleBudget(from: systemPrompt)
        if thinkingEnabled {
            return min(2048, visibleBudget + 800)
        }
        return visibleBudget
    }

    /// PromptTemplates carry an explicit "Maximum N tokens" directive. We sniff that out so
    /// each task gets the right max-tokens cap.
    func inferVisibleBudget(from systemPrompt: String) -> Int {
        let pattern = #"[Mm]aximum (\d+) tokens"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(
               in: systemPrompt,
               range: NSRange(systemPrompt.startIndex..., in: systemPrompt)
           ),
           let range = Range(match.range(at: 1), in: systemPrompt),
           let value = Int(systemPrompt[range]) {
            return min(512, value + 16)
        }
        return 80
    }
}

// MARK: - Streaming think-tag filter

/// Stateful filter for streamed Qwen3 output. The model emits a `<think>...</think>` block
/// before its visible reply when thinking is enabled. Tags can split across token boundaries
/// (`"<th"`, `"ink"`, `">"`), so we buffer until we have enough to decide.
final class ThinkTagStreamFilter {
    private enum State { case lookingForOpen, insideThink, responding }
    private static let openTag = "<think>"
    private static let closeTag = "</think>"

    private var state: State = .lookingForOpen
    private var buffer: String = ""
    private var thinkingNotified = false
    private var visibleStarted = false
    private(set) var visibleResponse: String = ""

    func process(
        _ chunk: String,
        onThinking: () -> Void,
        onVisible: (String) -> Void
    ) {
        buffer += chunk
        var keepGoing = true
        while keepGoing {
            keepGoing = false
            switch state {
            case .lookingForOpen:
                if let openRange = buffer.range(of: Self.openTag) {
                    if !thinkingNotified {
                        onThinking()
                        thinkingNotified = true
                    }
                    let beforeTag = String(buffer[..<openRange.lowerBound])
                    if !beforeTag.isEmpty {
                        emitVisible(beforeTag, onVisible: onVisible)
                    }
                    buffer = String(buffer[openRange.upperBound...])
                    state = .insideThink
                    keepGoing = true
                } else if !couldBePartialOpenTag(buffer) {
                    // Buffer can't grow into "<think>" — model isn't thinking, flush as visible
                    if !buffer.isEmpty {
                        emitVisible(buffer, onVisible: onVisible)
                        buffer = ""
                    }
                    state = .responding
                    keepGoing = true
                }
                // else: still ambiguous, keep buffering

            case .insideThink:
                if let closeRange = buffer.range(of: Self.closeTag) {
                    buffer = String(buffer[closeRange.upperBound...])
                    state = .responding
                    keepGoing = true
                }
                // else: still inside the think block, drop accumulated content

            case .responding:
                if !buffer.isEmpty {
                    emitVisible(buffer, onVisible: onVisible)
                    buffer = ""
                }
            }
        }
    }

    /// Called when the stream ends — flushes any held buffer that turned out to be visible.
    func flush(onVisible: (String) -> Void) {
        switch state {
        case .lookingForOpen:
            // Held buffer never resolved into `<think>` — treat as visible (e.g. a stray "<")
            if !buffer.isEmpty {
                emitVisible(buffer, onVisible: onVisible)
                buffer = ""
            }
        case .insideThink:
            // Truncated reasoning (no closing tag) — drop it
            buffer = ""
        case .responding:
            break
        }
    }

    private func emitVisible(_ text: String, onVisible: (String) -> Void) {
        // Trim leading whitespace once when visible content first starts. Qwen3 typically emits
        // "\n\n" right after `</think>` which we don't want to render.
        var toEmit = text
        if !visibleStarted {
            toEmit = String(text.drop(while: { $0.isWhitespace || $0.isNewline }))
            if toEmit.isEmpty { return }
            visibleStarted = true
        }
        visibleResponse += toEmit
        onVisible(toEmit)
    }

    /// Whether `buffer` could still grow into `<think>` (i.e. some suffix of `buffer` is a
    /// non-empty prefix of `<think>`). Used to decide whether to keep buffering in
    /// `.lookingForOpen`.
    private func couldBePartialOpenTag(_ buffer: String) -> Bool {
        let target = Self.openTag
        let maxCheck = min(buffer.count, target.count - 1)
        for length in stride(from: maxCheck, through: 1, by: -1) {
            let suffix = String(buffer.suffix(length))
            if target.hasPrefix(suffix) {
                return true
            }
        }
        return false
    }
}
