//
//  GlassInputView.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/12/25.
//

import SwiftUI
import PhotosUI
#if os(iOS)
import UIKit
#endif

// MARK: - Glass Input View

/// Input accessory that pairs a multi-line text field with send and stop actions.
struct GlassInputView: View {
    
    // MARK: Properties
    
    /// Temporary picker selection.
    @State private var selectedItems: [PhotosPickerItem] = []
    
    /// The text the user is sending to the assistant with binding to parent.
    @Binding var text: String
    
    /// Pending images to preview before sending.
    @Binding var pendingImages: [PendingImage]
    
    /// Whether the asisstant is generating a response.
    let isGenerating: Bool

    /// Optional binding to the parent's focus state.
    let focusBinding: FocusState<Bool>.Binding?
    
    @FocusState private var fallbackFocus: Bool
    
    /// Called when the user sends a message.
    let onSend: () -> Void
    
    /// Called when the user taps the stop button during generation.
    let onStop: () -> Void
    
    /// Called when the user picks new images.
    /// `items`: Newly selected `PhotosPickerItem` values
    let onPickImages: ([PhotosPickerItem]) -> Void
    
    /// Called to remove a selected image.
    /// `id`: The pending image id to remove.
    let onRemoveImage: (UUID) -> Void
    
    init(
        text: Binding<String>,
        pendingImages: Binding<[PendingImage]>,
        isGenerating: Bool,
        focusBinding: FocusState<Bool>.Binding? = nil,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onPickImages: @escaping ([PhotosPickerItem]) -> Void = { _ in },
        onRemoveImage: @escaping (UUID) -> Void = { _ in }
    ) {
        self._text = text
        self._pendingImages = pendingImages
        self.isGenerating = isGenerating
        self.focusBinding = focusBinding
        self.onSend = onSend
        self.onStop = onStop
        self.onPickImages = onPickImages
        self.onRemoveImage = onRemoveImage
    }
    
    // MARK: Body

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // Image picker button with glass effect
            imagePickerButton

            // Message bubble containing images and text field
            messageBubble

            // Send/Stop button
            SendButton(
                isGenerating: isGenerating,
                isEnabled: canSend,
                onSend: onSend,
                onStop: onStop
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: Image Picker Button

    private var imagePickerButton: some View {
        PhotosPicker(selection: $selectedItems, maxSelectionCount: 4, matching: .images) {
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.interactive())

                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            onPickImages(newItems)
            selectedItems = []
        }
    }

    // MARK: Message Bubble

    private var messageBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Pending images inside the bubble
            if !pendingImages.isEmpty {
                pendingImagesRow
                    .padding(.leading, -6)
                    .padding(.trailing, -10)
                    .padding(.top, -3)
            }

            // Text field
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused(resolvedFocusBinding)
                .onSubmit {
                    if canSend {
                        onSend()
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isFieldFocused ? Color.indigo.opacity(0.5) : Color.white.opacity(0.2),
                    lineWidth: 1
                )
        )
    }

    // MARK: Pending Images Row

    private var pendingImagesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImages) { item in
                    PendingImageThumbnail(
                        image: item.image,
                        onRemove: { onRemoveImage(item.id) }
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Helpers

    private var canSend: Bool {
        (!text.isEmpty || !pendingImages.isEmpty) && !isGenerating || isGenerating
    }

    private var resolvedFocusBinding: FocusState<Bool>.Binding {
        focusBinding ?? $fallbackFocus
    }

    private var isFieldFocused: Bool {
        focusBinding?.wrappedValue ?? fallbackFocus
    }
}

// MARK: - Send Button

/// Circular button that toggles between send and stop.
struct SendButton: View {
    
    // MARK: Properties
    
    /// Whether the assistant is currently generating.
    let isGenerating: Bool
    
    /// Whether the button is enabled (able to be interacted with) or not.
    let isEnabled: Bool
    
    /// Called when the user sends a message.
    let onSend: () -> Void
    
    /// Called when the user taps the stop button during generation.
    let onStop: () -> Void
    
    // MARK: Body

    var body: some View {
         Button(action: isGenerating ? onStop : onSend) {
             ZStack {
                 Circle()
                     .fill(.clear)
                     .glassEffect(
                         .regular
                             .tint(buttonTint)
                             .interactive(isEnabled)
                     )

                 Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                     .font(.system(size: 18, weight: .bold))
                     .foregroundStyle(isEnabled ? .white : .secondary)
             }
             .frame(width: 44, height: 44)
             .contentShape(Circle())
         }
         .buttonStyle(.plain)
         .disabled(!isEnabled)
     }

     /// Tint color based on current state
     private var buttonTint: Color {
         if isGenerating {
             return .red
         } else if isEnabled {
             return .blue
         } else {
             return .clear  // No tint when disabled
         }
     }
}

// MARK: - Pending Image Thumbnail

/// Thumbnail view for a pending image with remove button.
struct PendingImageThumbnail: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .offset(x: 0, y: 2)
            }
    }
}

// MARK: - Previews

// #Preview("Empty") {
//     GlassInputView(
//         text: .constant(""),
//         isGenerating: false,
//         onSend: {},
//         onStop: {}
//     )
// }

// #Preview("With Text") {
//     GlassInputView(
//         text: .constant("Hello, how are you?"),
//         isGenerating: false,
//         onSend: {},
//         onStop: {}
//     )
// }

// #Preview("Focused") {
//     GlassInputView(
//         text: .constant(""),
//         isGenerating: false,
//         onSend: {},
//         onStop: {}
//     )
// }

// #Preview("Generating") {
//     GlassInputView(
//         text: .constant(""),
//         isGenerating: true,
//         onSend: {},
//         onStop: {}
//     )
// }

// #Preview("Dark Mode") {
//     GlassInputView(
//         text: .constant("Test message"),
//         isGenerating: false,
//         onSend: {},
//         onStop: {}
//     )
//     .preferredColorScheme(.dark)
// }

