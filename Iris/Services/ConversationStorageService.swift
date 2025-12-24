//
//  ConversationStorageService.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/23/25.
//

import Foundation

/// Service responsible for persisting and loading conversations from disk.
/// Uses Application Support directory with individual JSON files per conversation.
actor ConversationStorageService {

    // MARK: - Constants

    private static let conversationsDirectoryName = "Conversations"
    private static let fileExtension = "json"

    // MARK: - Properties

    /// The directory where conversation files are stored.
    private let storageDirectory: URL

    /// JSON encoder configured for pretty printing (easier debugging).
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// JSON decoder configured for ISO8601 dates.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Initialization

    init() throws {
        // Get Application Support directory
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StorageError.directoryNotFound
        }

        // Create app-specific subdirectory, then Conversations inside it
        let appDirectory = appSupport.appendingPathComponent("Iris", isDirectory: true)
        let conversationsDir = appDirectory.appendingPathComponent(
            Self.conversationsDirectoryName,
            isDirectory: true
        )

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: conversationsDir.path) {
            try FileManager.default.createDirectory(
                at: conversationsDir,
                withIntermediateDirectories: true
            )
        }

        self.storageDirectory = conversationsDir
    }

    // MARK: - Public Methods

    /// Loads all conversations from disk, sorted by updatedAt (newest first).
    func loadAllConversations() throws -> [Conversation] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: storageDirectory.path) else {
            return []
        }

        let files = try fileManager.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == Self.fileExtension }

        var conversations: [Conversation] = []

        for fileURL in files {
            do {
                let data = try Data(contentsOf: fileURL)
                let conversation = try decoder.decode(Conversation.self, from: data)
                conversations.append(conversation)
            } catch {
                // Log error but continue loading other conversations
                print("[ConversationStorageService] Failed to load \(fileURL.lastPathComponent): \(error)")
            }
        }

        // Sort by updatedAt, newest first
        return conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Saves a single conversation to disk.
    func saveConversation(_ conversation: Conversation) throws {
        let fileURL = fileURL(for: conversation.id)
        let data = try encoder.encode(conversation)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// Deletes a conversation file from disk.
    func deleteConversation(id: UUID) throws {
        let fileURL = fileURL(for: id)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Checks if a conversation file exists.
    func conversationExists(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    // MARK: - Private Helpers

    private func fileURL(for conversationID: UUID) -> URL {
        storageDirectory.appendingPathComponent(
            "\(conversationID.uuidString).\(Self.fileExtension)"
        )
    }
}

// MARK: - Errors

extension ConversationStorageService {
    enum StorageError: Error, LocalizedError {
        case directoryNotFound
        case encodingFailed
        case decodingFailed
        case fileOperationFailed(String)

        var errorDescription: String? {
            switch self {
            case .directoryNotFound:
                return "Could not locate Application Support directory."
            case .encodingFailed:
                return "Failed to encode conversation data."
            case .decodingFailed:
                return "Failed to decode conversation data."
            case .fileOperationFailed(let reason):
                return "File operation failed: \(reason)"
            }
        }
    }
}
