//
//  ThinkingView.swift
//  Iris
//
//  Created by Claude on 12/22/25.
//

import SwiftUI

/// A collapsible view that shows LLM thinking/reasoning content.
struct ThinkingView: View {

    /// The thinking content to display.
    let content: String

    /// Whether the thinking is still streaming.
    let isStreaming: Bool

    /// Whether the view is expanded to show content.
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header button - always tappable
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.purple)

                    if isStreaming {
                        ShimmerText("Thinking...")
                    } else {
                        Text("Thought for a moment")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.purple.opacity(0.1))
                )
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded {
                thinkingContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var thinkingContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(content)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
        }
        .frame(maxHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.purple.opacity(0.05))
        )
        .padding(.top, 4)
    }
}

/// Animated text with shimmer/sweep effect.
struct ShimmerText: View {
    let text: String

    @State private var shimmerOffset: CGFloat = -1

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            .purple.opacity(0.6),
                            .white.opacity(0.8),
                            .purple.opacity(0.6),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: shimmerOffset * geo.size.width * 1.6)
                    .blendMode(.sourceAtop)
                }
            }
            .mask(Text(text).font(.subheadline))
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1
                }
            }
    }
}

// MARK: - Thinking Parser

/// Parses message content to separate thinking blocks from regular content.
struct ThinkingParser {

    struct Segment: Identifiable {
        let id = UUID()
        let isThinking: Bool
        let isStreaming: Bool
        let content: String
    }

    /// Parses text containing `<think>` tags into segments.
    static func parse(_ text: String) -> [Segment] {
        var result: [Segment] = []
        var currentIndex = text.startIndex

        while let openRange = text.range(of: "<think>", range: currentIndex..<text.endIndex) {
            // Add normal text before <think> if any
            let normalText = String(text[currentIndex..<openRange.lowerBound])
            if !normalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(Segment(isThinking: false, isStreaming: false, content: normalText))
            }

            let searchStart = openRange.upperBound
            if let closeRange = text.range(of: "</think>", range: searchStart..<text.endIndex) {
                // Found closing tag: complete thought block
                let thoughtContent = String(text[searchStart..<closeRange.lowerBound])
                if !thoughtContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(Segment(isThinking: true, isStreaming: false, content: thoughtContent))
                }
                currentIndex = closeRange.upperBound
            } else {
                // No closing tag found: streaming thought block
                let thoughtContent = String(text[searchStart..<text.endIndex])
                result.append(Segment(isThinking: true, isStreaming: true, content: thoughtContent))
                currentIndex = text.endIndex
            }
        }

        // Add remaining text after last tag
        if currentIndex < text.endIndex {
            let remaining = String(text[currentIndex..<text.endIndex])
            if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(Segment(isThinking: false, isStreaming: false, content: remaining))
            }
        }

        return result
    }
}

// MARK: - Previews

#Preview("Thinking - Streaming") {
    ThinkingView(
        content: "Let me analyze this problem step by step. First, I need to consider the user's question about SwiftUI animations. This involves understanding the animation system, how state changes trigger redraws, and how to create smooth transitions between states.",
        isStreaming: true
    )
    .padding()
}

#Preview("Thinking - Complete") {
    ThinkingView(
        content: "I thought about the best approach for implementing this feature. After considering several options, I decided that using a combination of GeometryReader and preference keys would be the most elegant solution. This allows us to track the scroll position without interfering with the natural scroll behavior, and we can use that information to show or hide UI elements as needed.",
        isStreaming: false
    )
    .padding()
}

#Preview("Shimmer Text") {
    ShimmerText("Thinking...")
        .padding()
}
