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
                                        .foregroundStyle(.white)
                                    
                                    Spacer()
                                    
                                    Text("\(chatManager.conversations.count) chats")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
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
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showModelManager) {
                ModelManagerView(mlxService: chatManager.mlxService)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Components

struct NewChatHero: View {
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                // "Deep Mesh" Background
                ZStack {
                    Color(hex: 0x1A1A2E) // Deep Navy Base
                    
                    LinearGradient(colors: [Color.indigo.opacity(0.7), Color.indigo.opacity(0.6), Color.indigo.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)

                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
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
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(24)
            }
            .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 8)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ConversationCard: View {
    let conversation: Conversation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(conversationTitle)
                    .font(.headline)
                    .fontDesign(.serif)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text(conversation.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            
            HStack(alignment: .top, spacing: 10) {
                // Subtle Indigo Pill
                Capsule()
                    .fill(Color.indigo)
                    .frame(width: 3, height: 16)
                    .padding(.top, 2)
                
                Text(conversationPreview)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(16)
        .background(Color(hex: 0x121212))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private var conversationTitle: String {
        conversation.messages.first(where: { $0.role == .user })?.content ?? "New Conversation"
    }

    private var conversationPreview: String {
        conversation.messages.last?.content ?? "No messages yet"
    }
}

struct BackgroundView: View {
    var body: some View {
        ZStack {
            Color(hex: 0x050505).ignoresSafeArea() // Pitch Black
            
            GridPattern()
                // INCREASED OPACITY from 0.03 to 0.1 for visibility
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .ignoresSafeArea()
                .mask {
                    // Start fade lower down so top area is crisper
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.5), // Stays solid until halfway
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
                .foregroundStyle(.white.opacity(0.1))
            
            Text("No Active Sessions")
                .font(.subheadline)
                .fontDesign(.serif)
                .foregroundStyle(.white.opacity(0.3))
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
            ZStack {
                Color(hex: 0x0A0A0A).ignoresSafeArea()
                
                List {
                    Section {
                        HStack {
                            Text("Total Storage Used")
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Text(formatSize(mlxService.cachedModels))
                                .fontWeight(.bold)
                                .foregroundStyle(.indigo)
                        }
                    }
                    .listRowBackground(Color(hex: 0x161616))
                    
                    Section("Available Models") {
                        ForEach(mlxService.cachedModels) { info in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(info.displayName)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.white)
                                    Text(info.statusText)
                                        .font(.caption)
                                        .foregroundStyle(info.isDownloaded ? .green : .gray)
                                }
                                Spacer()
                                if info.isDownloaded {
                                    Text(info.formattedSize)
                                        .font(.caption)
                                        .foregroundStyle(.gray)
                                }
                            }
                            .listRowBackground(Color(hex: 0x161616))
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
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    func formatSize(_ models: [MLXService.CachedModelInfo]) -> String {
        let total = models.reduce(0) { $0 + ($1.isDownloaded ? $1.sizeBytes : 0) }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
