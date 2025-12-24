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

    /// All conversations.
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

    /// Indicates if conversations are still loading from disk.
    var isLoadingConversations = true

    /// User-facing alert message for chat warnings.
    var alertMessage: String?

    /// Indicates if a model switch is pending for conversation selection.
    var pendingModelSwitch: PendingModelSwitch?

    // MARK: - Dependencies

    let mlxService: MLXService
    private let storageService: ConversationStorageService?

    // MARK: - Private Properties

    /// The ID of conversation currently generating.
    private var generatingConversationID: UUID? = nil

    /// Current generation task stored for cancellation.
    private var generationTask: Task<Void, Never>?

    // MARK: - Init

    init(mlxService: MLXService) {
        self.mlxService = mlxService

        // Initialize storage service
        do {
            self.storageService = try ConversationStorageService()
        } catch {
            print("[ChatManager] Failed to initialize storage: \(error)")
            self.storageService = nil
        }

        // Load persisted conversations
        Task { @MainActor in
            await loadPersistedConversations()
        }
    }

    // MARK: - Persistence

    /// Loads all conversations from disk on app launch.
    private func loadPersistedConversations() async {
        defer { isLoadingConversations = false }

        guard let storageService else {
            // Fallback to in-memory only
            let initial = Conversation()
            conversations.append(initial)
            activeConversationID = initial.id
            return
        }

        do {
            let loaded = try await storageService.loadAllConversations()

            if loaded.isEmpty {
                // No saved conversations, create initial one
                let initial = Conversation()
                conversations.append(initial)
                activeConversationID = initial.id
            } else {
                conversations = loaded
                // Don't auto-select; let user choose from HomeView
                activeConversationID = nil
            }
        } catch {
            print("[ChatManager] Failed to load conversations: \(error)")
            // Fallback to empty state with one new conversation
            let initial = Conversation()
            conversations.append(initial)
            activeConversationID = initial.id
        }
    }

    /// Saves a specific conversation to disk.
    private func saveConversation(_ conversation: Conversation) {
        guard let storageService else { return }
        Task {
            do {
                try await storageService.saveConversation(conversation)
            } catch {
                print("[ChatManager] Failed to save conversation \(conversation.id): \(error)")
            }
        }
    }
    
    // MARK: - Navigation

    func goHome() {
        activeConversationID = nil
    }

    // MARK: - Conversation Management

    func createNewConversation() {
        // Capture current model identifier if a model is loaded
        let modelId = mlxService.modelIdentifier

        var newConversation = Conversation()
        newConversation.modelIdentifier = modelId

        conversations.insert(newConversation, at: 0)
        activeConversationID = newConversation.id

        // Save immediately
        saveConversation(newConversation)
    }

    func selectConversation(_ id: UUID) {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }

        let currentModelId = mlxService.modelIdentifier
        let conversationModelId = conversation.modelIdentifier

        // Check if model switch is needed
        if let conversationModelId,
           conversationModelId != currentModelId {
            // Model mismatch - prompt user
            pendingModelSwitch = PendingModelSwitch(
                conversationID: id,
                requiredModelIdentifier: conversationModelId
            )
        } else {
            // Same model or no model specified - select directly
            activeConversationID = id
        }
    }

    /// Called after user confirms model switch or decides to proceed without switching.
    func confirmConversationSelection(loadModel: Bool) {
        guard let pending = pendingModelSwitch else { return }

        if loadModel {
            // Load the required model
            Task { @MainActor in
                await loadModelForConversation(pending.requiredModelIdentifier)
                activeConversationID = pending.conversationID
                pendingModelSwitch = nil
            }
        } else {
            // User chose to proceed without loading model
            activeConversationID = pending.conversationID
            pendingModelSwitch = nil
        }
    }

    func cancelConversationSelection() {
        pendingModelSwitch = nil
    }

    private func loadModelForConversation(_ modelIdentifier: String) async {
        // Find matching preset by identifier
        if let preset = MLXService.ModelPreset.allCases.first(where: { preset in
            preset.configurationId == modelIdentifier
        }) {
            do {
                try await mlxService.loadModel(preset)
            } catch {
                print("[ChatManager] Failed to load model: \(error)")
                alertMessage = "Failed to load model: \(error.localizedDescription)"
            }
        } else {
            // Try loading as custom HuggingFace ID
            do {
                try await mlxService.loadModel(hfID: modelIdentifier)
            } catch {
                print("[ChatManager] Failed to load custom model: \(error)")
                alertMessage = "Failed to load model: \(error.localizedDescription)"
            }
        }
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll(where: { $0.id == id })

        if activeConversationID == id {
            activeConversationID = conversations.first?.id
        }

        // Delete from disk
        if let storageService {
            Task {
                do {
                    try await storageService.deleteConversation(id: id)
                } catch {
                    print("[ChatManager] Failed to delete conversation file: \(error)")
                }
            }
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

        // Update model identifier on conversation if not set
        if conversations[index].modelIdentifier == nil {
            conversations[index].modelIdentifier = mlxService.modelIdentifier
        }

        // Add user message with animation
        let userMessage = Message(role: .user, content: text, attachments: filteredAttachments)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            conversations[index].messages.append(userMessage)
            conversations[index].updatedAt = Date()
        }

        // Save after user message
        saveConversation(conversations[index])

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

                // Save after generation completes
                if let conversation = conversations.first(where: { $0.id == conversationId }) {
                    saveConversation(conversation)
                }
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

        // Capture metrics after generation completes
        let metrics = mlxService.lastGenerationMetrics

        // Handle empty responses
        if fullResponse.isEmpty && !Task.isCancelled {
            updateAssistantMessage(conversationId: conversationId, messageId: assistantMessageId, content: "Sorry, I couldn't generate a response.", metrics: metrics)
        } else {
            // Final update with metrics
            updateAssistantMessage(conversationId: conversationId, messageId: assistantMessageId, content: fullResponse, metrics: metrics)
        }
    }
    
    private func updateAssistantMessage(
        conversationId: UUID,
        messageId: UUID,
        content: String,
        metrics: GenerationMetrics? = nil
    ) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationId }),
              let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageId })
        else { return }

        let original = conversations[convIndex].messages[msgIndex]
        conversations[convIndex].messages[msgIndex] = Message(
            id: original.id,
            role: .assistant,
            content: content,
            timestamp: original.timestamp,
            metrics: metrics ?? original.metrics
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

// MARK: - Supporting Types

extension ChatManager {
    /// Represents a pending model switch when selecting a conversation.
    struct PendingModelSwitch {
        let conversationID: UUID
        let requiredModelIdentifier: String

        /// Returns a short display name for the model.
        var modelDisplayName: String {
            let parts = requiredModelIdentifier.split(separator: "/")
            return String(parts.last ?? Substring(requiredModelIdentifier))
        }
    }
}
