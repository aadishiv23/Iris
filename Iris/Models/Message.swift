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

    /// Attachments associated with the message (e.g. images).
    let attachments: [MessageAttachment]

    /// The timestamp that this message was delivered.
    let timestamp: Date

    /// Generation metrics for assistant messages.
    let metrics: GenerationMetrics?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        attachments: [MessageAttachment] = [],
        timestamp: Date = Date(),
        metrics: GenerationMetrics? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.timestamp = timestamp
        self.metrics = metrics
    }
}

/// Metrics captured during LLM generation.
struct GenerationMetrics: Codable {
    /// Time to first token in milliseconds.
    let timeToFirstTokenMs: Double?

    /// Tokens generated per second.
    let tokensPerSecond: Double?

    /// Total tokens generated.
    let totalTokens: Int?

    /// Total generation time in seconds.
    let totalTimeSeconds: Double?

    /// Formatted string for time to first token.
    var formattedTTFT: String {
        guard let ttft = timeToFirstTokenMs else { return "—" }
        return String(format: "%.0f ms", ttft)
    }

    /// Formatted string for tokens per second.
    var formattedTokensPerSecond: String {
        guard let tps = tokensPerSecond else { return "—" }
        return String(format: "%.1f tok/s", tps)
    }
}

/// Attachment payloads that can be sent with a message.
struct MessageAttachment: Codable, Identifiable {
    enum AttachmentType: String, Codable {
        case image
    }

    let id: UUID
    let type: AttachmentType
    let data: Data
    let mimeType: String

    init(
        id: UUID = UUID(),
        type: AttachmentType,
        data: Data,
        mimeType: String
    ) {
        self.id = id
        self.type = type
        self.data = data
        self.mimeType = mimeType
    }
}
