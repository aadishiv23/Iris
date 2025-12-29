//
//  MLXService.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/9/25.
//

import Foundation
import CoreImage
#if os(iOS)
import UIKit
#endif
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

    /// Public accessor for the current model's identifier (e.g., HuggingFace ID).
    var modelIdentifier: String? { currentModelIdentifier }
    
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
        // Set GPU Cache Limit based on device
        // iPhone has limited memory - use 1.5GB max to leave room for the model
        #if os(iOS)
        let cacheLimit: Int = 1536 * 1024 * 1024  // 1.5GB for iPhone
        #else
        let cacheLimit: Int = 4 * 1024 * 1024 * 1024  // 4GB for Mac
        #endif
        MLX.GPU.set(cacheLimit: cacheLimit)
        Logger.info("MLXService initialized with GPU cache limit: \(cacheLimit / (1024*1024))MB", category: "MLX")

        // Set up memory pressure monitoring
        setupMemoryPressureMonitoring()

        refreshCachedModels()
    }

    /// Sets up monitoring for system memory pressure warnings
    private func setupMemoryPressureMonitoring() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Logger.warning("Received memory warning from system!", category: "MLX")
            self?.handleMemoryWarning()
        }
        #endif
    }

    /// Responds to memory pressure by clearing caches
    private func handleMemoryWarning() {
        Logger.warning("Handling memory warning - clearing GPU cache", category: "MLX")
        MLX.GPU.clearCache()

        // Log current state
        Logger.info("Memory warning handled", category: "MLX", metadata: [
            "isGenerating": String(currentGenerationTask != nil),
            "modelLoaded": String(isModelLoaded)
        ])
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
            guard var url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                return nil
            }
            url.appendPathComponent("models", isDirectory: true)

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

        /// Returns true if this model is memory-intensive and may crash on iPhone
        var isMemoryIntensive: Bool {
            switch self {
            case .qwen3_VL_4B_instruct_4bit, .qwen3_VL_4B_thinking_3bit,
                 .llama3_2_3B, .phi4bit, .qwen3_4b_4bit,
                 .gemma3n_E4B_it_lm_4bit:
                return true
            default:
                return false
            }
        }

        /// Warning message for memory-intensive models
        var memoryWarning: String? {
            guard isMemoryIntensive else { return nil }
            if modelType == .vlm {
                return "VLM models require significant memory. May crash on iPhone with long conversations."
            } else {
                return "This model requires significant memory. Keep conversations short to avoid crashes."
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
        Logger.info("Loading model preset: \(preset.displayName)", category: "MLX", metadata: [
            "modelType": String(describing: preset.modelType),
            "supportsImages": String(preset.supportsImages)
        ])
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
        let configId = configurationIdentifier(configuration) ?? "unknown"
        Logger.info("Starting model load", category: "MLX", metadata: [
            "configId": configId,
            "modelType": String(describing: modelType)
        ])

        // Clear GPU cache before loading to maximize available memory
        Logger.debug("Clearing GPU cache before model load", category: "MLX")
        MLX.GPU.clearCache()

        unloadModel()

        isLoadingModel = true
        let cached = hasCachedFiles(for: configuration)
        isLoadingFromCache = cached
        statusMessage = cached ? "Preparing cached model..." : "Downloading model..."
        downloadProgress = cached ? 1.0 : 0.0

        Logger.debug("Model cache status: \(cached ? "cached" : "needs download")", category: "MLX")

        defer {
            isLoadingModel = false
            loadingModelName = nil
            isLoadingFromCache = false
        }

        do {
            let factory: ModelFactory = modelType == .vlm ? VLMModelFactory.shared : LLMModelFactory.shared
            Logger.debug("Using factory: \(modelType == .vlm ? "VLM" : "LLM")", category: "MLX")

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

                Logger.info("Model loaded successfully", category: "MLX", metadata: [
                    "parameters": modelInformation ?? "unknown",
                    "configId": configId
                ])
                Logger.logMemoryUsage(context: "After model load")
            }

            isModelLoaded = true
            currentModelShortName = shortName
            statusMessage = "Model loaded."
            currentModelIdentifier = configurationIdentifier(configuration)
            refreshCachedModels()
        } catch {
            Logger.error("Model load failed: \(error.localizedDescription)", category: "MLX", metadata: [
                "configId": configId,
                "error": String(describing: error)
            ])
            statusMessage = "Failed to load model: \(error.localizedDescription)"
            throw MLXError.modelLoadFailed(error.localizedDescription)
        }
    }
    
    /// Unloads the current model and frees memory.
    func unloadModel() {
        Logger.info("Unloading model", category: "MLX", metadata: [
            "currentModel": currentModelIdentifier ?? "none"
        ])

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

        // Clear GPU cache after unloading to free memory
        MLX.GPU.clearCache()
        Logger.debug("GPU cache cleared after model unload", category: "MLX")

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
    
    /// Maximum number of messages to keep in conversation history to prevent OOM.
    /// VLM models use a much lower limit due to higher memory requirements.
    /// These are very conservative to prevent crashes on iPhone.
    private static let maxLLMHistoryMessages = 10
    private static let maxVLMHistoryMessages = 4  // VLM is extremely memory hungry

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

      let modelName = currentPreset?.displayName ?? currentModelIdentifier ?? "unknown"
      let isVLM = currentPreset?.modelType == .vlm

      Logger.logMemoryUsage(context: "Before generation")
      Logger.info("Starting generation", category: "Generation", metadata: [
          "model": modelName,
          "isVLM": String(isVLM),
          "messageCount": String(messages.count),
          "maxTokens": String(config.maxTokens)
      ])

      return AsyncStream { continuation in
          // Flag to ensure finish() is only called once (prevents race conditions)
          let finishOnce = FinishOnce(continuation: continuation)

          currentGenerationTask = Task { [weak self] in
              guard let self, let container = modelContainer else {
                  Logger.error("Generation failed: model container is nil", category: "Generation")
                  finishOnce.finish()
                  return
              }

              do {
                  // Clear GPU cache before generation to free memory
                  MLX.GPU.clearCache()
                  Logger.debug("GPU cache cleared", category: "Generation")

                  // Truncate conversation history to prevent OOM
                  // VLM models get a lower limit due to higher memory requirements
                  let maxMessages = currentPreset?.modelType == .vlm
                      ? Self.maxVLMHistoryMessages
                      : Self.maxLLMHistoryMessages

                  let truncatedMessages: [Message]
                  if messages.count > maxMessages {
                      // Keep the most recent messages
                      truncatedMessages = Array(messages.suffix(maxMessages))
                      Logger.warning("Truncated history from \(messages.count) to \(truncatedMessages.count) messages", category: "Generation")
                  } else {
                      truncatedMessages = messages
                  }

                  // Find the last user message index (for image attachment)
                  let lastUserIndex = truncatedMessages.lastIndex { $0.role == .user }

                  var imageCount = 0
                  let chatMessages: [Chat.Message] = [
                      .system(config.systemPrompt)
                  ] + truncatedMessages.enumerated().map { index, message in
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
                                  Logger.warning("Failed to process image attachment", category: "Generation")
                                  return nil
                              }
                              imageCount += 1
                              Logger.debug("Processed image: \(resized.size)", category: "Generation")
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

                  Logger.info("Prepared \(chatMessages.count) chat messages with \(imageCount) images", category: "Generation")

                  let userInput = UserInput(
                      chat: chatMessages,
                      processing: .init(resize: .init(width: 224, height: 224))
                  )

                  Logger.debug("Starting model.perform...", category: "Generation")

                  _ = try await container.perform { [weak self] context in
                      Task { @MainActor in Logger.debug("Preparing input via processor...", category: "Generation") }
                      let input = try await context.processor.prepare(input: userInput)
                      Task { @MainActor in Logger.debug("Input prepared, starting token generation...", category: "Generation") }

                      return try MLXLMCommon.generate(
                          input: input,
                          parameters: GenerateParameters(temperature: config.temperature),
                          context: context
                      ) { tokens in
                          if Task.isCancelled {
                              Task { @MainActor in Logger.info("Generation cancelled by user", category: "Generation") }
                              finishOnce.finish()
                              return .stop
                          }

                          // Track first token time
                          Task { @MainActor [weak self] in
                              guard let self else { return }
                              if self.firstTokenTime == nil {
                                  self.firstTokenTime = Date()
                                  Logger.debug("First token received", category: "Generation")
                              }
                              self.tokenCount = tokens.count
                          }

                          let text = context.tokenizer.decode(tokens: tokens)
                          continuation.yield(text)

                          return tokens.count >= config.maxTokens ? .stop : .more
                      }
                  }

                  Logger.info("Generation complete", category: "Generation")
                  Logger.logMemoryUsage(context: "After generation")

                  // Calculate final metrics
                  await MainActor.run { [weak self] in
                      self?.finalizeMetrics()
                  }

                  finishOnce.finish()

              } catch {
                  Logger.error("Generation error: \(error.localizedDescription)", category: "Generation", metadata: [
                      "errorType": String(describing: type(of: error)),
                      "errorDetails": String(describing: error)
                  ])
                  finishOnce.finish()
              }
          }
      }
    }

    /// Thread-safe wrapper to ensure AsyncStream continuation is finished exactly once
    private final class FinishOnce: @unchecked Sendable {
        private let continuation: AsyncStream<String>.Continuation
        private var finished = false
        private let lock = NSLock()

        init(continuation: AsyncStream<String>.Continuation) {
            self.continuation = continuation
        }

        func finish() {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            continuation.finish()
        }
    }

    /// Finalizes and stores generation metrics.
    private func finalizeMetrics() {
        guard let startTime = generationStartTime else {
            Logger.warning("Cannot finalize metrics: no start time recorded", category: "Generation")
            return
        }

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

        Logger.info("Generation metrics finalized", category: "Generation", metadata: [
            "totalTokens": String(tokenCount),
            "totalTime": String(format: "%.2fs", totalTime),
            "tokensPerSecond": tokensPerSecond.map { String(format: "%.1f", $0) } ?? "n/a",
            "ttft": ttft.map { String(format: "%.0fms", $0) } ?? "n/a"
        ])
    }

    /// Cancels any ongoing generation
    func cancelGeneration() {
        Logger.info("Cancelling generation", category: "Generation")
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
    /// Uses UIGraphicsImageRenderer for better memory management.
    /// Returns nil if resizing fails.
    func resizedForVLM(maxDimension: CGFloat) -> UIImage? {
        let currentMax = max(size.width, size.height)
        guard currentMax > maxDimension else { return self }

        let scale = maxDimension / currentMax
        let newSize = CGSize(
            width: floor(size.width * scale),
            height: floor(size.height * scale)
        )

        // Use UIGraphicsImageRenderer for automatic memory management
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
