//
//  ChatConversationView.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/12/25.
//

import SwiftUI

/// Scrollable chat transcript with messages, typing indicator, and input field.
struct ChatConversationView: View {
    
    // MARK: Properties
    
    /// The list of messages to be displayed.
    let messages: [Message]
    
    /// Whether the assistant is generating.
    let isGenerating: Bool
    
    /// Text input binding
    @Binding var inputText: String

    /// Called when user sends a message
    let onSend: () -> Void

    /// Called when user stops generation
    let onStop: () -> Void

    // MARK: Private State

    /// Whether to show the scroll-to-bottom button
    @State private var showScrollButton = false

    /// Tracks scroll position
    @State private var scrollOffset: CGFloat = 0

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            messageList

            GlassInputView(
                text: $inputText,
                isGenerating: isGenerating,
                onSend: onSend,
                onStop: onStop
            )
        }

    }
    
    // MARK: Message List
    
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(messages) { message in
                        MessageRow(message: message)
                    }
                    
                    if isGenerating && messages.last?.role == .assistant && messages.last?.content.isEmpty == true {
                        TypingIndicatorView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                    
                    // Invisilbe view to scroll to at bottom
                    Color.clear
                        .frame(height: 1)
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
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .padding(.bottom, 50)
            }
            .coordinateSpace(name: "scroll")
            .scrollIndicators(.hidden)
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                 let threshold: CGFloat = 500
                 let shouldShow = offset < threshold
                 if shouldShow != showScrollButton {
                     withAnimation(.easeInOut(duration: 0.2)) {
                         showScrollButton = shouldShow
                     }
                 }
             }
             .onChange(of: messages.count) { _, _ in
                 scrollToBottom(proxy: proxy)
             }
             .onChange(of: messages.last?.content) { _, _ in
                 scrollToBottom(proxy: proxy)
             }
             .overlay(alignment: .bottomTrailing) {
                 if showScrollButton {
                     ScrollToBottomButton {
                         scrollToBottom(proxy: proxy)
                     }
                     .padding(.trailing, 14)
                     .padding(.bottom, 80)
                     .transition(.scale.combined(with: .opacity))
                 }
             }
        }
    }
    
    
    // MARK: Helpers

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo("bottom", anchor: .bottom)
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
         inputText: .constant(""),
         onSend: {},
         onStop: {}
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
         inputText: .constant(""),
         onSend: {},
         onStop: {}
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
         inputText: .constant(""),
         onSend: {},
         onStop: {}
     )
 }

 #Preview("Generating") {
     ChatConversationView(
         messages: [
             Message(role: .user, content: "Tell me a story"),
             Message(role: .assistant, content: "")
         ],
         isGenerating: true,
         inputText: .constant(""),
         onSend: {},
         onStop: {}
     )
 }

 #Preview("Dark Mode") {
     ChatConversationView(
         messages: [
             Message(role: .user, content: "Hello!"),
             Message(role: .assistant, content: "Hi! How can I help?")
         ],
         isGenerating: false,
         inputText: .constant("Test"),
         onSend: {},
         onStop: {}
     )
     .preferredColorScheme(.dark)
 }
