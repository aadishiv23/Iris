# Voice Features Implementation Guide

This document outlines the implementation plan for adding voice capabilities to Iris:
- **Speech-to-Text (STT)**: User speaks, app transcribes to text
- **Text-to-Speech (TTS)**: Model response is spoken aloud
- **Voice Chat Flow**: Full conversational loop with streaming UI

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Required Permissions](#required-permissions)
3. [Speech-to-Text Options](#speech-to-text-options)
   - [Option A: WhisperKit](#option-a-whisperkit-recommended)
   - [Option B: Apple Speech Framework](#option-b-apple-speech-framework)
   - [Option C: MLX Whisper](#option-c-mlx-whisper)
4. [Text-to-Speech Options](#text-to-speech-options)
   - [Option A: MLX Audio (Marvis TTS)](#option-a-mlx-audio-marvis-tts-recommended)
   - [Option B: AVSpeechSynthesizer](#option-b-avspeechsynthesizer-fallback)
5. [Voice Service Implementation](#voice-service-implementation)
6. [UI Components](#ui-components)
7. [Integration with ChatManager](#integration-with-chatmanager)
8. [Streaming TTS While LLM Generates](#streaming-tts-while-llm-generates)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Voice Chat Flow                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────┐    ┌─────────┐    ┌─────────┐    ┌─────────────────┐ │
│  │   User   │───▶│   STT   │───▶│   LLM   │───▶│      TTS        │ │
│  │  speaks  │    │(Whisper)│    │ (MLX)   │    │(AVSpeech/Neural)│ │
│  └──────────┘    └────┬────┘    └────┬────┘    └────────┬────────┘ │
│                       │              │                   │          │
│                       ▼              ▼                   ▼          │
│                  ┌─────────┐   ┌──────────┐        ┌──────────┐    │
│                  │Input Box│   │Streaming │        │  Audio   │    │
│                  │ (text)  │   │   UI     │        │ Playback │    │
│                  └─────────┘   └──────────┘        └──────────┘    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. User taps mic button → starts recording
2. Audio → STT engine → transcribed text (streaming or final)
3. Transcribed text → displayed in input field
4. User taps send (or auto-send) → LLM generates response
5. LLM streams response → UI updates in real-time
6. Response chunks → TTS queue → audio playback
7. User hears response while seeing it stream

---

## Required Permissions

Add to `Info.plist`:

```xml
<!-- Microphone access for voice recording -->
<key>NSMicrophoneUsageDescription</key>
<string>Iris needs microphone access so you can speak to the AI assistant.</string>

<!-- Speech recognition (required for Apple Speech Framework) -->
<key>NSSpeechRecognitionUsageDescription</key>
<string>Iris uses speech recognition to transcribe your voice into text.</string>
```

### Requesting Permissions at Runtime

```swift
import AVFoundation
import Speech

class PermissionsManager {

    static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
```

---

## Speech-to-Text Options

### Option A: WhisperKit (Recommended)

**Best for**: High-quality, fully on-device transcription

#### Installation

Add to `Package.swift` or via Xcode:

```swift
dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
]
```

#### Implementation

```swift
import WhisperKit

@Observable
class WhisperSTTService {
    private var whisperKit: WhisperKit?
    private var audioRecorder: AVAudioRecorder?
    private var isRecording = false

    // Available models (smaller = faster, larger = more accurate)
    enum WhisperModel: String, CaseIterable {
        case tiny = "openai_whisper-tiny"
        case base = "openai_whisper-base"
        case small = "openai_whisper-small"
        case medium = "openai_whisper-medium"  // Best balance

        var displayName: String {
            switch self {
            case .tiny: return "Tiny (~75MB)"
            case .base: return "Base (~140MB)"
            case .small: return "Small (~460MB)"
            case .medium: return "Medium (~1.5GB)"
            }
        }
    }

    var isModelLoaded = false
    var isTranscribing = false
    var loadingProgress: Double = 0

    // MARK: - Model Loading

    func loadModel(_ model: WhisperModel = .base) async throws {
        whisperKit = try await WhisperKit(
            model: model.rawValue,
            downloadBase: nil,  // Uses default cache
            modelRepo: "argmaxinc/whisperkit-coreml",
            verbose: false,
            logLevel: .none,
            prewarm: true,
            load: true,
            useBackgroundDownloadSession: false
        ) { progress in
            Task { @MainActor in
                self.loadingProgress = progress.fractionCompleted
            }
        }
        isModelLoaded = true
    }

    // MARK: - Recording

    func startRecording() async throws -> URL {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default)
        try audioSession.setActive(true)

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording.wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,  // Whisper expects 16kHz
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]

        audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
        audioRecorder?.record()
        isRecording = true

        return audioFilename
    }

    func stopRecording() -> URL? {
        audioRecorder?.stop()
        isRecording = false
        return audioRecorder?.url
    }

    // MARK: - Transcription

    func transcribe(audioURL: URL) async throws -> String {
        guard let whisperKit else {
            throw WhisperError.modelNotLoaded
        }

        isTranscribing = true
        defer { isTranscribing = false }

        let results = try await whisperKit.transcribe(audioPath: audioURL.path())
        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Streaming Transcription (Real-time)

    func transcribeStreaming() -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                guard let whisperKit else {
                    continuation.finish()
                    return
                }

                // WhisperKit supports streaming via transcribeWithResults
                // This is a simplified version - see WhisperKit docs for full streaming API
                do {
                    let audioURL = try await startRecording()

                    // Poll for intermediate results while recording
                    while isRecording {
                        try await Task.sleep(for: .milliseconds(500))

                        if let partialURL = audioRecorder?.url {
                            let results = try await whisperKit.transcribe(audioPath: partialURL.path())
                            let text = results.map { $0.text }.joined(separator: " ")
                            continuation.yield(text)
                        }
                    }

                    // Final transcription
                    if let finalURL = stopRecording() {
                        let results = try await whisperKit.transcribe(audioPath: finalURL.path())
                        let text = results.map { $0.text }.joined(separator: " ")
                        continuation.yield(text)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    enum WhisperError: Error {
        case modelNotLoaded
        case recordingFailed
    }
}
```

#### Pros & Cons

| Pros | Cons |
|------|------|
| Fully on-device, private | Model download required (75MB-1.5GB) |
| High accuracy | Initial model load takes time |
| Works offline | More complex setup |
| Streaming support | Battery usage during transcription |

---

### Option B: Apple Speech Framework

**Best for**: Quick implementation, no downloads, system integration

#### Implementation

```swift
import Speech
import AVFoundation

@Observable
class AppleSpeechSTTService {
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    var isListening = false
    var transcribedText = ""
    var isAvailable: Bool { speechRecognizer?.isAvailable ?? false }

    init(locale: Locale = .current) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Streaming Recognition

    func startListening() -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                do {
                    try await startRecognition { result in
                        continuation.yield(result)
                    }
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    private func startRecognition(onResult: @escaping (String) -> Void) async throws {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { throw SpeechError.requestFailed }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false  // Set true for offline (lower quality)

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        // Start recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                self.transcribedText = text
                onResult(text)
            }

            if error != nil || result?.isFinal == true {
                self.stopListening()
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    enum SpeechError: Error {
        case notAuthorized
        case notAvailable
        case requestFailed
    }
}
```

#### Pros & Cons

| Pros | Cons |
|------|------|
| Built-in, no downloads | Requires network for best quality |
| Easy to implement | Less accurate than Whisper |
| Low memory footprint | May have usage limits |
| System voice integration | Privacy: audio sent to Apple |

---

### Option C: MLX Whisper

**Best for**: Staying within MLX ecosystem, consistent architecture

#### Installation

MLX Swift doesn't have a dedicated Whisper package yet, but you can use the Python MLX Whisper model via a bridge or wait for native support.

For now, the recommended approach is to use WhisperKit which is optimized for Apple Silicon.

#### Future Implementation (when available)

```swift
// Hypothetical MLX Whisper API (not yet available in Swift)
import MLXWhisper

class MLXWhisperService {
    private var whisperModel: WhisperModel?

    func loadModel() async throws {
        // Similar pattern to LLMModelFactory
        whisperModel = try await WhisperModelFactory.shared.loadContainer(
            configuration: WhisperRegistry.whisper_base
        )
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let model = whisperModel else { throw WhisperError.modelNotLoaded }

        return try await model.perform { context in
            let audioData = try Data(contentsOf: audioURL)
            return try context.transcribe(audio: audioData)
        }
    }
}
```

#### Pros & Cons

| Pros | Cons |
|------|------|
| Consistent with MLX stack | Not yet available in Swift |
| GPU acceleration | Would need custom implementation |
| On-device processing | Less community support |

---

## Text-to-Speech Options

### Option A: MLX Audio (Marvis TTS) - Recommended

**Best for**: High-quality neural TTS, on-device, streaming support, consistent with MLX stack

[MLX Audio](https://github.com/Blaizzy/mlx-audio) is a Swift package providing TTS, STT, and speech-to-speech capabilities built on Apple's MLX framework.

#### Installation

**Via Xcode:**
1. Select File → Add Package Dependencies
2. Enter: `https://github.com/Blaizzy/mlx-audio.git`
3. Choose version (0.2.5+) and add `mlx-swift-audio` to your target

**Via Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/Blaizzy/mlx-audio.git", from: "0.2.5")
],
targets: [
    .target(
        name: "Iris",
        dependencies: [
            .product(name: "mlx-swift-audio", package: "mlx-audio")
        ]
    )
]
```

#### Platform Requirements
- macOS 14.0+
- iOS 16.0+

#### Available Models

| Model | Size | Best For |
|-------|------|----------|
| **Marvis TTS** | ~250MB | Real-time streaming, conversational |
| **Kokoro** | ~82MB | Multilingual, smaller footprint |
| **CSM-1B** | ~1GB | Voice cloning with reference audio |

#### Implementation

```swift
import MLXAudio
import AVFoundation

@Observable
@MainActor
class MLXTTSService {
    private var session: MarvisSession?

    var isModelLoaded = false
    var isLoading = false
    var isSpeaking = false
    var loadingProgress: Double = 0

    // Voice presets available in Marvis
    enum Voice {
        case conversationalA  // Default conversational voice
        case conversationalB
        // More voices available - check MLXAudio documentation

        var marvisVoice: MarvisSession.Voice {
            switch self {
            case .conversationalA: return .conversationalA
            case .conversationalB: return .conversationalB
            }
        }
    }

    // MARK: - Model Loading

    func loadModel(voice: Voice = .conversationalA) async throws {
        isLoading = true
        defer { isLoading = false }

        // MarvisSession downloads model on first use
        session = try await MarvisSession(
            voice: voice.marvisVoice,
            playbackEnabled: true  // Auto-plays audio
        )

        isModelLoaded = true
    }

    // MARK: - Basic Speech

    /// Generate and play speech for text
    func speak(_ text: String) async throws {
        guard let session else {
            throw TTSError.modelNotLoaded
        }

        isSpeaking = true
        defer { isSpeaking = false }

        let result = try await session.generate(for: text)
        print("Generated \(result.sampleCount) samples @ \(result.sampleRate) Hz")
    }

    // MARK: - Streaming Speech (for LLM output)

    /// Stream speech as audio chunks - ideal for LLM streaming output
    func speakStreaming(_ text: String, interval: Double = 0.5) async throws {
        guard let session else {
            throw TTSError.modelNotLoaded
        }

        isSpeaking = true
        defer { isSpeaking = false }

        for try await chunk in session.stream(text: text, streamingInterval: interval) {
            // Each chunk contains PCM samples that play automatically
            print("Chunk: samples=\(chunk.sampleCount) rtf=\(chunk.realTimeFactor)")

            // Real-time factor < 1.0 means faster than real-time
            // (good for keeping up with streaming text)
        }
    }

    // MARK: - Raw Audio (for custom processing)

    /// Generate raw PCM audio without auto-playback
    func generateRaw(_ text: String) async throws -> (audio: [Float], sampleRate: Int) {
        // Create session without playback for raw audio access
        let rawSession = try await MarvisSession(
            voice: .conversationalA,
            playbackEnabled: false
        )

        let result = try await rawSession.generateRaw(for: text)
        return (result.audio, result.sampleRate)
    }

    /// Save generated audio to file
    func saveToFile(_ text: String, url: URL) async throws {
        let (audio, sampleRate) = try await generateRaw(text)

        // Convert to WAV file
        let audioData = try createWAVData(from: audio, sampleRate: sampleRate)
        try audioData.write(to: url)
    }

    private func createWAVData(from samples: [Float], sampleRate: Int) throws -> Data {
        var data = Data()

        // WAV header
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample) / 8)
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = UInt32(samples.count * 2)
        let fileSize = 36 + dataSize

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Convert Float samples to Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Sample = Int16(clamped * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Array($0) })
        }

        return data
    }

    // MARK: - Errors

    enum TTSError: Error, LocalizedError {
        case modelNotLoaded
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "TTS model not loaded. Call loadModel() first."
            case .generationFailed(let reason):
                return "TTS generation failed: \(reason)"
            }
        }
    }
}
```

#### Streaming TTS with LLM Output

```swift
// In ChatManager - speak as LLM streams
class StreamingTTSController {
    private let ttsService: MLXTTSService
    private var buffer = ""
    private var speakingTask: Task<Void, Never>?

    init(ttsService: MLXTTSService) {
        self.ttsService = ttsService
    }

    /// Feed streaming LLM chunks
    func feed(_ chunk: String) {
        buffer += chunk

        // Extract complete sentences for natural speech
        let sentencePattern = #"[^.!?\n]+[.!?\n]+"#

        while let match = buffer.range(of: sentencePattern, options: .regularExpression) {
            let sentence = String(buffer[match]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[match.upperBound...])

            if !sentence.isEmpty {
                queueSentence(sentence)
            }
        }
    }

    /// Call when LLM finishes
    func finish() {
        let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            queueSentence(remaining)
        }
        buffer = ""
    }

    private var sentenceQueue: [String] = []
    private var isProcessing = false

    private func queueSentence(_ sentence: String) {
        sentenceQueue.append(sentence)
        processQueue()
    }

    private func processQueue() {
        guard !isProcessing, !sentenceQueue.isEmpty else { return }

        isProcessing = true
        let sentence = sentenceQueue.removeFirst()

        speakingTask = Task {
            do {
                try await ttsService.speakStreaming(sentence, interval: 0.3)
            } catch {
                print("TTS error: \(error)")
            }

            await MainActor.run {
                self.isProcessing = false
                self.processQueue()
            }
        }
    }

    func stop() {
        speakingTask?.cancel()
        sentenceQueue.removeAll()
        buffer = ""
        isProcessing = false
    }
}
```

#### Pros & Cons

| Pros | Cons |
|------|------|
| High-quality neural voice | Model download required (~250MB) |
| Real-time streaming support | Initial model load time |
| Fully on-device, private | Higher battery usage than AVSpeech |
| Consistent with MLX stack | Requires iOS 16+ / macOS 14+ |
| GPU accelerated on Apple Silicon | |

---

### Option B: AVSpeechSynthesizer (Fallback)

**Best for**: Quick fallback, no downloads, maximum compatibility

Use as fallback when MLX Audio model isn't loaded or for low-power scenarios.

#### Implementation

```swift
import AVFoundation

@Observable
class SystemTTSService {
    private let synthesizer = AVSpeechSynthesizer()
    private var speechDelegate: SpeechDelegate?

    var isSpeaking: Bool { synthesizer.isSpeaking }

    // Best available system voice
    static var recommendedVoice: AVSpeechSynthesisVoice? {
        let premiumIdentifiers = [
            "com.apple.voice.premium.en-US.Zoe",
            "com.apple.voice.premium.en-US.Ava",
            "com.apple.voice.enhanced.en-US.Samantha"
        ]

        for identifier in premiumIdentifiers {
            if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
                return voice
            }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.recommendedVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // Streaming support via sentence buffering
    private var pendingText = ""

    func speakStreaming(_ chunk: String) {
        pendingText += chunk

        // Speak complete sentences
        while let range = pendingText.range(of: #"[.!?\n]"#, options: .regularExpression) {
            let sentence = String(pendingText[..<range.upperBound])
            pendingText = String(pendingText[range.upperBound...])

            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                speak(trimmed)
            }
        }
    }

    func finishStreaming() {
        let remaining = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            speak(remaining)
        }
        pendingText = ""
    }

    func onFinished(_ handler: @escaping () -> Void) {
        speechDelegate = SpeechDelegate(onFinished: handler)
        synthesizer.delegate = speechDelegate
    }

    private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
        let onFinished: () -> Void
        init(onFinished: @escaping () -> Void) { self.onFinished = onFinished }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            if !synthesizer.isSpeaking { onFinished() }
        }
    }
}
```

#### Pros & Cons

| Pros | Cons |
|------|------|
| No download required | Robotic voice quality |
| Works offline | Less natural sounding |
| Low battery usage | Limited expressiveness |
| Maximum compatibility | |

---

## Voice Service Implementation

Unified service combining STT (WhisperKit) and TTS (MLX Audio):

```swift
import Foundation
import AVFoundation
import MLXAudio

@Observable
@MainActor
class VoiceService {
    // MARK: - Services

    private let sttService: WhisperSTTService
    private let ttsService: MLXTTSService
    private let fallbackTTS: SystemTTSService  // Fallback when MLX not loaded
    private var streamingController: StreamingTTSController?

    // MARK: - State

    enum VoiceState {
        case idle
        case loadingModels
        case listening
        case transcribing
        case speaking
    }

    var state: VoiceState = .idle
    var currentTranscription = ""
    var error: Error?

    // Model loading progress
    var sttModelLoaded = false
    var ttsModelLoaded = false
    var loadingProgress: Double = 0

    // Settings
    var autoSendAfterTranscription = false
    var autoSpeakResponses = true
    var useFallbackTTS = false  // Use system TTS instead of MLX

    init() {
        self.sttService = WhisperSTTService()
        self.ttsService = MLXTTSService()
        self.fallbackTTS = SystemTTSService()
    }

    // MARK: - Setup

    /// Load both STT and TTS models
    func setup() async throws {
        // Request permissions first
        guard await PermissionsManager.requestMicrophonePermission() else {
            throw VoiceError.microphonePermissionDenied
        }

        state = .loadingModels

        // Load models in parallel
        async let sttLoad: () = loadSTTModel()
        async let ttsLoad: () = loadTTSModel()

        do {
            try await sttLoad
            try await ttsLoad
        } catch {
            self.error = error
        }

        state = .idle
    }

    private func loadSTTModel() async throws {
        try await sttService.loadModel(.base)  // ~140MB
        sttModelLoaded = true
    }

    private func loadTTSModel() async throws {
        try await ttsService.loadModel(voice: .conversationalA)  // ~250MB
        ttsModelLoaded = true
    }

    // MARK: - Voice Input (Tap to Toggle)

    func toggleListening() async {
        switch state {
        case .idle:
            await startListening()
        case .listening:
            await stopListening()
        default:
            break
        }
    }

    private func startListening() async {
        guard sttModelLoaded else {
            error = VoiceError.modelNotLoaded
            return
        }

        state = .listening
        currentTranscription = ""

        do {
            _ = try await sttService.startRecording()
        } catch {
            self.error = error
            state = .idle
        }
    }

    private func stopListening() async {
        guard let audioURL = sttService.stopRecording() else {
            state = .idle
            return
        }

        state = .transcribing

        do {
            currentTranscription = try await sttService.transcribe(audioURL: audioURL)
            state = .idle
        } catch {
            self.error = error
            state = .idle
        }
    }

    // MARK: - Voice Output

    /// Speak a complete text (non-streaming)
    func speak(_ text: String) async {
        guard autoSpeakResponses else { return }

        state = .speaking
        defer { state = .idle }

        if ttsModelLoaded && !useFallbackTTS {
            do {
                try await ttsService.speak(text)
            } catch {
                // Fall back to system TTS on error
                fallbackTTS.speak(text)
            }
        } else {
            fallbackTTS.speak(text)
        }
    }

    /// Start streaming TTS controller for LLM output
    func beginStreamingSpeech() {
        guard autoSpeakResponses else { return }

        if ttsModelLoaded && !useFallbackTTS {
            streamingController = StreamingTTSController(ttsService: ttsService)
        }
        state = .speaking
    }

    /// Feed a chunk of streaming LLM text
    func feedStreamingChunk(_ chunk: String) {
        guard autoSpeakResponses else { return }

        if let controller = streamingController {
            controller.feed(chunk)
        } else {
            // Fallback to system TTS streaming
            fallbackTTS.speakStreaming(chunk)
        }
    }

    /// Finish streaming speech
    func finishStreamingSpeech() {
        if let controller = streamingController {
            controller.finish()
            streamingController = nil
        } else {
            fallbackTTS.finishStreaming()
        }
        state = .idle
    }

    /// Stop all speech immediately
    func stopSpeaking() {
        streamingController?.stop()
        streamingController = nil
        fallbackTTS.stop()
        state = .idle
    }

    // MARK: - Errors

    enum VoiceError: Error, LocalizedError {
        case microphonePermissionDenied
        case speechRecognitionPermissionDenied
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone access is required for voice input."
            case .speechRecognitionPermissionDenied:
                return "Speech recognition permission is required."
            case .modelNotLoaded:
                return "Voice models are not loaded. Please wait for setup to complete."
            }
        }
    }
}
```

---

## UI Components

### Microphone Button (Tap to Toggle)

```swift
import SwiftUI

struct MicrophoneButton: View {
    @Environment(VoiceService.self) private var voiceService

    var body: some View {
        Button {
            Task {
                await voiceService.toggleListening()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 56, height: 56)

                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(iconColor)

                // Listening indicator
                if voiceService.state == .listening {
                    Circle()
                        .stroke(Color.red, lineWidth: 3)
                        .frame(width: 56, height: 56)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: voiceService.state
                        )
                }
            }
        }
        .disabled(voiceService.state == .transcribing)
    }

    private var backgroundColor: Color {
        switch voiceService.state {
        case .listening: return .red.opacity(0.2)
        case .transcribing: return .orange.opacity(0.2)
        case .speaking: return .blue.opacity(0.2)
        case .idle: return .secondary.opacity(0.1)
        }
    }

    private var iconName: String {
        switch voiceService.state {
        case .listening: return "mic.fill"
        case .transcribing: return "waveform"
        case .speaking: return "speaker.wave.2.fill"
        case .idle: return "mic"
        }
    }

    private var iconColor: Color {
        switch voiceService.state {
        case .listening: return .red
        case .transcribing: return .orange
        case .speaking: return .blue
        case .idle: return .primary
        }
    }

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0
}
```

### Voice Status Indicator

```swift
struct VoiceStatusView: View {
    @Environment(VoiceService.self) private var voiceService

    var body: some View {
        HStack(spacing: 8) {
            switch voiceService.state {
            case .listening:
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                Text("Listening...")
                    .foregroundStyle(.secondary)

            case .transcribing:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Transcribing...")
                    .foregroundStyle(.secondary)

            case .speaking:
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.blue)
                    .symbolEffect(.variableColor.iterative)
                Text("Speaking...")
                    .foregroundStyle(.secondary)

            case .idle:
                EmptyView()
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .opacity(voiceService.state == .idle ? 0 : 1)
        .animation(.easeInOut, value: voiceService.state)
    }
}
```

---

## Integration with ChatManager

Add voice support to ChatManager:

```swift
// In ChatManager.swift

@Observable
class ChatManager {
    // ... existing properties ...

    let voiceService = VoiceService()

    // MARK: - Voice Chat

    func setupVoice() async throws {
        try await voiceService.setup()
    }

    /// Called when user finishes speaking (tap to toggle off)
    func processVoiceInput() async {
        guard !voiceService.currentTranscription.isEmpty else { return }

        let transcript = voiceService.currentTranscription
        voiceService.currentTranscription = ""

        // Send as message
        await sendMessage(transcript)
    }

    /// Modified sendMessage to optionally speak response
    func sendMessage(_ content: String, speakResponse: Bool = true) async {
        // ... existing message handling ...

        // During streaming, optionally speak chunks
        for await chunk in mlxService.generateStream(messages: messages) {
            // Update UI
            updateAssistantMessage(/* ... */)

            // Speak if enabled
            if speakResponse {
                voiceService.speakStreaming(chunk)
            }
        }

        // Finish speaking
        if speakResponse {
            voiceService.finishSpeaking()
        }
    }
}
```

---

## Streaming TTS While LLM Generates

The key challenge is speaking the LLM output as it streams, without stuttering or unnatural pauses.

### Strategy: Sentence Buffering

```swift
class StreamingTTSController {
    private let ttsService: TTSService
    private var buffer = ""
    private var sentenceQueue: [String] = []
    private var isSpeaking = false

    init(ttsService: TTSService) {
        self.ttsService = ttsService
    }

    /// Feed streaming LLM output
    func feed(_ chunk: String) {
        buffer += chunk

        // Extract complete sentences
        extractAndQueueSentences()

        // Start speaking if not already
        if !isSpeaking && !sentenceQueue.isEmpty {
            speakNext()
        }
    }

    /// Call when LLM finishes generating
    func finish() {
        // Queue any remaining text
        let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            sentenceQueue.append(remaining)
        }
        buffer = ""

        if !isSpeaking && !sentenceQueue.isEmpty {
            speakNext()
        }
    }

    private func extractAndQueueSentences() {
        // Find sentence boundaries
        let pattern = #"[^.!?\n]+[.!?\n]+"#

        while let match = buffer.range(of: pattern, options: .regularExpression) {
            let sentence = String(buffer[match]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentenceQueue.append(sentence)
            }
            buffer = String(buffer[match.upperBound...])
        }
    }

    private func speakNext() {
        guard !sentenceQueue.isEmpty else {
            isSpeaking = false
            return
        }

        isSpeaking = true
        let sentence = sentenceQueue.removeFirst()

        ttsService.speak(sentence)
        ttsService.onSpeechFinished { [weak self] in
            self?.speakNext()
        }
    }

    func stop() {
        sentenceQueue.removeAll()
        buffer = ""
        ttsService.stop()
        isSpeaking = false
    }
}
```

### Usage in ChatManager

```swift
// In ChatManager.sendMessage
private var streamingTTS: StreamingTTSController?

func sendMessage(_ content: String) async {
    // ... prepare message ...

    // Initialize streaming TTS
    if voiceService.autoSpeakResponses {
        streamingTTS = StreamingTTSController(ttsService: voiceService.ttsService)
    }

    var previousLength = 0
    var fullResponse = ""

    for await fullText in mlxService.generateStream(messages: messages) {
        if Task.isCancelled { break }

        // Extract new chunk
        let newText = String(fullText.dropFirst(previousLength))
        previousLength = fullText.count
        fullResponse += newText

        // Update UI
        updateAssistantMessage(conversationId: conversationId, messageId: assistantMessageId, content: fullResponse)

        // Feed to TTS
        streamingTTS?.feed(newText)
    }

    // Finish TTS
    streamingTTS?.finish()
    streamingTTS = nil

    // ... finalize message ...
}
```

---

## Summary Checklist

### Phase 1: Dependencies & Permissions
- [ ] Add microphone permission to Info.plist (`NSMicrophoneUsageDescription`)
- [ ] Add WhisperKit package: `https://github.com/argmaxinc/WhisperKit.git`
- [ ] Add MLX Audio package: `https://github.com/Blaizzy/mlx-audio.git`

### Phase 2: Speech-to-Text (STT)
- [ ] Create `WhisperSTTService` class
- [ ] Implement model loading with progress
- [ ] Implement recording start/stop
- [ ] Implement transcription

### Phase 3: Text-to-Speech (TTS)
- [ ] Create `MLXTTSService` class with MarvisSession
- [ ] Create `SystemTTSService` as fallback
- [ ] Implement streaming TTS controller for LLM output
- [ ] Add sentence buffering for natural speech

### Phase 4: Unified Voice Service
- [ ] Create `VoiceService` combining STT + TTS
- [ ] Implement parallel model loading
- [ ] Add tap-to-toggle voice input
- [ ] Add streaming speech for LLM responses

### Phase 5: UI Components
- [ ] Add microphone button to input bar
- [ ] Add voice status indicator
- [ ] Add speaker button to message bubbles (optional)
- [ ] Add voice settings in settings view

### Phase 6: ChatManager Integration
- [ ] Wire voice transcription to message input
- [ ] Add streaming TTS during LLM generation
- [ ] Add auto-send after transcription (optional)
- [ ] Handle cancellation gracefully

### Phase 7: Advanced Features (Future)
- [ ] Add Apple Speech Framework as STT fallback
- [ ] Add voice activity detection (auto-stop recording)
- [ ] Add continuous conversation mode
- [ ] Add voice model selection UI
- [ ] Add Kokoro TTS for multilingual support

---

## Resources

- [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit)
- [MLX Audio GitHub](https://github.com/Blaizzy/mlx-audio) - TTS, STT, STS for Apple Silicon
- [Marvis TTS on HuggingFace](https://huggingface.co/Marvis-AI/marvis-tts-250m-v0.1)
- [Apple Speech Framework Docs](https://developer.apple.com/documentation/speech)
- [AVSpeechSynthesizer Docs](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)
- [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples)
- [WWDC25: Explore LLMs on Apple Silicon with MLX](https://developer.apple.com/videos/play/wwdc2025/298/)
