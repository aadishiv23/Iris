//
//  ChatView.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/13/25.
//

import SwiftUI

/// Primary chat surface that wires the view model into the conversation UI.
struct ChatView: View {
    
    // MARK: Properties
    
    /// The ChatManager
    let chatManager: ChatManager

    /// ViewModel for this chat view
    @State private var viewModel: ChatViewModel
    
    /// Show settings sheet
    @State private var showSettings = false

    /// Show model picker sheet
    @State private var showModelPicker = false
    
    /// Tracks whether the user dismissed the model loading popup.
    @State private var hideModelLoadingPopup = false
    
    // MARK: Init
    
    init(chatManager: ChatManager) {
        self.chatManager = chatManager
        _viewModel = State(initialValue: ChatViewModel(chatManager: chatManager))
        
    }
    
    // MARK: Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackgroundView()
                
                ChatConversationView(
                    messages: viewModel.messages,
                    isGenerating: viewModel.isGeneratingResponse,
                    inputText: $viewModel.inputText,
                    onSend: { viewModel.sendMessage() },
                    onStop: { viewModel.stopGeneration()}
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        chatManager.goHome()
                    } label: {
                        Image(systemName: "house")
                            .foregroundStyle(.primary)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    modelMenu
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                      withAnimation {
                          viewModel.newConversation()
                      }
                  } label: {
                      Image(systemName: "square.and.pencil")
                          .foregroundStyle(.primary)
                  }
                }
            }
            .sheet(isPresented: $showSettings) {
                ChatSettingsView()
            }
            .sheet(isPresented: $showModelPicker) {
                ChatModelPickerView(mlxService: chatManager.mlxService)
            }
        }
        .overlay(alignment: .top) {
            if shouldShowModelLoadingPopup {
                ModelLoadingPopup(
                    title: "Loading \(chatManager.mlxService.loadingModelName ?? "model")",
                    message: chatManager.mlxService.statusMessage,
                    progress: chatManager.mlxService.downloadProgress,
                    onDismiss: { hideModelLoadingPopup = true }
                )
                .padding(.horizontal, 16)
                .padding(.top, 48)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: chatManager.mlxService.isLoadingModel) { _, isLoading in
            if isLoading {
                hideModelLoadingPopup = false
            }
        }
    }
    
    // MARK: Model Menu
    
    private var modelMenu: some View {
        Menu {
            Section {
                Label(
                    chatManager.mlxService.isModelLoaded ? "Model Loaded" : "No Model",
                    systemImage: chatManager.mlxService.isModelLoaded ? "checkmark.circle.fill" : "circle"
                )
            }

            Section {
                Button {
                    showModelPicker = true
                } label: {
                    Label("Switch Model", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentModelName)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
    }
    
    // MARK: Helpers
    
    private var currentModelName: String {
        if chatManager.mlxService.isModelLoaded {
            return chatManager.mlxService.modelInformation ?? "Iris"
        }
        return "No Model"
    }

    private var shouldShowModelLoadingPopup: Bool {
        chatManager.mlxService.isLoadingModel && !hideModelLoadingPopup
    }
}

// MARK: - ChatSettingsView

struct ChatSettingsView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
      NavigationStack {
          List {
              Text("Settings coming soon...")
          }
          .navigationTitle("Settings")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
              ToolbarItem(placement: .navigationBarTrailing) {
                  Button("Done") {
                      dismiss()
                  }
              }
          }
      }
  }
}

// MARK: - Model Picker View

struct ChatModelPickerView: View {
  let mlxService: MLXService
  @Environment(\.dismiss) private var dismiss

  var body: some View {
      NavigationStack {
          List {
              if mlxService.isLoadingModel {
                  Section("Loading Model") {
                      HStack {
                          VStack(alignment: .leading, spacing: 4) {
                              Text("Loading \(mlxService.loadingModelName ?? "model")")
                                  .font(.headline)
                              Text(mlxService.statusMessage)
                                  .font(.subheadline)
                                  .foregroundStyle(.secondary)
                          }
                          Spacer()
                          progressView
                      }
                      .padding(.vertical, 4)
                  }
              }

              Section("Available Models") {
                  ForEach(MLXService.ModelPreset.allCases, id: \.self) { preset in
                      Button {
                          loadModel(preset)
                      } label: {
                          HStack {
                              Text(preset.displayName)
                                  .foregroundStyle(.primary)

                              Spacer()

                              if mlxService.loadingModelName == preset.displayName,
                                 mlxService.isLoadingModel {
                                  ProgressView()
                              }
                          }
                      }
                      .disabled(mlxService.isLoadingModel)
                  }
              }

              if mlxService.isModelLoaded {
                  Section {
                      Button(role: .destructive) {
                          mlxService.unloadModel()
                          dismiss()
                      } label: {
                          Label("Unload Model", systemImage: "xmark.circle")
                      }
                  }
              }
          }
          .navigationTitle("Switch Model")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
              ToolbarItem(placement: .navigationBarTrailing) {
                  Button("Cancel") {
                      dismiss()
                  }
              }
          }
      }
  }

  private func loadModel(_ preset: MLXService.ModelPreset) {
      Task { @MainActor in
          do {
              try await mlxService.loadModel(preset)
              dismiss()
          } catch {
              print("Failed to load model: \(error)")
          }
      }
  }

  private var progressView: some View {
      Group {
          if mlxService.downloadProgress > 0 {
              ProgressView(value: mlxService.downloadProgress)
                  .frame(width: 80)
          } else {
              ProgressView()
          }
      }
      .progressViewStyle(.circular)
  }
}

// MARK: - Model Loading Popup

struct ModelLoadingPopup: View {
    let title: String
    let message: String
    let progress: Double
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                progressView
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    private var progressView: some View {
        Group {
            if progress > 0 {
                ProgressView(value: progress)
            } else {
                ProgressView()
            }
        }
        .progressViewStyle(.linear)
    }
}

// MARK: - Model Preset Extension

extension MLXService.ModelPreset: CaseIterable {
    public static var allCases: [MLXService.ModelPreset] {
        [.llama3_2_1B, .llama3_2_3B, .phi3_5, .phi4bit, .qwen3_4b_4bit, .gemma3n_E2B_it_lm_4bit, .gemma3n_E4B_it_lm_4bit]
    }
}

// MARK: - Previews

#Preview("Chat View") {
    let mlxService = MLXService()
    let chatManager = ChatManager(mlxService: mlxService)

    let previewConversation = Conversation(
        title: "Preview Chat",
        messages: [
            Message(role: .user, content: "Hey Iris, can you summarize WWDC?"),
            Message(role: .assistant, content: "WWDC is Apple's annual developer conference where they unveil new software and tools.")
        ]
    )

    chatManager.conversations = [previewConversation]
    chatManager.activeConversationID = previewConversation.id

    return ChatView(chatManager: chatManager)
}
