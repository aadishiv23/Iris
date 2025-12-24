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
   - [Option A: AVSpeechSynthesizer](#option-a-avspeechsynthesizer-quick-start)
   - [Option B: Neural TTS](#option-b-neural-tts-future)
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

### Option A: AVSpeechSynthesizer (Quick Start)

**Best for**: Fast implementation, works immediately, no downloads

#### Implementation

```swift
import AVFoundation

@Observable
class TTSService {
    private let synthesizer = AVSpeechSynthesizer()
    private var speechDelegate: SpeechDelegate?

    var isSpeaking: Bool { synthesizer.isSpeaking }
    var isPaused: Bool { synthesizer.isPaused }

    // Available voices
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.starts(with: "en")  // English voices
        }
    }

    // Recommended voices for natural sound
    static var recommendedVoice: AVSpeechSynthesisVoice? {
        // Premium voices (iOS 17+)
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

        // Fallback to best available
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    struct SpeechConfig {
        var voice: AVSpeechSynthesisVoice?
        var rate: Float = AVSpeechUtteranceDefaultSpeechRate  // 0.0 - 1.0
        var pitch: Float = 1.0  // 0.5 - 2.0
        var volume: Float = 1.0  // 0.0 - 1.0
        var preUtteranceDelay: TimeInterval = 0
        var postUtteranceDelay: TimeInterval = 0

        static var `default`: SpeechConfig {
            SpeechConfig(voice: TTSService.recommendedVoice)
        }
    }

    // MARK: - Basic Speech

    func speak(_ text: String, config: SpeechConfig = .default) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = config.voice ?? Self.recommendedVoice
        utterance.rate = config.rate
        utterance.pitchMultiplier = config.pitch
        utterance.volume = config.volume
        utterance.preUtteranceDelay = config.preUtteranceDelay
        utterance.postUtteranceDelay = config.postUtteranceDelay

        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    // MARK: - Streaming Speech (for LLM output)

    /// Speaks text in chunks, suitable for streaming LLM output
    /// Queues sentences and speaks them sequentially
    private var pendingText = ""
    private var speakingQueue: [String] = []

    func speakStreaming(_ chunk: String, config: SpeechConfig = .default) {
        pendingText += chunk

        // Extract complete sentences
        let sentenceEndings = [".", "!", "?", "\n"]

        for ending in sentenceEndings {
            while let range = pendingText.range(of: ending) {
                let sentence = String(pendingText[..<range.upperBound])
                pendingText = String(pendingText[range.upperBound...])

                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    queueSentence(trimmed, config: config)
                }
            }
        }
    }

    /// Call when streaming is complete to speak any remaining text
    func finishStreaming(config: SpeechConfig = .default) {
        let remaining = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            queueSentence(remaining, config: config)
        }
        pendingText = ""
    }

    private func queueSentence(_ sentence: String, config: SpeechConfig) {
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = config.voice ?? Self.recommendedVoice
        utterance.rate = config.rate
        utterance.pitchMultiplier = config.pitch
        utterance.volume = config.volume

        synthesizer.speak(utterance)
    }

    // MARK: - Delegate for callbacks

    func onSpeechFinished(_ handler: @escaping () -> Void) {
        speechDelegate = SpeechDelegate(onFinished: handler)
        synthesizer.delegate = speechDelegate
    }

    private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
        let onFinished: () -> Void

        init(onFinished: @escaping () -> Void) {
            self.onFinished = onFinished
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            if !synthesizer.isSpeaking {
                onFinished()
            }
        }
    }
}
```

#### Pros & Cons

| Pros | Cons |
|------|------|
| No setup required | Robotic voice quality |
| Works offline | Limited voice options |
| Low latency | No voice cloning |
| Battery efficient | Less expressive |

---

### Option B: Neural TTS (Future)

**Best for**: Natural-sounding speech, voice cloning, emotional expression

#### Options to Consider

1. **Coqui TTS** (via ONNX or Core ML conversion)
2. **Bark** (Suno AI - text to audio with emotion)
3. **Piper** (fast, local TTS)
4. **ElevenLabs API** (cloud, high quality)

#### Placeholder Implementation

```swift
import Foundation

protocol NeuralTTSEngine {
    func loadModel() async throws
    func synthesize(_ text: String) async throws -> Data  // Audio data
    func synthesizeStreaming(_ text: String) -> AsyncStream<Data>
}

// Example: ElevenLabs API (cloud-based)
class ElevenLabsTTS: NeuralTTSEngine {
    private let apiKey: String
    private let voiceId: String

    init(apiKey: String, voiceId: String = "default") {
        self.apiKey = apiKey
        self.voiceId = voiceId
    }

    func loadModel() async throws {
        // No-op for API-based TTS
    }

    func synthesize(_ text: String) async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_monolingual_v1",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.5
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    func synthesizeStreaming(_ text: String) -> AsyncStream<Data> {
        // ElevenLabs supports streaming via websockets
        // Implementation would use URLSession.webSocketTask
        fatalError("Streaming TTS not implemented")
    }
}

// Example: Local Neural TTS (future)
class LocalNeuralTTS: NeuralTTSEngine {
    // Would use Core ML or ONNX Runtime
    // Models: Piper, Coqui, etc. converted to mlpackage

    func loadModel() async throws {
        // Load Core ML model
    }

    func synthesize(_ text: String) async throws -> Data {
        // Run inference
        fatalError("Not implemented")
    }

    func synthesizeStreaming(_ text: String) -> AsyncStream<Data> {
        fatalError("Not implemented")
    }
}
```

---

## Voice Service Implementation

Unified service combining STT and TTS:

```swift
import Foundation
import AVFoundation

@Observable
@MainActor
class VoiceService {
    // MARK: - Services

    private let sttService: WhisperSTTService  // or AppleSpeechSTTService
    private let ttsService: TTSService

    // MARK: - State

    enum VoiceState {
        case idle
        case listening
        case transcribing
        case speaking
    }

    var state: VoiceState = .idle
    var currentTranscription = ""
    var error: Error?

    // Settings
    var autoSendAfterTranscription = false
    var autoSpeakResponses = true

    init() {
        self.sttService = WhisperSTTService()
        self.ttsService = TTSService()
    }

    // MARK: - Setup

    func setup() async throws {
        // Request permissions
        guard await PermissionsManager.requestMicrophonePermission() else {
            throw VoiceError.microphonePermissionDenied
        }

        // Load Whisper model
        try await sttService.loadModel(.base)
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

    func speak(_ text: String) {
        guard autoSpeakResponses else { return }
        state = .speaking
        ttsService.speak(text)
        ttsService.onSpeechFinished { [weak self] in
            Task { @MainActor in
                self?.state = .idle
            }
        }
    }

    func speakStreaming(_ chunk: String) {
        guard autoSpeakResponses else { return }
        if state != .speaking {
            state = .speaking
        }
        ttsService.speakStreaming(chunk)
    }

    func finishSpeaking() {
        ttsService.finishStreaming()
        ttsService.onSpeechFinished { [weak self] in
            Task { @MainActor in
                self?.state = .idle
            }
        }
    }

    func stopSpeaking() {
        ttsService.stop()
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
                return "Voice model is not loaded."
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

### Phase 1: Basic Voice Input (STT)
- [ ] Add microphone permission to Info.plist
- [ ] Add WhisperKit dependency
- [ ] Create WhisperSTTService
- [ ] Add microphone button to input bar
- [ ] Integrate with ChatManager

### Phase 2: Basic Voice Output (TTS)
- [ ] Create TTSService with AVSpeechSynthesizer
- [ ] Add speaker button to message bubbles
- [ ] Add auto-speak toggle in settings
- [ ] Implement streaming TTS

### Phase 3: Full Voice Chat
- [ ] Create unified VoiceService
- [ ] Add voice status indicators
- [ ] Implement tap-to-toggle flow
- [ ] Add voice settings UI

### Phase 4: Advanced (Future)
- [ ] Add Apple Speech Framework as fallback
- [ ] Integrate neural TTS
- [ ] Add voice activity detection
- [ ] Implement continuous conversation mode

---

## Resources

- [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit)
- [Apple Speech Framework Docs](https://developer.apple.com/documentation/speech)
- [AVSpeechSynthesizer Docs](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)
- [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples)
