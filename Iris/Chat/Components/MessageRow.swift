//
//  MessageRow.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/11/25.
//

import Foundation
import SwiftUI


/// Single chat bubble for user messages, plain text for assistant messages.
struct MessageRow: View {
    
    /// The message being displayed in this row
    let message: Message
    
    // MARK: View
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 40)
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
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
                VStack(alignment: .leading, spacing: 4) {
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.body)
                            .foregroundStyle(.primary)
                        
                        Text(message.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
