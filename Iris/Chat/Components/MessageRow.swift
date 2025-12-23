//
//  MessageRow.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/11/25.
//

import Foundation
import SwiftUI
import UIKit


/// Single chat bubble for user messages, plain text for assistant messages.
struct MessageRow: View {
    
    /// The message being displayed in this row
    let message: Message
    
    // MARK: View

    var body: some View {
        let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)

        HStack(alignment: .bottom, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 40)

                VStack(alignment: .trailing, spacing: 4) {
                    if !message.attachments.isEmpty {
                        attachmentsView(message.attachments)
                    }

                    Text(markdownContent(trimmedContent))
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(BubbleShape())
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !message.attachments.isEmpty {
                         attachmentsView(message.attachments)
                     }

                    if !trimmedContent.isEmpty {
                        // Parse content for thinking blocks
                        let segments = ThinkingParser.parse(trimmedContent)

                        ForEach(segments) { segment in
                            if segment.isThinking {
                                ThinkingView(
                                    content: segment.content,
                                    isStreaming: segment.isStreaming
                                )
                            } else {
                                Text(markdownContent(segment.content))
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            }
                        }

                        Text(message.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Markdown Helper

    private func markdownContent(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }
    
    @ViewBuilder
    private func attachmentsView(_ attachments: [MessageAttachment]) -> some View {
        let imageAttachments = attachments.filter { $0.type == .image }
        let images = imageAttachments.compactMap { UIImage(data: $0.data) }

        if images.count == 1 {
            // Single image - moderate size
            singleImageView(images[0])
        } else if images.count == 2 {
            // Two images side by side
            twoImagesView(images)
        } else if images.count == 3 {
            // Three images - 2 on top, 1 below
            threeImagesView(images)
        } else if images.count >= 4 {
            // 4+ images - 2x2 grid (show first 4)
            fourImagesGrid(Array(images.prefix(4)), extraCount: images.count - 4)
        }
    }

    private func singleImageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: 220, maxHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func twoImagesView(_ images: [UIImage]) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { index in
                Image(uiImage: images[index])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func threeImagesView(_ images: [UIImage]) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(uiImage: images[0])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Image(uiImage: images[1])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Image(uiImage: images[2])
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 224, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func fourImagesGrid(_ images: [UIImage], extraCount: Int) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(uiImage: images[0])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Image(uiImage: images[1])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 4) {
                Image(uiImage: images[2])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                ZStack {
                    Image(uiImage: images[3])
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Show +N overlay if there are more images
                    if extraCount > 0 {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.black.opacity(0.5))
                            .frame(width: 110, height: 110)

                        Text("+\(extraCount)")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

/// Capsule-like bubble shape with pinched bottom-right corner.
struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 20
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Previews

#Preview("User Message") {
    MessageRow(message: Message(
        role: .user,
        content: "Hello, how are you today?"
    ))
    .padding()
}

#Preview("Assistant Message") {
    MessageRow(message: Message(
        role: .assistant,
        content: "I'm doing great! How can I help you?"
    ))
    .padding()
}

#Preview("Conversation") {
    VStack(spacing: 12) {
        MessageRow(message: Message(role: .user, content: "What's the weather like?"))
        MessageRow(message: Message(role: .assistant, content: "I don't have access to real-time weather data, but I can help you find a weather service!"))
        MessageRow(message: Message(role: .user, content: "Thanks!"))
    }
    .padding()
}

#Preview("With Thinking") {
    VStack(spacing: 12) {
        MessageRow(message: Message(role: .user, content: "What is 2+2?"))
        MessageRow(message: Message(
            role: .assistant,
            content: "<think>Let me calculate this simple addition. 2 + 2 equals 4.</think>The answer is **4**!"
        ))
    }
    .padding()
}
