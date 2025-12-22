//
//  SandboxView.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/22/25.
//

import SwiftUI

/// Empty sandbox surface for quick UI experiments.
struct SandboxView: View {
    var body: some View {
        ZStack {
            Color.clear
        }
        .navigationTitle("Sandbox")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
