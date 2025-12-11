//
//  MLXService.swift
//  Iris
//
//  Created by Aadi Malhotra on 12/9/25.
//

import Foundation
import MLX
import MLXNN
import MLXLLM
import MLXLMCommon
import Observation
internal import Tokenizers

/// Service responsible for managing MLX model lifecycle and text generation
/// This service handles model loading, inference, and streaming responses
@Observable
@MainActor
class MLXService {
    // MARK: - Public State
    
    /// State tracking whether a model is loaded and ready.
    var isModelLoaded = false
    
    /// The download progress from 0.0 to 1.0.
    var downloadProgress: Double = 0.0
    
    /// Status message
    var statusMessage: String = "No model loaded"
    
    /// Model information presented after loading
    var modelInformation: String?
    
    // MARK: - Private Properties
    
    /// A container for models that guarantees single threaded access.
    private var modelContainer: ModelContainer?
    
    private var currentGenerationTask: Task<Void, Never>?
    
    // MARK: - Initializer
    
    init() {
        // Set GPU Cache Limit, 2GB for now
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024 * 1024 * 1024)
    }

    // MARK: - Model Management
    
    /// Available model presets
    enum ModelPreset {
        case llama3_2_1B
        case llama3_2_3B
        case phi3_5
        case phi4bit
        case qwen3_4b_4bit
        case gemma3n_E2B_it_lm_4bit
        case gemma3n_E4B_it_lm_4bit
        case custom(String) // HuggingFace model ID

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
            case .custom(let id): return id
            }
        }
    }
    
    /// Loads a model from preset
    func loadModel(_ preset: ModelPreset) async throws {
        try await loadModel(configuration: preset.configuration)
    }
    
    /// Loads a model from given HuggingFace ID.
    func loadModel(hfID: String) async throws {
        let config = ModelConfiguration(id: hfID)
        try await loadModel(configuration: config)
    }
    
    /// Loads a model with the given configuration.
    func loadModel(configuration: ModelConfiguration) async throws {
        unloadModel()
        
        statusMessage = "Downloading model..."
        downloadProgress = 0.0
        
        do {
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            ) { [weak self] progress in
                
                let progressFraction = progress.fractionCompleted
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.downloadProgress = progressFraction
                    self.statusMessage = "Downloading model... (\(Int(progressFraction * 100))%)"
                }
            }
            
            // Get model informatoin
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
            statusMessage = "Model loaded."
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
        downloadProgress = 0.0
        statusMessage = "No model loaded."
    }
    
    // MARK: - Text Generation
    
    /// Generation parameters
    struct GenerationConfig {
        var maxTokens: Int = 1024
        var temperature: Float =  0.7
        var topP: Float = 0.9
        var systemPrompt: String = "You are a helpful assistant. Respond to the user in a helpful manner"
        
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
      AsyncStream { continuation in
          currentGenerationTask = Task {
              guard let container = modelContainer else {
                  continuation.finish()
                  return
              }

              do {
                  // Convert Message array to format expected by MLX
                  var chatMessages: [[String: String]] = [
                      ["role": "system", "content": config.systemPrompt]
                  ]

                  for message in messages {
                      chatMessages.append([
                          "role": message.role == .user ? "user" : "assistant",
                          "content": message.content
                      ])
                  }

                  _ = try await container.perform { context in
                      let input = try await context.processor.prepare(
                          input: .init(messages: chatMessages)
                      )

                      return try MLXLMCommon.generate(
                          input: input,
                          parameters: GenerateParameters(temperature: config.temperature),
                          context: context
                      ) { tokens in
                          if Task.isCancelled {
                              continuation.finish()
                              return .stop
                          }

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

     var errorDescription: String? {
         switch self {
         case .modelNotLoaded:
             return "No model is loaded. Please load a model first."
         case .generationFailed(let reason):
             return "Generation failed: \(reason)"
         case .modelLoadFailed(let reason):
             return "Failed to load model: \(reason)"
         }
     }
 }

