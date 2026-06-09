import Foundation
import CoreData

final class CoreDataMemoryRepo: MemoryRepository {
    private let persistence: PersistenceController
    private let llmService: LLMService?

    var viewContext: NSManagedObjectContext {
        persistence.container.viewContext
    }

    init(persistence: PersistenceController = .shared, llmService: LLMService? = nil) {
        self.persistence = persistence
        self.llmService = llmService
    }

    func save(session: SessionModel) async throws {
        let ctx = persistence.container.newBackgroundContext()
        try await ctx.perform {
            let request: NSFetchRequest<CDSession> = CDSession.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", session.id as CVarArg)
            let existing = try ctx.fetch(request).first ?? CDSession(context: ctx)

            existing.id = session.id
            existing.startedAt = session.startedAt
            existing.endedAt = session.endedAt
            existing.title = session.title
            existing.summary = session.summary

            if let oldMessages = existing.messages {
                for case let msg as NSManagedObject in oldMessages {
                    ctx.delete(msg)
                }
            }

            let cdMessages = session.messages.map { msg -> CDMessage in
                let cdMsg = CDMessage(context: ctx)
                cdMsg.id = msg.id
                cdMsg.sessionId = msg.sessionId
                cdMsg.role = msg.role
                cdMsg.content = msg.content
                cdMsg.inputMode = msg.inputMode
                cdMsg.createdAt = msg.createdAt
                return cdMsg
            }
            existing.messages = NSOrderedSet(array: cdMessages)

            try ctx.save()
        }
    }

    func loadContext(for date: Date) async throws -> LLMContext {
        let ctx = persistence.container.viewContext
        return try await ctx.perform {
            let userProfile = try Self.fetchUserProfileSummary(ctx: ctx)
            let lifeStory = try Self.fetchLifeStory(ctx: ctx)
            let weeklySummaries = try Self.fetchRecentWeeklySummaries(ctx: ctx, count: 4)
            let recentSessions = try Self.fetchRecentSessionTranscripts(ctx: ctx, count: 2)

            return LLMContext(
                systemPrompt: PromptTemplates.systemPrompt,
                userProfile: userProfile,
                lifeStory: lifeStory,
                weeklySummaries: weeklySummaries,
                recentSessions: recentSessions,
                currentSession: []
            )
        }
    }

    func triggerMemoryUpdateIfNeeded() async {
        guard let llmService else { return }

        let lastSummaryDate = await fetchLastWeeklySummaryDate()
        let daysSinceLast = lastSummaryDate.map {
            Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
        } ?? Int.max
        guard daysSinceLast >= 7 else { return }

        do {
            try await generateWeeklySummary(llmService: llmService)
            try await rewriteLifeStory(llmService: llmService)
        } catch {
            // Best-effort; silent failure
        }
    }

    // MARK: - Fetch helpers

    private static func fetchUserProfileSummary(ctx: NSManagedObjectContext) throws -> String? {
        let request: NSFetchRequest<CDUserProfile> = CDUserProfile.fetchRequest()
        request.fetchLimit = 1
        return try ctx.fetch(request).first?.profileSummary
    }

    private static func fetchLifeStory(ctx: NSManagedObjectContext) throws -> String? {
        let request: NSFetchRequest<CDLifeStory> = CDLifeStory.fetchRequest()
        request.fetchLimit = 1
        return try ctx.fetch(request).first?.content
    }

    private static func fetchRecentWeeklySummaries(ctx: NSManagedObjectContext, count: Int) throws -> [String] {
        let request: NSFetchRequest<CDWeeklySummary> = CDWeeklySummary.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "weekStarting", ascending: false)]
        request.fetchLimit = count
        return try ctx.fetch(request).compactMap { $0.content }
    }

    private static func fetchRecentSessionTranscripts(ctx: NSManagedObjectContext, count: Int) throws -> [SessionTranscript] {
        let request: NSFetchRequest<CDSession> = CDSession.fetchRequest()
        request.predicate = NSPredicate(format: "endedAt != nil")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        request.fetchLimit = count
        return try ctx.fetch(request).map { cdSession in
            let messages = (cdSession.messages?.array as? [CDMessage] ?? []).map {
                ChatMessage(role: $0.role ?? "user", content: $0.content ?? "")
            }
            return SessionTranscript(sessionId: cdSession.id ?? UUID(), messages: messages)
        }
    }

    private func fetchLastWeeklySummaryDate() async -> Date? {
        let ctx = persistence.container.viewContext
        return await ctx.perform {
            let request: NSFetchRequest<CDWeeklySummary> = CDWeeklySummary.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "generatedAt", ascending: false)]
            request.fetchLimit = 1
            return (try? ctx.fetch(request))?.first?.generatedAt
        }
    }

    // MARK: - Memory updates

    private func generateWeeklySummary(llmService: LLMService) async throws {
        let ctx = persistence.container.newBackgroundContext()
        let cutoff = Date().addingTimeInterval(-7 * 86400)

        let summaryText: String? = try await ctx.perform {
            let request: NSFetchRequest<CDSession> = CDSession.fetchRequest()
            request.predicate = NSPredicate(format: "startedAt >= %@ AND endedAt != nil", cutoff as NSDate)
            let sessions = try ctx.fetch(request)
            guard !sessions.isEmpty else { return nil }
            return sessions.compactMap { $0.summary }.joined(separator: "\n")
        }
        guard let summaryText, !summaryText.isEmpty else { return }

        let promptContext = LLMContext(
            systemPrompt: PromptTemplates.weeklySummaryPrompt(summaries: summaryText),
            userProfile: nil, lifeStory: nil, weeklySummaries: [], recentSessions: [], currentSession: []
        )
        let generated = try await llmService.generate(
            context: promptContext,
            thinkingEnabled: false,
            onEvent: { _ in }
        )
        guard !generated.isEmpty else { return }

        try await ctx.perform {
            let summary = CDWeeklySummary(context: ctx)
            summary.id = UUID()
            summary.weekStarting = cutoff
            summary.content = generated
            summary.generatedAt = Date()
            try ctx.save()
        }
    }

    private func rewriteLifeStory(llmService: LLMService) async throws {
        let ctx = persistence.container.newBackgroundContext()

        let summaries: [String] = try await ctx.perform {
            let request: NSFetchRequest<CDWeeklySummary> = CDWeeklySummary.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "weekStarting", ascending: false)]
            request.fetchLimit = 8
            return try ctx.fetch(request).compactMap { $0.content }
        }
        guard !summaries.isEmpty else { return }

        let promptContext = LLMContext(
            systemPrompt: PromptTemplates.lifeStoryRewritePrompt(weeklySummaries: summaries),
            userProfile: nil, lifeStory: nil, weeklySummaries: [], recentSessions: [], currentSession: []
        )
        let generated = try await llmService.generate(
            context: promptContext,
            thinkingEnabled: false,
            onEvent: { _ in }
        )
        guard !generated.isEmpty else { return }

        try await ctx.perform {
            let request: NSFetchRequest<CDLifeStory> = CDLifeStory.fetchRequest()
            let story = (try? ctx.fetch(request))?.first ?? CDLifeStory(context: ctx)
            if story.id == nil { story.id = UUID() }
            story.content = generated
            story.lastUpdated = Date()
            try ctx.save()
        }
    }
}
