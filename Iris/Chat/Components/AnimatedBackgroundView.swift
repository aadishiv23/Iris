//
//  AnimatedBackgroundView.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/14/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Cross-Platform Color Extension

extension Color {
    #if canImport(UIKit)
    init(nsOrUIColor: UIColor) {
        self.init(uiColor: nsOrUIColor)
    }
    #elseif canImport(AppKit)
    init(nsOrUIColor: NSColor) {
        self.init(nsColor: nsOrUIColor)
    }
    #endif
}

// MARK: - Cross-Platform System Colors

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
extension NSColor {
    static var systemGroupedBackground: NSColor {
        return NSColor.windowBackgroundColor
    }
}
#endif

// MARK: - Adaptive Background Color

extension Color {
    /// Background color that adapts to light/dark mode on all platforms
    static var adaptiveBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
}

/// Indigo and blue glassy blobs that provide the animated chat backdrop.
struct AnimatedBackgroundView: View {

 // MARK: - State

 @State private var animateBackground = false
 @Environment(\.colorScheme) private var colorScheme

 // MARK: - Body

 var body: some View {
     ZStack {
         Color.adaptiveBackground
             .ignoresSafeArea()

         Circle()
             .fill(Color.indigo.opacity(0.2))
             .frame(width: 300, height: 300)
             .blur(radius: 60)
             .offset(
                 x: animateBackground ? -100 : 100,
                 y: animateBackground ? -150 : 150
             )

         Circle()
             .fill(Color.blue.opacity(0.2))
             .frame(width: 250, height: 250)
             .blur(radius: 50)
             .offset(
                 x: animateBackground ? 120 : -120,
                 y: animateBackground ? 100 : -100
             )
     }
     .ignoresSafeArea()
     .onAppear {
         withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
             animateBackground.toggle()
         }
     }
 }
}

// MARK: - Previews

#Preview("Animated Background") {
 AnimatedBackgroundView()
}

#Preview("Dark Mode") {
 AnimatedBackgroundView()
     .preferredColorScheme(.dark)
}
