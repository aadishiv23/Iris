//
//  TypingIndicatorView.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/12/25.
//

import SwiftUI

struct TypingIndicatorView: View {
    
    // MARK: State
    
    @State private var phase = 0.0
    
    // MARK: Body
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 7, height: 7)
                    .foregroundStyle(.secondary)
                    .offset(y: -5 * sin(phase + Double(index) * 0.6))
                    .opacity(0.5 + 0.5 * sin(phase + Double(index) * 0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .glassEffect(in: Capsule())
        .onAppear {
             withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                 phase = .pi * 2
             }
         }
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
