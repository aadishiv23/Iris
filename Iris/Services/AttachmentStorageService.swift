//
//  AttachmentStorageService.swift
//  Iris
//
//  Created by Claude on 12/29/25.
//

import Foundation

/// Service for storing message attachments on disk to reduce memory usage.
/// Attachments are stored in the app's caches directory and can be loaded on demand.
actor AttachmentStorageService {

    // MARK: - Singleton

    static let shared = AttachmentStorageService()

    // MARK: - Properties

    private let storageDirectory: URL
    private let fileManager = FileManager.default

    // MARK: - Initialization

    private init() {
        // Use caches directory for attachments (can be purged by system if needed)
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        storageDirectory = cachesDir.appendingPathComponent("Attachments", isDirectory: true)

        // Create directory if needed
        if !fileManager.fileExists(atPath: storageDirectory.path) {
            try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Public Methods

    /// Saves attachment data to disk and returns the file path.
    func save(data: Data, id: UUID) throws -> String {
        let fileURL = storageDirectory.appendingPathComponent("\(id.uuidString).attachment")
        try data.write(to: fileURL, options: [.atomic])
        return fileURL.path
    }

    /// Loads attachment data from disk.
    func load(id: UUID) -> Data? {
        let fileURL = storageDirectory.appendingPathComponent("\(id.uuidString).attachment")
        return try? Data(contentsOf: fileURL)
    }

    /// Checks if an attachment exists on disk.
    func exists(id: UUID) -> Bool {
        let fileURL = storageDirectory.appendingPathComponent("\(id.uuidString).attachment")
        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Deletes an attachment from disk.
    func delete(id: UUID) {
        let fileURL = storageDirectory.appendingPathComponent("\(id.uuidString).attachment")
        try? fileManager.removeItem(at: fileURL)
    }

    /// Clears all cached attachments.
    func clearAll() {
        try? fileManager.removeItem(at: storageDirectory)
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }

    /// Returns total size of cached attachments in bytes.
    func totalCacheSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: storageDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }
}
