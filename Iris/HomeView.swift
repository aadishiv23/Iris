//
//  HomeView.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/14/25.
//

import SwiftUI

struct HomeView: View {

    // MARK: - Properties

    let chatManager: ChatManager
    @State private var showModelManager = false
    
    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 1. Background (Grid visibility fixed)
                BackgroundView()

                ScrollView {
                    VStack(spacing: 24) {
                        
                        // 2. New Chat Hero
                        NewChatHero(action: {
                            chatManager.createNewConversation()
                        })
                        .padding(.horizontal)
                        .padding(.top, 10)

                        // 3. Recent Conversations
                        if !chatManager.conversations.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text("Recent Activity")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .fontDesign(.serif)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Text("\(chatManager.conversations.count) chats")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)

                                LazyVStack(spacing: 12) {
                                    ForEach(chatManager.conversations) { conversation in
                                        ConversationCard(conversation: conversation)
                                            .onTapGesture {
                                                chatManager.selectConversation(conversation.id)
                                            }
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    chatManager.deleteConversation(conversation.id)
                                                } label: {
                                                    Label("Delete Chat", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 80)
                            }
                        } else {
                            EmptyStateView()
                                .padding(.top, 60)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Iris")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showModelManager = true
                    } label: {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .sheet(isPresented: $showModelManager) {
                ModelManagerView(mlxService: chatManager.mlxService)
                    #if os(macOS)
                    .frame(minWidth: 450, minHeight: 400)
                    #endif
            }
        }
    }
}

// MARK: - Components

struct NewChatHero: View {
    var action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                // Background with gradient
                ZStack {
                    colorScheme == .dark ? Color(hex: 0x1A1A2E) : Color.indigo.opacity(0.1)

                    LinearGradient(
                        colors: [Color.indigo.opacity(0.7), Color.indigo.opacity(0.5), Color.indigo.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.1) : Color.indigo.opacity(0.3), lineWidth: 1)
                )

                // Content
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("New Session")
                            .font(.title2)
                            .fontWeight(.bold)
                            .fontDesign(.serif)
                            .foregroundStyle(.white)

                        Text("Start a new conversation...")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer()

                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(24)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 15, x: 0, y: 8)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ConversationCard: View {
    let conversation: Conversation
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(conversationTitle)
                    .font(.headline)
                    .fontDesign(.serif)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer()

                Text(conversation.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .top, spacing: 10) {
                // Subtle Indigo Pill
                Capsule()
                    .fill(Color.indigo)
                    .frame(width: 3, height: 16)
                    .padding(.top, 2)

                Text(conversationPreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(16)
        .background(colorScheme == .dark ? Color(hex: 0x121212) : Color(hex: 0xFFFFFF))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 8, y: 2)
    }

    private var conversationTitle: String {
        conversation.messages.first(where: { $0.role == .user })?.content ?? "New Conversation"
    }

    private var conversationPreview: String {
        conversation.messages.last?.content ?? "No messages yet"
    }
}

struct BackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Adaptive background - dark in dark mode, light in light mode
            (colorScheme == .dark ? Color(hex: 0x050505) : Color(hex: 0xF5F5F7))
                .ignoresSafeArea()

            GridPattern()
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05), lineWidth: 1)
                .ignoresSafeArea()
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.quaternary)

            Text("No Active Sessions")
                .font(.subheadline)
                .fontDesign(.serif)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Utilities

struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let stepSize: CGFloat = 40
        
        for x in stride(from: 0, to: rect.width, by: stepSize) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        for y in stride(from: 0, to: rect.height, by: stepSize) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Model Manager (Unchanged)

struct ModelManagerView: View {
    @Environment(\.dismiss) private var dismiss
    let mlxService: MLXService
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Total Storage Used")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatSize(mlxService.cachedModels))
                            .fontWeight(.bold)
                            .foregroundStyle(.indigo)
                    }
                }

                Section("Available Models") {
                    ForEach(mlxService.cachedModels) { info in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(info.displayName)
                                    .fontWeight(.medium)
                                Text(info.statusText)
                                    .font(.caption)
                                    .foregroundStyle(info.isDownloaded ? .green : .secondary)
                            }
                            Spacer()
                            if info.isDownloaded {
                                Text(info.formattedSize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            if info.isDownloaded {
                                Button(role: .destructive) { try? mlxService.deleteCachedModel(info) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Models")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    func formatSize(_ models: [MLXService.CachedModelInfo]) -> String {
        let total = models.reduce(0) { $0 + ($1.isDownloaded ? $1.sizeBytes : 0) }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
