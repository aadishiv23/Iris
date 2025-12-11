//
//  ChatViewModel.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/11/25.
//

import Foundation

@Observable
@MainActor
class ChatViewModel {
    // MARK: - UI State
    
    /// The text the user will send to the model.
    var inputText = ""
    
    // MARK: - Dependencies
    
    private let chatManager: ChatManager
    
    // MARK: - Initalizer
    
    init(chatManager: ChatManager) {
        self.chatManager = chatManager
    }
    
    // MARK: - Computer Properties
    
    var activeConversation: Conversation? {
        chatManager.activeConversation
    }
    
    var messages: [Message] {
        activeConversation?.messages ?? []
    }
    
    var isGeneratingResponse: Bool {
        chatManager.isGenerating
    }
    
    var hasMessages: Bool {
        !messages.isEmpty
    }
    
    // MARK: - Actions (delegate to ChatManager)

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatManager.sendMessage(text)
        inputText = ""
    }

    func stopGeneration() {
        chatManager.cancelGeneration()
    }

    func newConversation() {
        chatManager.createNewConversation()
    }
}
