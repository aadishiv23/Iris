//
//  TypingIndicatorView.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/12/25.
//

import SwiftUI

/// Animated dot indicator shown while the assistant is generating a response.
struct TypingIndicatorView: View {

    // MARK: Body

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let speed = 6.0

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = time * speed - Double(index) * 0.6

                    Circle()
                        .frame(width: 7, height: 7)
                        .foregroundStyle(.secondary)
                        .offset(y: -3 * sin(phase))
                        .opacity(0.5 + 0.5 * sin(phase))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .glassEffect(in: Capsule())
    }
}

// MARK: - Previews

 #Preview("Typing Indicator") {
     TypingIndicatorView()
         .padding()
 }

#Preview("In Chat Context") {
    VStack(alignment: .leading, spacing: 12) {
        MessageRow(message: Message(role: .user, content: "What is Swift?"))

        HStack {
            TypingIndicatorView()
            Spacer()
        }
    }
    .padding()
}

#Preview("Dark Mode") {
    TypingIndicatorView()
        .padding()
        .preferredColorScheme(.dark)
}
