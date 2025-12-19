//
//  IrisApp.swift
//  Iris
//
//  Created by Aadi Malhotra on 11/2/25.
//

import SwiftUI

@main
struct IrisApp: App {

    // MARK: - Properties

    /// The MLX service for model operations
    @State private var mlxService: MLXService

    /// The chat manager that coordinates conversations
    @State private var chatManager: ChatManager

    // MARK: - Init

    init() {
        let service = MLXService()
        let manager = ChatManager(mlxService: service)

        _mlxService = State(initialValue: service)
        _chatManager = State(initialValue: manager)
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView(chatManager: chatManager)
                #if os(macOS)
                .frame(minWidth: 700, minHeight: 500)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 700)
        .windowStyle(.automatic)
        #endif
    }
}
