//
//  MLXService.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/9/25.
//

import Foundation
import CoreImage
import UIKit
import MLX
import MLXNN
import MLXLLM
import MLXLMCommon
import MLXVLM
import Observation
import Hub
internal import Tokenizers

/// Service responsible for managing MLX model lifecycle and text generation
/// This service handles model loading, inference, and streaming responses
@Observable
@MainActor
class MLXService {
    // MARK: - Public State
    
    /// State tracking whether a model is loaded and ready.
    var isModelLoaded = false

    /// Indicates whether a model is currently loading.
    var isLoadingModel = false
    
    /// The download progress from 0.0 to 1.0.
    var downloadProgress: Double = 0.0

    /// Human readable name for the model that is currently loading.
    var loadingModelName: String?

    /// Cached model metadata displayed in the Model Manager UI.
    var cachedModels: [CachedModelInfo] = []
    
    /// Status message
    var statusMessage: String = "No model loaded"
    
    /// Model information presented after loading
    var modelInformation: String?

    /// Short name of the currently loaded model for toolbar display
    var currentModelShortName: String?

    /// Identifier for the model that is currently active in memory.
    private var currentModelIdentifier: String?
    
    /// Currently loaded preset (only set when loading from a preset).
    private(set) var currentPreset: ModelPreset?

    // MARK: - Generation Metrics

    /// Metrics from the last generation (reset on each new generation).
    private(set) var lastGenerationMetrics: GenerationMetrics?

    // MARK: - Private Properties

    /// A container for models that guarantees single threaded access.
    private var modelContainer: ModelContainer?

    private var currentGenerationTask: Task<Void, Never>?

    /// Tracks whether we're loading from an already-downloaded cache.
    private var isLoadingFromCache = false

    /// Timing for metrics tracking.
    private var generationStartTime: Date?
    private var firstTokenTime: Date?
    private var tokenCount: Int = 0

    // MARK: - Initializer
    
    init() {
        // Set GPU Cache Limit, 6GB for now
        MLX.GPU.set(cacheLimit: 4 * 1024 * 1024 * 1024)
        refreshCachedModels()
    }

    // MARK: - Model Cache Management

    func refreshCachedModels() {
        cachedModels = MLXService.ModelPreset.allCases.map { cachedInfo(for: $0) }
    }

    func deleteCachedModel(_ info: CachedModelInfo) throws {
        guard info.isDownloaded, let directory = info.directory else { return }

        if let currentModelIdentifier, info.id == currentModelIdentifier {
            throw MLXError.modelInUse
        }

        do {
            try FileManager.default.removeItem(at: directory)
            refreshCachedModels()
        } catch {
            throw MLXError.modelDeletionFailed(error.localizedDescription)
        }
    }

    func clearCachedModels() throws {
        if currentModelIdentifier != nil {
            throw MLXError.modelInUse
        }

        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }

        let modelsDirectory = cachesDirectory.appendingPathComponent("models", isDirectory: true)
        guard FileManager.default.fileExists(atPath: modelsDirectory.path) else { return }

        do {
            try FileManager.default.removeItem(at: modelsDirectory)
            refreshCachedModels()
        } catch {
            throw MLXError.modelDeletionFailed(error.localizedDescription)
        }
    }

    private func cachedInfo(for preset: ModelPreset) -> CachedModelInfo {
        let configuration = preset.configuration
        let identifier = configurationIdentifier(configuration) ?? preset.displayName
        let directory = cacheDirectory(for: configuration)
        let stats = directory.flatMap { directoryStats(for: $0) } ?? (exists: false, size: 0, modified: nil)

        return CachedModelInfo(
            id: identifier,
            displayName: preset.displayName,
            isDownloaded: stats.exists,
            sizeBytes: stats.size,
            lastModified: stats.modified,
            directory: directory,
            preset: preset
        )
    }

    private func cacheDirectory(for configuration: ModelConfiguration) -> URL? {
        switch configuration.id {
        case .id(let id, _):
            // MLX downloads to: {cachesDir}/models/{org}/{model}/
            var url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("models", isDirectory: true)

            for component in id.split(separator: "/") {
                url.appendPathComponent(String(component), isDirectory: true)
            }

            return url

        case .directory(let directory):
            return directory
        }
    }

    private func directoryStats(for url: URL) -> (exists: Bool, size: Int64, modified: Date?) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return (false, 0, nil)
        }

        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey]
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(resourceKeys), options: [.skipsHiddenFiles])

        var totalSize: Int64 = 0
        var lastModified: Date?

        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                let values = try fileURL.resourceValues(forKeys: resourceKeys)

                guard values.isRegularFile == true else { continue }

                if let fileSize = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                    totalSize += Int64(fileSize)
                }

                if let modificationDate = values.contentModificationDate {
                    if let existingDate = lastModified {
                        lastModified = max(existingDate, modificationDate)
                    } else {
                        lastModified = modificationDate
                    }
                }
            } catch {
                continue
            }
        }

        return (true, totalSize, lastModified)
    }

    private func configurationIdentifier(_ configuration: ModelConfiguration) -> String? {
        switch configuration.id {
        case .id(let id, _):
            return id
        case .directory(let url):
            return url.path
        }
    }

    private func hasCachedFiles(for configuration: ModelConfiguration) -> Bool {
        guard let directory = cacheDirectory(for: configuration) else { return false }
        let stats = directoryStats(for: directory)
        return stats.exists && stats.size > 0
    }

    // MARK: - Model Management
    
    /// Available model presets
    enum ModelPreset: Hashable {
        case llama3_2_1B
        case llama3_2_3B
        case phi3_5
        case phi4bit
        case qwen3_4b_4bit
        case gemma3n_E2B_it_lm_4bit
        case gemma3n_E4B_it_lm_4bit
        case gemma3n_E2B_4bit
        case gemma3n_E2B_3bit
        case qwen3_VL_4B_instruct_4bit
        case qwen3_VL_4B_thinking_3bit
        case custom(String) // HuggingFace model ID

        enum ModelType {
            case llm
            case vlm
        }

        var configuration: ModelConfiguration {
            switch self {
            case .llama3_2_1B:
                return LLMRegistry.llama3_2_1B_4bit
            case .llama3_2_3B:
                return LLMRegistry.llama3_2_3B_4bit
            case .phi3_5:
                return LLMRegistry.phi3_5_4bit
            case .phi4bit:
                return LLMRegistry.phi4bit
            case .qwen3_4b_4bit:
                return LLMRegistry.qwen3_4b_4bit
            case .gemma3n_E2B_it_lm_4bit:
                return LLMRegistry.gemma3n_E2B_it_lm_4bit
            case .gemma3n_E4B_it_lm_4bit:
                return LLMRegistry.gemma3n_E4B_it_lm_4bit
            case .gemma3n_E2B_4bit:
                return ModelConfiguration(id: "mlx-community/gemma-3n-E2B-4bit")
            case .gemma3n_E2B_3bit:
                return ModelConfiguration(id: "mlx-community/gemma-3n-E2B-3bit")
            case .qwen3_VL_4B_instruct_4bit:
                return ModelConfiguration(id: "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit")
            case .qwen3_VL_4B_thinking_3bit:
                return ModelConfiguration(id: "mlx-community/Qwen3-VL-4B-Thinking-3bit")
            case .custom(let id):
                return ModelConfiguration(id: id)
            }
        }
        
//        static public let gemma3n_E2B_it_lm_4bit = ModelConfiguration(
//            id: "mlx-community/gemma-3n-E2B-it-lm-4bit",
//            defaultPrompt: "What is the difference between a fruit and a vegetable?",
//            // https://ai.google.dev/gemma/docs/core/prompt-structure
//            extraEOSTokens: ["<end_of_turn>"]
//        )
        
//        static public let qwen3_4b_4bit = ModelConfiguration(
//            id: "mlx-community/Qwen3-4B-4bit",
//            defaultPrompt: "Why is the sky blue?"
//        )

        var displayName: String {
            switch self {
            case .llama3_2_1B: return "Llama 3.2 1B"
            case .llama3_2_3B: return "Llama 3.2 3B"
            case .phi3_5: return "Phi 3.5"
            case .phi4bit: return "Phi 4bit"
            case .qwen3_4b_4bit: return "Qwen 3.4B 4bit"
            case .gemma3n_E2B_it_lm_4bit: return "Gemma 3n E2B it lm 4bit"
            case .gemma3n_E4B_it_lm_4bit: return "Gemma 3n E4B it lm 4bit"
            case .gemma3n_E2B_4bit: return "Gemma 3n E2B 4bit"
            case .gemma3n_E2B_3bit: return "Gemma 3n E2B 3bit"
            case .qwen3_VL_4B_instruct_4bit: return "Qwen3 VL 4B Instruct 4bit"
            case .qwen3_VL_4B_thinking_3bit: return "Qwen3 VL 4B Thinking 3bit"
            case .custom(let id): return id
            }
        }

        /// Short name shown in the toolbar
        var shortName: String {
            switch self {
            case .llama3_2_1B: return "Llama 3.2 1B"
            case .llama3_2_3B: return "Llama 3.2 3B"
            case .phi3_5: return "Phi 3.5"
            case .phi4bit: return "Phi 2 4 bit"
            case .qwen3_4b_4bit: return "Qwen 3 4B 4bit"
            case .gemma3n_E2B_it_lm_4bit: return "Gemma 3n E2B"
            case .gemma3n_E4B_it_lm_4bit: return "Gemma 3n E4B"
            case .gemma3n_E2B_4bit: return "Gemma 3n E2B 4bit"
            case .gemma3n_E2B_3bit: return "Gemma 3n E2B 3bit"
            case .qwen3_VL_4B_instruct_4bit: return "Qwen3 VL 4B"
            case .qwen3_VL_4B_thinking_3bit: return "Qwen3 VL 4B Think"
            case .custom(let id):
                let parts = id.split(separator: "/")
                return String(parts.last ?? Substring(id))
            }
        }
        
        /// Tracks whether the given model support an image
        var supportsImages: Bool {
            switch self {
            case .gemma3n_E2B_4bit, .gemma3n_E2B_3bit, .qwen3_VL_4B_instruct_4bit,
                 .qwen3_VL_4B_thinking_3bit:
                return true
            default:
                return false
            }
        }

        var modelType: ModelType {
            switch self {
            case .qwen3_VL_4B_instruct_4bit, .qwen3_VL_4B_thinking_3bit:
                return .vlm
            default:
                return .llm
            }
        }
    }

    struct CachedModelInfo: Identifiable, Hashable {
        let id: String
        let displayName: String
        let isDownloaded: Bool
        let sizeBytes: Int64
        let lastModified: Date?
        let directory: URL?
        let preset: ModelPreset?

        var formattedSize: String {
            guard isDownloaded else { return "—" }
            return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }

        var statusText: String {
            isDownloaded ? "Installed" : "Not Installed"
        }
    }
    
    /// Loads a model from preset
    func loadModel(_ preset: ModelPreset) async throws {
        loadingModelName = preset.displayName
        try await loadModel(
            configuration: preset.configuration,
            shortName: preset.shortName,
            modelType: preset.modelType
        )
        currentPreset = preset
    }

    /// Loads a model from given HuggingFace ID.
    func loadModel(hfID: String) async throws {
        let config = ModelConfiguration(id: hfID)
        loadingModelName = hfID
        // Extract short name from HF ID (last component)
        let parts = hfID.split(separator: "/")
        let shortName = String(parts.last ?? Substring(hfID))
        try await loadModel(configuration: config, shortName: shortName, modelType: .llm)
    }
    
    /// Loads a model with the given configuration.
    func loadModel(
        configuration: ModelConfiguration,
        shortName: String? = nil,
        modelType: ModelPreset.ModelType = .llm
    ) async throws {
        unloadModel()

        isLoadingModel = true
        let cached = hasCachedFiles(for: configuration)
        isLoadingFromCache = cached
        statusMessage = cached ? "Preparing cached model..." : "Downloading model..."
        downloadProgress = cached ? 1.0 : 0.0

        defer {
            isLoadingModel = false
            loadingModelName = nil
            isLoadingFromCache = false
        }

        do {
            let factory: ModelFactory = modelType == .vlm ? VLMModelFactory.shared : LLMModelFactory.shared
            modelContainer = try await factory.loadContainer(
                configuration: configuration
            ) { [weak self] progress in

                let progressFraction = progress.fractionCompleted
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.isLoadingFromCache {
                        self.downloadProgress = 1.0
                        self.statusMessage = "Preparing cached model..."
                    } else {
                        self.downloadProgress = progressFraction
                        self.statusMessage = "Downloading model... (\(Int(progressFraction * 100))%)"
                    }
                }
            }

            // Get model information
            if let container = modelContainer {
                let numParams = await container.perform { context in
                    context.model.numParameters()
                }

                let millions = numParams / (1024 * 1024)
                if millions >= 1000 {
                    modelInformation = String(format: "%.1fB parameters", Double(millions) / 1000.0)
                } else {
                    modelInformation = "\(millions)M parameters"
                }
            }

            isModelLoaded = true
            currentModelShortName = shortName
            statusMessage = "Model loaded."
            currentModelIdentifier = configurationIdentifier(configuration)
            refreshCachedModels()
        } catch {
            statusMessage = "Failed to load model: \(error.localizedDescription)"
            throw MLXError.modelLoadFailed(error.localizedDescription)
        }
    }
    
    /// Unloads the current model and frees memory.
    func unloadModel() {
        cancelGeneration()
        modelContainer = nil
        isModelLoaded = false
        modelInformation = nil
        currentModelShortName = nil
        currentPreset = nil
        downloadProgress = 0.0
        isLoadingModel = false
        loadingModelName = nil
        statusMessage = "No model loaded."
        currentModelIdentifier = nil
        isLoadingFromCache = false
        refreshCachedModels()
    }
    
    // MARK: - Text Generation
    
    /// Generation parameters
    struct GenerationConfig {
        var maxTokens: Int = 1024
        var temperature: Float =  0.7
        var topP: Float = 0.9
        var systemPrompt: String = AppConfig.systemPrompt
        
        static var `default` = GenerationConfig()
    }
    
    /// Generates a complete respnse (non-streaming)
    func generate(
        prompt: String,
        config: GenerationConfig = .default
    ) async throws -> String {
        guard let modelContainer = modelContainer else {
            throw MLXError.modelNotLoaded
        }
        
        let result = try await modelContainer.perform { context in
            let input = try await context.processor.prepare(
                input: .init(messages: [
                    ["role": "system", "content": config.systemPrompt],
                    ["role": "user", "content": prompt],
                
                ])
            )
            
            return try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: config.temperature),
                context: context
            ) { tokens in
                return tokens.count >= config.maxTokens ? .stop : .more
            }
        }
        
        return result.output
    }
    
    /// Generates a streaming response
    func generateStream(
        prompt: String,
        config: GenerationConfig = .default
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            currentGenerationTask = Task {
                guard let modelContainer = modelContainer else {
                    continuation.finish()
                    return
                }
                
                do {
                    _ = try await modelContainer.perform { context in
                        let chatMessages: [Chat.Message] = [
                            .system(config.systemPrompt),
                            .user(prompt)
                        ]
                        let userInput = UserInput(chat: chatMessages)
                        let input = try await context.processor.prepare(input: userInput)
                        
                        return try MLXLMCommon.generate(
                            input: input,
                            parameters: GenerateParameters(temperature: config.temperature),
                            context: context
                        ) { tokens in
                            // check for cancellation
                            if Task.isCancelled {
                                continuation.finish()
                                return .stop
                            }
                            // Decode and yield the current output
                            let text = context.tokenizer.decode(tokens: tokens)
                            continuation.yield(text)
                            
                            return tokens.count >= config.maxTokens ? .stop : .more
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }
    
    /// Generates with conversation history
    func generateStream(
      messages: [Message],
      config: GenerationConfig = .default
    ) -> AsyncStream<String> {
      // Reset metrics
      lastGenerationMetrics = nil
      generationStartTime = Date()
      firstTokenTime = nil
      tokenCount = 0

      return AsyncStream { continuation in
          currentGenerationTask = Task { [weak self] in
              guard let self, let container = modelContainer else {
                  continuation.finish()
                  return
              }

              do {
                  // Clear GPU cache before generation to free memory
                  MLX.GPU.clearCache()

                  // Find the last user message index (for image attachment)
                  let lastUserIndex = messages.lastIndex { $0.role == .user }

                  let chatMessages: [Chat.Message] = [
                      .system(config.systemPrompt)
                  ] + messages.enumerated().map { index, message in
                      let role: Chat.Message.Role = {
                          switch message.role {
                          case .user: return .user
                          case .assistant: return .assistant
                          case .system: return .system
                          }
                      }()

                      // ONLY attach images to the very last user message
                      // Skip ALL images from conversation history to save memory
                      let images: [UserInput.Image]
                      if index == lastUserIndex {
                          // VLMs typically accept a single image per request; cap to one for now.
                          // We can later fan out to multiple generations if multiple images are attached.
                          images = message.attachments.prefix(1).compactMap { attachment -> UserInput.Image? in
                              guard attachment.type == .image,
                                    let uiImage = UIImage(data: attachment.data),
                                    let resized = uiImage.resizedForVLM(maxDimension: 224),
                                    let ciImage = CIImage(image: resized) else {
                                  NSLog("[MLXService] Failed to process image attachment")
                                  return nil
                              }
                              NSLog("[MLXService] Processed image: %@", "\(resized.size)")
                              return .ciImage(ciImage)
                          }
                      } else {
                          images = []
                      }

                      // If message had images but we're not including them, note it in content
                      let content: String
                      if index != lastUserIndex && !message.attachments.isEmpty {
                          // Historical message with image - just reference it
                          content = message.content.isEmpty ? "[Previous image]" : message.content
                      } else if !images.isEmpty && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                          content = "Describe this image."
                      } else {
                          content = message.content
                      }

                      return Chat.Message(
                          role: role,
                          content: content,
                          images: images
                      )
                  }

                  NSLog("[MLXService] Created %d chat messages", chatMessages.count)

                  let userInput = UserInput(
                      chat: chatMessages,
                      processing: .init(resize: .init(width: 224, height: 224))
                  )

                  NSLog("[MLXService] Starting model.perform...")

                  _ = try await container.perform { [weak self] context in
                      NSLog("[MLXService] Preparing input...")
                      let input = try await context.processor.prepare(input: userInput)
                      NSLog("[MLXService] Input prepared, starting generation...")

                      return try MLXLMCommon.generate(
                          input: input,
                          parameters: GenerateParameters(temperature: config.temperature),
                          context: context
                      ) { tokens in
                          if Task.isCancelled {
                              continuation.finish()
                              return .stop
                          }

                          // Track first token time
                          Task { @MainActor [weak self] in
                              guard let self else { return }
                              if self.firstTokenTime == nil {
                                  self.firstTokenTime = Date()
                              }
                              self.tokenCount = tokens.count
                          }

                          let text = context.tokenizer.decode(tokens: tokens)
                          continuation.yield(text)

                          return tokens.count >= config.maxTokens ? .stop : .more
                      }
                  }

                  print("[MLXService] Generation complete")

                  // Calculate final metrics
                  await MainActor.run { [weak self] in
                      self?.finalizeMetrics()
                  }

                  continuation.finish()

              } catch {
                  print("[MLXService] Error during generation: \(error)")
                  continuation.finish()
              }
          }
      }
    }

    /// Finalizes and stores generation metrics.
    private func finalizeMetrics() {
        guard let startTime = generationStartTime else { return }

        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)

        var ttft: Double? = nil
        if let firstToken = firstTokenTime {
            ttft = firstToken.timeIntervalSince(startTime) * 1000 // Convert to ms
        }

        var tokensPerSecond: Double? = nil
        if tokenCount > 0 && totalTime > 0 {
            tokensPerSecond = Double(tokenCount) / totalTime
        }

        lastGenerationMetrics = GenerationMetrics(
            timeToFirstTokenMs: ttft,
            tokensPerSecond: tokensPerSecond,
            totalTokens: tokenCount > 0 ? tokenCount : nil,
            totalTimeSeconds: totalTime > 0 ? totalTime : nil
        )
    }

    /// Cancels any ongoing generation
    func cancelGeneration() {
      currentGenerationTask?.cancel()
      currentGenerationTask = nil
    }
}

// MARK: - Errors

 enum MLXError: Error, LocalizedError {
     case modelNotLoaded
     case generationFailed(String)
     case modelLoadFailed(String)
     case modelDeletionFailed(String)
     case modelInUse

     var errorDescription: String? {
         switch self {
         case .modelNotLoaded:
             return "No model is loaded. Please load a model first."
         case .generationFailed(let reason):
             return "Generation failed: \(reason)"
         case .modelLoadFailed(let reason):
             return "Failed to load model: \(reason)"
         case .modelDeletionFailed(let reason):
             return "Failed to delete model: \(reason)"
         case .modelInUse:
             return "Cannot delete a model that is currently loaded. Please unload it first."
         }
     }
 }

// MARK: - UIImage Extension for VLM

extension UIImage {
    /// Resizes image to fit within maxDimension while preserving aspect ratio.
    /// Returns nil if resizing fails.
    func resizedForVLM(maxDimension: CGFloat) -> UIImage? {
        let currentMax = max(size.width, size.height)
        guard currentMax > maxDimension else { return self }

        let scale = maxDimension / currentMax
        let newSize = CGSize(
            width: floor(size.width * scale),
            height: floor(size.height * scale)
        )

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
