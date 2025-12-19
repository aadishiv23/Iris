//
//  ContentView.swift
//  Iris
//
//  Created by Aadi Malhotra on 11/2/25.
//

import SwiftUI

/// Root view that routes between HomeView and ChatView based on active conversation.
struct ContentView: View {

    // MARK: - Properties

    /// The ChatManager
    let chatManager: ChatManager

    // MARK: - Body

    var body: some View {
        Group {
            if chatManager.activeConversationID != nil {
                ChatView(chatManager: chatManager)
            } else {
                HomeView(chatManager: chatManager)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chatManager.activeConversationID)
    }
}

// MARK: - Previews

//#Preview("With Active Conversation") {
//    let mlxService = MLXService()
//    let chatManager = ChatManager(mlxService: mlxService)
//    chatManager.createNewConversation()
//
//    ContentView(chatManager: chatManager)
//}

#Preview("Home") {
    let mlxService = MLXService()
    let chatManager = ChatManager(mlxService: mlxService)

    ContentView(chatManager: chatManager)
}
