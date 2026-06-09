import Foundation

struct MessageModel: Identifiable, Equatable {
    let id: UUID
    let sessionId: UUID
    let role: String
    let content: String
    let inputMode: String
    let createdAt: Date
}

struct SessionModel: Identifiable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var title: String?
    var summary: String?
    var messages: [MessageModel]
}
