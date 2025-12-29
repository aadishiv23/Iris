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
            headerButton

            if isExpanded {
                thinkingContent
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isExpanded ? 1 : 0)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }

    private var headerButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                // Animated sparkle icon
                Image(systemName: isStreaming ? "sparkles" : "sparkle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse.wholeSymbol, options: .repeating, value: isStreaming)
                    .contentTransition(.symbolEffect(.replace))

                if isStreaming {
                    Text("Thinking")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    ThinkingPulse()
                } else {
                    Text("Thought process")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(isExpanded ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var thinkingContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 14)
        }
        .frame(maxHeight: 180)
    }
}

// MARK: - Streaming Indicator

/// Animated ellipsis for streaming state.
struct ThinkingPulse: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.4)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate * 2.5) % 4
            Text(String(repeating: ".", count: phase))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .leading)
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

#Preview("Streaming") {
    VStack(alignment: .leading) {
        ThinkingView(
            content: "Let me analyze this step by step. First, I need to consider the user's question about SwiftUI animations...",
            isStreaming: true
        )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
}

#Preview("Complete") {
    VStack(alignment: .leading) {
        ThinkingView(
            content: "I thought about the best approach for implementing this feature. After considering several options, I decided that using a combination of GeometryReader and preference keys would be the most elegant solution. This allows us to track the scroll position without interfering with the natural scroll behavior.",
            isStreaming: false
        )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
}

#Preview("Pulse Animation") {
    HStack {
        Text("Thinking")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        ThinkingPulse()
    }
    .padding()
}
