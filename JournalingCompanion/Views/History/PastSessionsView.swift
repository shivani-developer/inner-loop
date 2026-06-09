import SwiftUI
import CoreData

struct PastSessionsView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDSession.startedAt, ascending: false)],
        predicate: NSPredicate(format: "endedAt != nil"),
        animation: .default
    ) private var sessions: FetchedResults<CDSession>

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { session in
                    NavigationLink(destination: SessionDetailView(session: session)) {
                        SessionRowView(session: session)
                    }
                }
            }
            .navigationTitle("Sessions")
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView("No sessions yet", systemImage: "book.closed")
                }
            }
        }
    }
}

struct SessionRowView: View {
    let session: CDSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title ?? "Untitled")
                .font(.body)
                .fontWeight(.medium)
            if let summary = session.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(session.startedAt ?? Date(), style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
