import Foundation

struct SessionSummary: Identifiable {
    let id: UUID = UUID()
    let title: String
    let summary: String
}
