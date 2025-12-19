//
//  AnimatedBackgroundView.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/14/25.
//

import SwiftUI

/// Indigo and blue glassy blobs that provide the animated chat backdrop.
struct AnimatedBackgroundView: View {

 // MARK: - State

 @State private var animateBackground = false

 // MARK: - Body

 var body: some View {
     ZStack {
         Color(.systemGroupedBackground)
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
