//
//  ChatManager.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/11/25.
//

import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
class ChatManager {
    // MARK: - Properties
    
    /// All converations.
    var conversations: [Conversation] = []
    
    /// Currently active conversation ID.
    var activeConversationID: UUID? = nil
    
    /// Computed: the active conversation.
    var activeConversation: Conversation? {
        get { conversations.first { $0.id == activeConversationID } }
        set {
            if let newValue, let index = conversations.firstIndex(where: { $0.id == newValue.id }) {
                conversations[index] = newValue
            }
        }
    }
    
    /// State tracking whether a generation is in progress.
    var isGenerating = false

    /// User-facing alert message for chat warnings.
    var alertMessage: String?
    
    // MARK: - Dependencies
    
    let mlxService: MLXService
    
    // MARK: - Private Properties
    
    /// The ID of conversation currently generating.
    private var generatingConversationID: UUID? = nil
    
    /// Current generation task stored for cancellation.
    private var generationTask: Task<Void, Never>?
    
    // MARK: - Init
    
    init(mlxService: MLXService) {
        self.mlxService = mlxService
        
        // Start with one conversation
        let initial = Conversation()
        conversations.append(initial)
        activeConversationID = initial.id
    }
    
//    init(mlxService: MLXService) {
//        self.mlxService = mlxService
//        activeConversationId = nil
//    }
    
    // MARK: - Navigation

    func goHome() {
        activeConversationID = nil
    }
    
    // MARK: - Conversation Management
    
    func createNewConversation() {
        let newConversation = Conversation()
        conversations.insert(newConversation, at: 0)
        activeConversationID = newConversation.id
    }
    
    func selectConversation(_ id: UUID) {
        activeConversationID = id
    }
    
    func deleteConversation(_ id: UUID) {
        conversations.removeAll(where: { $0.id == id })
        
        if activeConversationID == id {
            activeConversationID = conversations.first?.id
        }
        
        // Ensure at least one conversation exists
        if conversations.isEmpty {
            createNewConversation()
        }
    }
    
    // MARK: - Message Handling
    
    func sendMessage(_ text: String, attachments: [MessageAttachment]) {
        let supportsImages = mlxService.currentPreset?.supportsImages == true
        let filteredAttachments = supportsImages ? attachments : []

        if !supportsImages && !attachments.isEmpty {
            alertMessage = "Images are only supported with Gemma 3n models."
        }
        
        guard (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !filteredAttachments.isEmpty),
              let conversationId = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == conversationId }) else {
            return
        }
        
        // Cancel any existing generation
        if isGenerating {
            cancelGeneration()
        }
        
        // Add user message with animation
        let userMessage = Message(role: .user, content: text, attachments: filteredAttachments)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            conversations[index].messages.append(userMessage)
        }

        // Add placeholder assistant message with animation
        let assistantMessage = Message(role: .assistant, content: "")
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            conversations[index].messages.append(assistantMessage)
        }
        let assistantMessageId = assistantMessage.id
        
        // Start generation
        isGenerating = true
        generatingConversationID = activeConversationID
        
        generationTask = Task {
            await performGeneration(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId
            )
        }
    }
    
    private func performGeneration(
        conversationId: UUID,
        assistantMessageId: UUID
    ) async {
        defer {
            if generatingConversationID == conversationId {
                isGenerating = false
                generatingConversationID = nil
                generationTask = nil
            }
        }
        
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else {
            isGenerating = false
            return
        }
        
        // Get conversation history for context
        // we index into conversatoins as there is always a chance that user switches conversation mid generation
        let messages = conversations[index].messages.filter { $0.id != assistantMessageId }
        
        var previousLength = 0
        var fullResponse = ""
        
        for await fullText in mlxService.generateStream(messages: messages) {
            // Check for cancellation
            if Task.isCancelled { break }
            
            // Check we are still generating for this conversation
            guard generatingConversationID == conversationId else { break }
            
            // Extract only new part
            let newText = String(fullText.dropFirst(previousLength))
            previousLength = fullText.count
            fullResponse += newText
            
            // Update with assistant message
            updateAssistantMessage(conversationId: conversationId, messageId: assistantMessageId, content: fullResponse)
        }
        
        // Handle empty responses
        
        if fullResponse.isEmpty && !Task.isCancelled {
            updateAssistantMessage(conversationId: conversationId, messageId: assistantMessageId, content: "Sorry, I couldn't generate a response.")
        }
    }
    
    private func updateAssistantMessage(
        conversationId: UUID,
        messageId: UUID,
        content: String
    ) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationId }),
              let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageId })
        else { return }

        let original = conversations[convIndex].messages[msgIndex]
        conversations[convIndex].messages[msgIndex] = Message(
            id: original.id,
            role: .assistant,
            content: content,
            timestamp: original.timestamp
        )
    }
    
    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        mlxService.cancelGeneration()
        isGenerating = false
        generatingConversationID = nil
    }
}
