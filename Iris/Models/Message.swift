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

    /// Returns a copy of this message with attachments offloaded to disk.
    func withAttachmentsOffloaded() async -> Message {
        guard !attachments.isEmpty else { return self }

        var offloadedAttachments: [MessageAttachment] = []
        for attachment in attachments {
            let offloaded = await attachment.offloadedToDisk()
            offloadedAttachments.append(offloaded)
        }

        return Message(
            id: id,
            role: role,
            content: content,
            attachments: offloadedAttachments,
            timestamp: timestamp,
            metrics: metrics
        )
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
/// Supports on-disk storage to reduce memory usage.
struct MessageAttachment: Codable, Identifiable {
    enum AttachmentType: String, Codable {
        case image
    }

    let id: UUID
    let type: AttachmentType
    let mimeType: String

    /// Raw data - may be nil if offloaded to disk.
    private var _data: Data?

    /// Whether the data has been saved to disk.
    var isOnDisk: Bool

    /// The attachment data. Loads from disk if needed.
    var data: Data {
        get {
            if let data = _data {
                return data
            }
            // Try to load from disk synchronously (for Codable compatibility)
            // In practice, use loadData() for async loading
            if isOnDisk, let diskData = loadFromDiskSync() {
                return diskData
            }
            return Data()
        }
    }

    init(
        id: UUID = UUID(),
        type: AttachmentType,
        data: Data,
        mimeType: String
    ) {
        self.id = id
        self.type = type
        self._data = data
        self.mimeType = mimeType
        self.isOnDisk = false
    }

    /// Creates an attachment reference that loads data from disk.
    init(
        id: UUID,
        type: AttachmentType,
        mimeType: String,
        isOnDisk: Bool
    ) {
        self.id = id
        self.type = type
        self._data = nil
        self.mimeType = mimeType
        self.isOnDisk = isOnDisk
    }

    /// Saves the attachment data to disk and returns a new attachment with data cleared.
    func offloadedToDisk() async -> MessageAttachment {
        guard let data = _data, !isOnDisk else { return self }

        do {
            _ = try await AttachmentStorageService.shared.save(data: data, id: id)
            return MessageAttachment(id: id, type: type, mimeType: mimeType, isOnDisk: true)
        } catch {
            // Failed to save, keep in memory
            return self
        }
    }

    /// Loads data from disk asynchronously.
    func loadData() async -> Data? {
        if let data = _data {
            return data
        }
        if isOnDisk {
            return await AttachmentStorageService.shared.load(id: id)
        }
        return nil
    }

    /// Synchronous disk load (for Codable getter).
    private func loadFromDiskSync() -> Data? {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileURL = cachesDir
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).attachment")
        return try? Data(contentsOf: fileURL)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, type, mimeType, isOnDisk
        case _data = "data"
    }
}
