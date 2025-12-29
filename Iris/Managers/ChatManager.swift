//
//  ChatManager.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/11/25.
//

import Foundation
import Observation
import SwiftUI
import MLX

@Observable
@MainActor
class ChatManager {
    // MARK: - Properties

    /// Lightweight metadata for all conversations (for sidebar listing).
    var conversationMetadata: [ConversationMetadata] = []

    /// The fully-loaded active conversation (only one loaded at a time to save memory).
    private var loadedConversation: Conversation?

    /// Currently active conversation ID.
    var activeConversationID: UUID? = nil

    /// Computed: the active conversation (returns the loaded conversation if IDs match).
    var activeConversation: Conversation? {
        get {
            guard let id = activeConversationID, loadedConversation?.id == id else { return nil }
            return loadedConversation
        }
        set {
            if let newValue {
                loadedConversation = newValue
                // Update metadata to reflect changes
                if let index = conversationMetadata.firstIndex(where: { $0.id == newValue.id }) {
                    conversationMetadata[index] = ConversationMetadata(from: newValue)
                }
            }
        }
    }

    /// Legacy accessor for sidebar compatibility - returns metadata as pseudo-conversations.
    var conversations: [ConversationMetadata] {
        conversationMetadata
    }

    /// State tracking whether a generation is in progress.
    var isGenerating = false

    /// Indicates if conversations are still loading from disk.
    var isLoadingConversations = true

    /// User-facing alert message for chat warnings.
    var alertMessage: String?

    /// Indicates if a model switch is pending for conversation selection.
    var pendingModelSwitch: PendingModelSwitch?

    /// Tracks whether sidebar is open.
    var isSidebarOpen = false

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
            Logger.info("ChatManager initialized with storage service", category: "Chat")
        } catch {
            Logger.error("Failed to initialize storage: \(error)", category: "Chat")
            self.storageService = nil
        }

        // Load persisted conversations
        Task { @MainActor in
            await loadPersistedConversations()
        }
    }

    // MARK: - Persistence

    /// Loads conversation metadata from disk on app launch (lazy loading - full conversations loaded on demand).
    private func loadPersistedConversations() async {
        defer { isLoadingConversations = false }

        guard let storageService else {
            Logger.warning("No storage service, using in-memory conversations only", category: "Chat")
            let initial = Conversation()
            loadedConversation = initial
            conversationMetadata.append(ConversationMetadata(from: initial))
            activeConversationID = initial.id
            return
        }

        do {
            let metadata = try await storageService.loadAllMetadata()
            Logger.info("Loaded metadata for \(metadata.count) conversations", category: "Chat")

            if metadata.isEmpty {
                // No saved conversations, create initial one
                let initial = Conversation()
                loadedConversation = initial
                conversationMetadata.append(ConversationMetadata(from: initial))
                activeConversationID = initial.id
                saveConversation(initial)
            } else {
                conversationMetadata = metadata
                // Don't auto-select; let user choose from HomeView
                activeConversationID = nil
                loadedConversation = nil
            }
        } catch {
            Logger.error("Failed to load conversation metadata: \(error)", category: "Chat")
            // Fallback to empty state with one new conversation
            let initial = Conversation()
            loadedConversation = initial
            conversationMetadata.append(ConversationMetadata(from: initial))
            activeConversationID = initial.id
        }
    }

    /// Loads a full conversation from disk by ID.
    private func loadFullConversation(id: UUID) async -> Conversation? {
        guard let storageService else { return nil }

        do {
            let conversation = try await storageService.loadConversation(id: id)
            Logger.info("Loaded full conversation: \(id)", category: "Chat")
            return conversation
        } catch {
            Logger.error("Failed to load conversation \(id): \(error)", category: "Chat")
            return nil
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

        // Add metadata and set as loaded conversation
        conversationMetadata.insert(ConversationMetadata(from: newConversation), at: 0)
        loadedConversation = newConversation
        activeConversationID = newConversation.id
        Logger.activeConversationID = newConversation.id

        Logger.info("Created new conversation", category: "Chat", metadata: [
            "conversationID": newConversation.id.uuidString,
            "modelIdentifier": modelId ?? "none"
        ])

        // Save immediately
        saveConversation(newConversation)
    }

    func selectConversation(_ id: UUID) {
        guard let metadata = conversationMetadata.first(where: { $0.id == id }) else {
            Logger.warning("Attempted to select non-existent conversation: \(id)", category: "Chat")
            return
        }

        Logger.info("Selecting conversation", category: "Chat", metadata: [
            "conversationID": id.uuidString,
            "messageCount": String(metadata.messageCount),
            "modelIdentifier": metadata.modelIdentifier ?? "none"
        ])

        // Set active conversation for logging context
        Logger.activeConversationID = id

        let currentModelId = mlxService.modelIdentifier
        let conversationModelId = metadata.modelIdentifier

        // Check if model switch is needed
        if let conversationModelId,
           conversationModelId != currentModelId {
            Logger.info("Model mismatch detected, prompting for switch", category: "Chat", metadata: [
                "currentModel": currentModelId ?? "none",
                "conversationModel": conversationModelId
            ])
            // Model mismatch - prompt user
            pendingModelSwitch = PendingModelSwitch(
                conversationID: id,
                requiredModelIdentifier: conversationModelId
            )
        } else {
            // Same model or no model specified - load and select
            Task {
                await loadAndActivateConversation(id: id)
            }
        }
    }

    /// Loads a conversation from disk and sets it as active.
    private func loadAndActivateConversation(id: UUID) async {
        // Check if already loaded
        if loadedConversation?.id == id {
            activeConversationID = id
            return
        }

        // Load from disk
        if let conversation = await loadFullConversation(id: id) {
            loadedConversation = conversation
            activeConversationID = id
            Logger.info("Conversation loaded and activated: \(id)", category: "Chat")
        } else {
            Logger.error("Failed to load conversation: \(id)", category: "Chat")
        }
    }

    /// Called after user confirms model switch or decides to proceed without switching.
    func confirmConversationSelection(loadModel: Bool) {
        guard let pending = pendingModelSwitch else {
            Logger.warning("confirmConversationSelection called without pending switch", category: "Chat")
            return
        }

        Logger.info("Confirming conversation selection", category: "Chat", metadata: [
            "loadModel": String(loadModel),
            "conversationID": pending.conversationID.uuidString,
            "requiredModel": pending.requiredModelIdentifier
        ])

        if loadModel {
            // Load the required model, then load conversation
            Task { @MainActor in
                await loadModelForConversation(pending.requiredModelIdentifier)
                await loadAndActivateConversation(id: pending.conversationID)
                Logger.activeConversationID = pending.conversationID
                pendingModelSwitch = nil
                Logger.info("Conversation activated after model load", category: "Chat")
            }
        } else {
            // User chose to proceed without loading model
            Logger.warning("User proceeding without loading required model", category: "Chat")
            Task {
                await loadAndActivateConversation(id: pending.conversationID)
                Logger.activeConversationID = pending.conversationID
                pendingModelSwitch = nil
            }
        }
    }

    func cancelConversationSelection() {
        Logger.info("Conversation selection cancelled", category: "Chat")
        pendingModelSwitch = nil
    }

    private func loadModelForConversation(_ modelIdentifier: String) async {
        Logger.info("Loading model for conversation", category: "Chat", metadata: [
            "modelIdentifier": modelIdentifier
        ])

        // Find matching preset by identifier
        if let preset = MLXService.ModelPreset.allCases.first(where: { preset in
            preset.configurationId == modelIdentifier
        }) {
            Logger.debug("Found preset for model: \(preset.displayName)", category: "Chat")
            do {
                try await mlxService.loadModel(preset)
                Logger.info("Model loaded successfully for conversation", category: "Chat")
            } catch {
                Logger.error("Failed to load model: \(error)", category: "Chat", metadata: [
                    "modelIdentifier": modelIdentifier,
                    "error": String(describing: error)
                ])
                alertMessage = "Failed to load model: \(error.localizedDescription)"
            }
        } else {
            // Try loading as custom HuggingFace ID
            Logger.debug("No preset found, trying as HuggingFace ID", category: "Chat")
            do {
                try await mlxService.loadModel(hfID: modelIdentifier)
                Logger.info("Custom model loaded successfully", category: "Chat")
            } catch {
                Logger.error("Failed to load custom model: \(error)", category: "Chat", metadata: [
                    "modelIdentifier": modelIdentifier,
                    "error": String(describing: error)
                ])
                alertMessage = "Failed to load model: \(error.localizedDescription)"
            }
        }
    }

    func deleteConversation(_ id: UUID) {
        conversationMetadata.removeAll(where: { $0.id == id })

        // Clear loaded conversation if it's the one being deleted
        if loadedConversation?.id == id {
            loadedConversation = nil
        }

        if activeConversationID == id {
            activeConversationID = conversationMetadata.first?.id
            // Load the new active conversation if any
            if let newActiveId = activeConversationID {
                Task {
                    await loadAndActivateConversation(id: newActiveId)
                }
            }
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
        if conversationMetadata.isEmpty {
            createNewConversation()
        }
    }
    
    // MARK: - Message Handling
    
    func sendMessage(_ text: String, attachments: [MessageAttachment]) {
        let supportsImages = mlxService.currentPreset?.supportsImages == true
        let filteredAttachments = supportsImages ? attachments : []

        Logger.info("Sending message", category: "Chat", metadata: [
            "textLength": String(text.count),
            "attachmentCount": String(attachments.count),
            "supportsImages": String(supportsImages),
            "model": mlxService.currentPreset?.displayName ?? mlxService.modelIdentifier ?? "none"
        ])

        if !supportsImages && !attachments.isEmpty {
            Logger.warning("Images not supported by current model, stripping attachments", category: "Chat")
            alertMessage = "Images are only supported with Gemma 3n models."
        }

        guard (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !filteredAttachments.isEmpty),
              let conversationId = activeConversationID,
              loadedConversation?.id == conversationId else {
            Logger.warning("Cannot send: empty message or no active conversation", category: "Chat")
            return
        }

        // Set active conversation for logging context
        Logger.activeConversationID = conversationId

        // Cancel any existing generation
        if isGenerating {
            Logger.info("Cancelling existing generation before new message", category: "Chat")
            cancelGeneration()
        }

        // Update model identifier on conversation if not set
        if loadedConversation?.modelIdentifier == nil {
            loadedConversation?.modelIdentifier = mlxService.modelIdentifier
            Logger.debug("Set conversation model identifier: \(mlxService.modelIdentifier ?? "none")", category: "Chat")
        }

        // Add user message with animation
        let userMessage = Message(role: .user, content: text, attachments: filteredAttachments)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            loadedConversation?.messages.append(userMessage)
            loadedConversation?.updatedAt = Date()
        }

        Logger.debug("User message added to conversation", category: "Chat", metadata: [
            "messageID": userMessage.id.uuidString,
            "conversationMessageCount": String(loadedConversation?.messages.count ?? 0)
        ])

        // Update metadata
        if let conv = loadedConversation,
           let metaIndex = conversationMetadata.firstIndex(where: { $0.id == conversationId }) {
            conversationMetadata[metaIndex] = ConversationMetadata(from: conv)
            saveConversation(conv)
        }

        // Add placeholder assistant message with animation
        let assistantMessage = Message(role: .assistant, content: "")
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            loadedConversation?.messages.append(assistantMessage)
        }
        let assistantMessageId = assistantMessage.id

        // Start generation
        isGenerating = true
        generatingConversationID = activeConversationID

        Logger.info("Starting generation task", category: "Chat", metadata: [
            "conversationID": conversationId.uuidString,
            "assistantMessageID": assistantMessageId.uuidString
        ])

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
        Logger.debug("performGeneration started", category: "Chat", metadata: [
            "conversationID": conversationId.uuidString
        ])

        defer {
            if generatingConversationID == conversationId {
                isGenerating = false
                generatingConversationID = nil
                generationTask = nil

                // Clear GPU cache after generation to free memory
                Logger.debug("Clearing GPU cache after generation", category: "Chat")
                MLX.GPU.clearCache()

                // Offload attachments from older messages to disk to free memory
                Task { @MainActor in
                    await offloadHistoricalAttachments(conversationId: conversationId)
                }

                // Save after generation completes
                if let conversation = loadedConversation, conversation.id == conversationId {
                    saveConversation(conversation)
                    // Update metadata
                    if let metaIndex = conversationMetadata.firstIndex(where: { $0.id == conversationId }) {
                        conversationMetadata[metaIndex] = ConversationMetadata(from: conversation)
                    }
                    Logger.debug("Conversation saved after generation", category: "Chat")
                }
            }
        }

        guard loadedConversation?.id == conversationId else {
            Logger.error("Conversation not found during generation", category: "Chat", metadata: [
                "conversationID": conversationId.uuidString
            ])
            isGenerating = false
            return
        }

        // Get conversation history for context
        let messages = (loadedConversation?.messages ?? []).filter { $0.id != assistantMessageId }

        Logger.info("Beginning stream generation", category: "Chat", metadata: [
            "historyMessageCount": String(messages.count)
        ])

        var previousLength = 0
        var fullResponse = ""
        var tokenUpdates = 0

        for await fullText in mlxService.generateStream(messages: messages) {
            // Check for cancellation
            if Task.isCancelled {
                Logger.info("Generation cancelled mid-stream", category: "Chat")
                break
            }

            // Check we are still generating for this conversation
            guard generatingConversationID == conversationId else {
                Logger.info("Conversation switched during generation, stopping", category: "Chat")
                break
            }

            // Extract only new part
            let newText = String(fullText.dropFirst(previousLength))
            previousLength = fullText.count
            fullResponse += newText
            tokenUpdates += 1

            // Update with assistant message
            updateAssistantMessage(conversationId: conversationId, messageId: assistantMessageId, content: fullResponse)
        }

        Logger.info("Stream generation finished", category: "Chat", metadata: [
            "responseLength": String(fullResponse.count),
            "tokenUpdates": String(tokenUpdates)
        ])

        // Capture metrics after generation completes
        let metrics = mlxService.lastGenerationMetrics

        // Handle empty responses
        if fullResponse.isEmpty && !Task.isCancelled {
            Logger.warning("Empty response generated", category: "Chat")
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
        guard loadedConversation?.id == conversationId,
              let msgIndex = loadedConversation?.messages.firstIndex(where: { $0.id == messageId })
        else { return }

        let original = loadedConversation!.messages[msgIndex]
        loadedConversation?.messages[msgIndex] = Message(
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

    /// Offloads attachments from historical messages to disk to free memory.
    /// Keeps only the most recent message's attachments in memory.
    private func offloadHistoricalAttachments(conversationId: UUID) async {
        guard loadedConversation?.id == conversationId,
              let messages = loadedConversation?.messages,
              messages.count > 1 else { return }

        // Offload all but the last 2 messages with attachments
        var updatedMessages: [Message] = []
        let messagesToKeepInMemory = 2

        for (index, message) in messages.enumerated() {
            if !message.attachments.isEmpty && index < messages.count - messagesToKeepInMemory {
                // Offload older messages with attachments
                let offloaded = await message.withAttachmentsOffloaded()
                updatedMessages.append(offloaded)
                Logger.debug("Offloaded attachments for message \(index)", category: "Chat")
            } else {
                updatedMessages.append(message)
            }
        }

        loadedConversation?.messages = updatedMessages

        // Save the updated conversation
        if let conversation = loadedConversation {
            saveConversation(conversation)
        }
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

// MARK: - Sidebar

extension ChatManager {
    /// Toggle and present the sidebar.
    func toggleSidebar() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isSidebarOpen.toggle()
        }
    }
    
    /// Close sidebar
    func closeSidebar() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isSidebarOpen = false
        }
    }
}
