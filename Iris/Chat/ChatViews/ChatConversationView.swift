//
//  ChatConversationView.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/12/25.
//

import SwiftUI
import PhotosUI

/// Scrollable chat transcript with messages, typing indicator, and input field.
struct ChatConversationView: View {
    
    // MARK: Properties
    
    @FocusState private var isInputFocused: Bool

    /// The list of messages to be displayed.
    let messages: [Message]
    
    /// Whether the assistant is generating.
    let isGenerating: Bool
    
    /// Text input binding
    @Binding var inputText: String
    
    /// Images selected for the next message,
    @Binding var pendingImages: [PendingImage]

    /// Called when user sends a message
    let onSend: () -> Void

    /// Called when user stops generation
    let onStop: () -> Void
    
    /// Called when the user picks new images.
    /// `items`: Newly selected `PhotosPickerItem` values
    let onPickImages: ([PhotosPickerItem]) -> Void
    
    /// Called to remove a selected image.
    /// `id`: The pending image id to remove.
    let onRemoveImage: (UUID) -> Void

    // MARK: Private State

    /// Whether to show the scroll-to-bottom button
    @State private var showScrollButton = false

    /// Whether the user is near the bottom of the list
    @State private var isNearBottom = true

    /// Trigger to align the last user message to the top on send
    @State private var pendingScrollToUserMessageTop = false

    /// Follow the streaming assistant response unless user scrolls away
    @State private var followStreaming = false

    /// Delay before starting to follow streaming (allows user message to appear at top first)
    @State private var delayedFollowStreaming = false

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            messageList

            GlassInputView(
                text: $inputText,
                pendingImages: $pendingImages,
                isGenerating: isGenerating,
                focusBinding: $isInputFocused,
                onSend: {
                    onSend()
                    isInputFocused = false // dismiss keyboard
                    pendingScrollToUserMessageTop = true
                    delayedFollowStreaming = true
                    followStreaming = false // Will be enabled after initial scroll
                },
                onStop: onStop,
                onPickImages: onPickImages,
                onRemoveImage: onRemoveImage
            )
        }

    }
    
    // MARK: Message List
    
    private var messageList: some View {
        ScrollViewReader { proxy in
            GeometryReader { scrollGeo in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                                .transition(
                                    .asymmetric(
                                        insertion: .scale(scale: 0.9)
                                            .combined(with: .opacity)
                                            .combined(with: .move(edge: .bottom)),
                                        removal: .opacity
                                    )
                                )
                        }
                        
                        if isGenerating && messages.last?.role == .assistant && messages.last?.content.isEmpty == true {
                            TypingIndicatorView()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }
                        
                        // Invisible view to scroll to at bottom
                        Color.clear
                            .frame(height: 20)
                            .id("bottom")
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .preference(
                                            key: ScrollOffsetKey.self,
                                            value: geo.frame(in: .named("scroll")).minY
                                        )
                                }
                            )
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }
                .coordinateSpace(name: "scroll")
                .scrollIndicators(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .onPreferenceChange(ScrollOffsetKey.self) { bottomMinY in
                    let distanceFromBottom = max(0, bottomMinY - scrollGeo.size.height)
                    let nearBottom = distanceFromBottom <= 80
                    let shouldShow = !nearBottom
                    if nearBottom != isNearBottom {
                        isNearBottom = nearBottom
                    }
                    if shouldShow != showScrollButton {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showScrollButton = shouldShow
                        }
                    }
                    if !nearBottom && followStreaming {
                        followStreaming = false
                    }
                }
                .onChange(of: messages.count) { _, _ in
                    if pendingScrollToUserMessageTop,
                       let lastUserId = messages.last(where: { $0.role == .user })?.id {
                        // Scroll user message to top
                        scrollToMessage(id: lastUserId, proxy: proxy, anchor: .top, animated: true)
                        pendingScrollToUserMessageTop = false

                        // After a brief delay, enable following streaming
                        if delayedFollowStreaming {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                followStreaming = true
                                delayedFollowStreaming = false
                            }
                        }
                    } else if isNearBottom && !delayedFollowStreaming {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                .onChange(of: messages.last?.content) { _, newContent in
                    // Only auto-scroll when there's actual content (not on empty placeholder)
                    guard let content = newContent, !content.isEmpty else { return }

                    // No animation during streaming to prevent jitter
                    if followStreaming {
                        scrollToBottom(proxy: proxy, animated: false)
                    } else if isNearBottom && !delayedFollowStreaming {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                .onChange(of: isGenerating) { _, newValue in
                    if !newValue {
                        followStreaming = false
                        delayedFollowStreaming = false
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if showScrollButton {
                        ScrollToBottomButton {
                            scrollToBottom(proxy: proxy)
                            followStreaming = isGenerating
                        }
                        .padding(.trailing, 14)
                        .padding(.bottom, 80)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
    }
    
    
    // MARK: Helpers

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
    
    private func scrollToMessage(
        id: UUID,
        proxy: ScrollViewProxy,
        anchor: UnitPoint = .top,
        animated: Bool = true
    ) {
        if animated {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        } else {
            proxy.scrollTo(id, anchor: anchor)
        }
    }
}

// MARK: - Scroll Offset Preference Key

 /// Tracks scroll position for showing/hiding scroll button
 struct ScrollOffsetKey: PreferenceKey {
     static var defaultValue: CGFloat = 0

     static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
         value = nextValue()
     }
 }

 // MARK: - Scroll To Bottom Button

 /// Floating button that scrolls to the bottom of the chat
 struct ScrollToBottomButton: View {

     /// Called when button is tapped
     let onTap: () -> Void

     var body: some View {
         Button(action: onTap) {
             Image(systemName: "arrow.down")
                 .font(.system(size: 14, weight: .bold))
                 .foregroundStyle(.white)
                 .frame(width: 44, height: 44)
                 .background(
                     Circle()
                        .glassEffect(
                            .regular
                                .tint(.blue.opacity(0.5))
                                .interactive()
                        )
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                 )
         }
     }
 }

 // MARK: - Previews

 #Preview("Empty") {
     ChatConversationView(
         messages: [],
         isGenerating: false,
         inputText: Binding.constant(""),
         pendingImages: Binding.constant([]),
         onSend: {},
         onStop: {}
        , onPickImages: { _ in }
        , onRemoveImage: { _ in }
     )
 }

 #Preview("With Messages") {
     ChatConversationView(
         messages: [
             Message(role: .user, content: "Hello!"),
             Message(role: .assistant, content: "Hi there! How can I help you today?"),
             Message(role: .user, content: "What is SwiftUI?"),
             Message(role: .assistant, content: "SwiftUI is Apple's modern declarative framework for building user interfaces across all Apple platforms.")
         ],
         isGenerating: false,
         inputText: Binding.constant(""),
         pendingImages: Binding.constant([]),
         onSend: {},
         onStop: {}
        , onPickImages: { _ in }
        , onRemoveImage: { _ in }
     )
 }

 #Preview("Many Messages") {
     ChatConversationView(
         messages: (0..<20).map { i in
             Message(
                 role: i % 2 == 0 ? .user : .assistant,
                 content: "Message number \(i + 1). This is some sample text."
             )
         },
         isGenerating: false,
         inputText: Binding.constant(""),
         pendingImages: Binding.constant([]),
         onSend: {},
         onStop: {}
        , onPickImages: { _ in }
        , onRemoveImage: { _ in }
     )
 }

 #Preview("Generating") {
     ChatConversationView(
         messages: [
             Message(role: .user, content: "Tell me a story"),
             Message(role: .assistant, content: "")
         ],
         isGenerating: true,
         inputText: Binding.constant(""),
         pendingImages: Binding.constant([]),
         onSend: {},
         onStop: {}
        , onPickImages: { _ in }
        , onRemoveImage: { _ in }
     )
 }

 #Preview("Dark Mode") {
     ChatConversationView(
         messages: [
             Message(role: .user, content: "Hello!"),
             Message(role: .assistant, content: "Hi! How can I help?")
         ],
         isGenerating: false,
         inputText: Binding.constant("Test"),
         pendingImages: Binding.constant([]),
         onSend: {},
         onStop: {}
        , onPickImages: { _ in }
        , onRemoveImage: { _ in }
     )
     .preferredColorScheme(.dark)
 }
