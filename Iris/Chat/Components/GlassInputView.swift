//
//  GlassInputView.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/12/25.
//

import SwiftUI

// MARK: - Glass Input View

/// Input accessory that pairs a multi-line text field with send and stop actions.
struct GlassInputView: View {
    
    // MARK: Properties
    
    /// The text the user is sending to the assistant with binding to parent.
    @Binding var text: String
    
    /// Whether the asisstant is generating a response.
    let isGenerating: Bool

    /// Optional binding to the parent's focus state.
    let focusBinding: FocusState<Bool>.Binding?
    
    @FocusState private var fallbackFocus: Bool
    
    /// Called when the user sends a message.
    let onSend: () -> Void
    
    /// Called when the user taps the stop button during generation.
    let onStop: () -> Void
    
    init(
        text: Binding<String>,
        isGenerating: Bool,
        focusBinding: FocusState<Bool>.Binding? = nil,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self._text = text
        self.isGenerating = isGenerating
        self.focusBinding = focusBinding
        self.onSend = onSend
        self.onStop = onStop
    }
    
    // MARK: Body

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            isFieldFocused ? Color.indigo.opacity(0.5) : Color.white.opacity(0.5),
                            lineWidth: 1
                        )
                )
                .focused(resolvedFocusBinding)
                .onSubmit {
                    if !text.isEmpty && !isGenerating {
                        onSend()
                    }
                }

            SendButton(
              isGenerating: isGenerating,
              isEnabled: !text.isEmpty || isGenerating,
              onSend: onSend,
              onStop: onStop
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
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


// MARK: - Previews

#Preview("Empty") {
    GlassInputView(
        text: .constant(""),
        isGenerating: false,
        onSend: {},
        onStop: {}
    )
}

#Preview("With Text") {
    GlassInputView(
        text: .constant("Hello, how are you?"),
        isGenerating: false,
        onSend: {},
        onStop: {}
    )
}

#Preview("Focused") {
    GlassInputView(
        text: .constant(""),
        isGenerating: false,
        onSend: {},
        onStop: {}
    )
}

#Preview("Generating") {
    GlassInputView(
        text: .constant(""),
        isGenerating: true,
        onSend: {},
        onStop: {}
    )
}

#Preview("Dark Mode") {
    GlassInputView(
        text: .constant("Test message"),
        isGenerating: false,
        onSend: {},
        onStop: {}
    )
    .preferredColorScheme(.dark)
}
