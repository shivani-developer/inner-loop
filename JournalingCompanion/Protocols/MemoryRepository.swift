import Foundation

protocol MemoryRepository {
    func loadContext(for date: Date) async throws -> LLMContext
    func save(session: SessionModel) async throws
    func triggerMemoryUpdateIfNeeded() async
}
