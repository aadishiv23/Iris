//
//  Conversation.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/9/25.
//

import Foundation

/// An object representing a conversation thread.
struct Conversation: Codable, Identifiable {
    /// Unique identifier for conversation.
    let id: UUID
    
    /// The title of the conversation. Can be edited/mutated.
    var title: String
    
    /// List of messages comprising the conversation thread.
    var messages: [Message]
    
    /// The date representing the creation of this given conversation thread.
    let createdAt: Date
    
    /// The date representing the last update to this given conversation thread.
    var updatedAt: Date

    /// The identifier of the model used for this conversation (e.g., HuggingFace ID).
    /// Used to restore the correct model when loading a saved conversation.
    var modelIdentifier: String?

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [Message] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        modelIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelIdentifier = modelIdentifier
    }
}
