//
//  ChatViewModel.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/11/25.
//

import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import _PhotosUI_SwiftUI

@Observable
@MainActor
class ChatViewModel {
    // MARK: - UI State
    
    /// The text the user will send to the model.
    var inputText = ""
    
    /// Images selected by the user but not sent yet.
    var pendingImages: [PendingImage] = []
    
    // MARK: - Dependencies
    
    private let chatManager: ChatManager
    
    // MARK: - Initalizer
    
    init(chatManager: ChatManager) {
        self.chatManager = chatManager
    }
    
    // MARK: - Computer Properties
    
    var activeConversation: Conversation? {
        chatManager.activeConversation
    }
    
    var messages: [Message] {
        activeConversation?.messages ?? []
    }
    
    var isGeneratingResponse: Bool {
        chatManager.isGenerating
    }
    
    var hasMessages: Bool {
        !messages.isEmpty
    }

    var alertMessage: String? {
        chatManager.alertMessage
    }
    
    // MARK: - Actions (delegate to ChatManager)

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingImages.isEmpty else { return }
        let attachments = pendingImages.map {
            MessageAttachment(type: .image, data: $0.data, mimeType: $0.mimeType)
        }
        chatManager.sendMessage(text, attachments: attachments)
        inputText = ""
        pendingImages = []
    }

    func stopGeneration() {
        chatManager.cancelGeneration()
    }

    func newConversation() {
        chatManager.createNewConversation()
    }

    func clearAlert() {
        chatManager.alertMessage = nil
    }
    
    // MARK: - Attachment/Image Methods
    
    /// Add newly selected image items to the pending list.
    /// - Parameters:
    ///    - items: The `PhotoPickerItem` item list chosen by the user.
    func addPickedItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { continue }
            
            let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/png"
            pendingImages.append(
                PendingImage(
                    image: image,
                    data: data,
                    mimeType: mimeType
                )
            )
        }
    }
    
    /// Removes a pending image by id.
    /// - Parameter id: The identifier of the pending image to remove.
    func removePendingImage(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.25)) {
            pendingImages.removeAll { $0.id == id }
        }
    }
}
