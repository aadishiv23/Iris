//
//  SidebarConversationRow.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/24/25.
//

import SwiftUI

struct SidebarConversationRow: View {

    // MARK: - State

    /// The conversation being represented by this row.
    let conversation: Conversation

    /// Tracks whether this particular row is active.
    let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(conversationTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let modelIdentifier = conversation.modelIdentifier {
                    Text(formatModelName(modelIdentifier))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            isActive ? Color.indigo.opacity(0.15) : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Private methods

    private var conversationTitle: String {
        if let firstUserMessage = conversation.messages.first(where: { $0.role == .user }) {
            let content = firstUserMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.count > 28 {
                return String(content.prefix(28)) + "..."
            }
            return content.isEmpty ? "New Chat" : content
        }
        return "New Chat"
    }

    private func formatModelName(_ identifier: String) -> String {
        String(identifier.split(separator: "/").last ?? Substring(identifier))
    }
}
