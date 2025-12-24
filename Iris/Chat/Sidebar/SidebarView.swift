//
//  SidebarView.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/24/25.
//

import SwiftUI

struct SidebarView: View {

    // MARK: - Properties

    let chatManager: ChatManager

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Iris")
                    .font(.title)
                    .fontWeight(.bold)
                    .fontDesign(.serif)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Home button
            Button {
                chatManager.closeSidebar()
                chatManager.goHome()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "house.fill")
                        .font(.body.weight(.medium))
                    Text("Home")
                        .font(.body.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    chatManager.activeConversationID == nil
                        ? Color.indigo.opacity(0.15)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)

            // New Chat button
            Button {
                chatManager.closeSidebar()
                chatManager.createNewConversation()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.medium))
                    Text("New Chat")
                        .font(.body.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)

            Divider()
                .padding(.vertical, 16)
                .padding(.horizontal, 12)

            // Conversations List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(chatManager.conversations) { conversation in
                        SidebarConversationRow(
                            conversation: conversation,
                            isActive: conversation.id == chatManager.activeConversationID
                        )
                        .onTapGesture {
                            selectConversation(conversation.id)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                chatManager.deleteConversation(conversation.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 300)
        .background(
            (colorScheme == .dark ? Color(hex: 0x1A1A1A) : Color(hex: 0xF8F8FA))
                .ignoresSafeArea()
        )
    }

    // MARK: - Private Methods

    private func selectConversation(_ id: UUID) {
        chatManager.closeSidebar()

        // Small delay for smooth animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            chatManager.selectConversation(id)
        }
    }
}
