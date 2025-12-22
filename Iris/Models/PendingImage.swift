//
//  PendingImage.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/21/25.
//

import Foundation
import UIKit

/// A lightweight in-memory representation of an image selected for sending.
struct PendingImage: Identifiable {
    /// Unique identfier.
    let id: UUID
    
    /// The decoded `UIImage` for preview rendering.
    let image: UIImage
    
    /// Raw image data stored for conversion into message attachment.
    let data: Data
    
    /// The mime type for the image, eg. (`image/jpeg`)
    let mimeType: String
    
    /// Creates a new PendingImage.
    /// - Parameters:
    ///   - id: Stable identifier for UI rendering.
    ///   - image: The decoded image for previews.
    ///   - data: Raw image bytes for model input.
    ///   - mimeType: The MIME type describing the image data.
    init(id: UUID = UUID(), image: UIImage, data: Data, mimeType: String) {
        self.id = id
        self.image = image
        self.data = data
        self.mimeType = mimeType
    }
}
