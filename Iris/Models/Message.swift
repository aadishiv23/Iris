//
//  Message.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/9/25.
//

import Foundation

/// An enumeration representing the roles of a producer of a message.
enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

/// An object representing a message in a conversation.
struct Message: Codable, Identifiable {
    /// Unique identifier representing this message.
    let id: UUID
    
    /// The sender's role.
    let role: MessageRole
    
    /// The content of the given message.
    /// Currently, it is to be a String. However, in future, this could likely be converted to a custom type that can support different information.
    let content: String
    
    /// The timestamp that this message was delivered.
    let timestamp: Date
    
    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
