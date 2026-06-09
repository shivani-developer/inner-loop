import SwiftUI

struct SessionDetailView: View {
    let session: CDSession

    private var messages: [CDMessage] {
        (session.messages?.array as? [CDMessage]) ?? []
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let summary = session.summary {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 8)
                }

                ForEach(messages) { message in
                    HStack {
                        if message.role == "user" { Spacer() }
                        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                            Text(message.content ?? "")
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(message.role == "user" ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            if message.role == "user", message.inputMode == "voice" {
                                Label("Voice", systemImage: "mic.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        if message.role == "assistant" { Spacer() }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(session.title ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
    }
}
