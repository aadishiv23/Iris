# Iris Project Summary

## What It Is

A native iOS chat app that runs LLMs locally on-device using Apple's MLX framework. No server, no API calls—completely offline AI chat.

---

## Architecture

```
IrisApp
    └── ContentView (router)
            ├── HomeView (when activeConversationId == nil)
            └── ChatView (when activeConversationId != nil)
                    └── ChatConversationView
                            ├── MessageRow (per message)
                            ├── TypingIndicatorView (while generating)
                            └── GlassInputView (text input + send/stop)
```

**Data flow:**

```
MLXService (model loading, text generation)
     │
     ▼
ChatManager (owns conversations, coordinates generation)
     │
     ▼
ChatViewModel (thin UI layer, owns input text)
     │
     ▼
Views (display only)
```

---

## Files Completed

| File | Location | Purpose |
|------|----------|---------|
| `Message.swift` | Models/ | Message struct: id, role, content, timestamp |
| `Conversation.swift` | Models/ | Conversation struct: id, messages, createdAt, updatedAt |
| `MLXService.swift` | Services/ | Model loading (Llama, Phi, Qwen, Gemma), streaming generation via AsyncStream |
| `ChatManager.swift` | Managers/ | Owns conversations array, activeConversationId, sendMessage(), cancelGeneration() |
| `ChatViewModel.swift` | ViewModels/ | Thin layer: owns inputText, delegates to ChatManager |
| `IrisApp.swift` | Root | App entry: creates MLXService → ChatManager → ContentView |
| `ContentView.swift` | Root | Router: shows ChatView or HomeView based on activeConversationId |
| `HomeView.swift` | Views/Home/ | Conversation list, new chat button, swipe-to-delete |
| `ChatView.swift` | Views/Chat/ | Main chat container, toolbar (home/model menu/new chat), sheets for settings/model picker |
| `ChatConversationView.swift` | Views/Chat/ | Scrollable messages + input, auto-scroll, scroll-to-bottom button |
| `MessageRow.swift` | Views/Components/ | User: blue gradient bubble. Assistant: plain text |
| `TypingIndicatorView.swift` | Views/Components/ | Animated bouncing dots using TimelineView + sine wave |
| `GlassInputView.swift` | Views/Components/ | TextField + SendButton with Liquid Glass, focus state for keyboard dismiss |
| `AnimatedBackgroundView.swift` | Views/Components/ | Floating indigo/blue blurred circles |

---

## Key Features Implemented

| Feature | Implementation |
|---------|----------------|
| Multiple conversations | ChatManager.conversations array |
| Conversation switching | selectConversation(), goHome() |
| Streaming responses | MLXService.generateStream() → AsyncStream<String> |
| Auto-scroll | ScrollViewReader + onChange of messages.count/content |
| Scroll-to-bottom button | GeometryReader + PreferenceKey to detect scroll position |
| Keyboard dismiss on send | @FocusState binding |
| Model switching | ModelPickerView with presets |
| Typing indicator | TimelineView animation (not withAnimation, which doesn't work for sine) |
| Cross-platform shapes | BubbleShape uses pure SwiftUI Path (no UIBezierPath) |

---

## Design Decisions

1. **Option C architecture** — MLXService → ChatManager → ChatViewModel. One model instance shared across all conversations.

2. **Init injection over @Environment** — ChatManager passed explicitly. Allows immediate initialization.

3. **Dumb views** — MessageRow, GlassInputView, etc. receive data/closures, don't know about ViewModels.

4. **ZStack for input** — GlassInputView floats over ScrollView with blur, like Messages app.

5. **Home via toolbar** — App launches to new conversation, home accessed via button (not landing page).

---

## What's Not Done

| Task | Status |
|------|--------|
| Persistence | ❌ Conversations lost on restart |
| Model download progress UI | ⚠️ Basic, could show progress bar |
| Settings screen | ⚠️ Placeholder only |
| Error handling UI | ❌ Errors just print to console |
| Welcome/empty state | ❌ Could add prompt suggestions |
| macOS target | ⚠️ Code is ready, needs target setup |

---

## Dependencies

- `mlx-swift` — Core MLX framework
- `mlx-swift-examples` / `mlx-swift-lm` — MLXLLM, ModelContainer, LLMModelFactory
- `Gzip`, `Jinja`, `swift-transformers`, `swift-numerics`, `swift-collections`

---

## Git State

- Branch: `chat-ui-plus-mlx`
- Reference worktree: `../Iris-chat-feature`

---

## File Structure

```
Iris/
├── IrisApp.swift
├── ContentView.swift
│
├── Models/
│   ├── Message.swift
│   └── Conversation.swift
│
├── Services/
│   └── MLXService.swift
│
├── Managers/
│   └── ChatManager.swift
│
├── ViewModels/
│   └── ChatViewModel.swift
│
└── Views/
    ├── Chat/
    │   ├── ChatView.swift
    │   └── ChatConversationView.swift
    │
    ├── Home/
    │   └── HomeView.swift
    │
    └── Components/
        ├── MessageRow.swift
        ├── TypingIndicatorView.swift
        ├── GlassInputView.swift
        └── AnimatedBackgroundView.swift
```

---

## Component Details

### MLXService

Handles all MLX model operations:

- `loadModel(_ preset:)` — Loads model from HuggingFace via LLMModelFactory
- `unloadModel()` — Frees memory
- `generateStream(messages:)` — Returns AsyncStream<String> for streaming generation
- `cancelGeneration()` — Cancels in-progress generation
- Model presets: Llama 3.2 (1B/3B), Phi 3.5/4, Qwen 2.5 3B, Gemma 2 2B

### ChatManager

Central coordinator:

- `conversations: [Conversation]` — All conversations
- `activeConversationId: UUID?` — Currently selected (nil = home view)
- `isGenerating: Bool` — Whether generation is in progress
- `sendMessage(_ text:)` — Adds user message, streams assistant response
- `cancelGeneration()` — Stops current generation
- `createConversation()`, `selectConversation()`, `deleteConversation()`, `goHome()`

### ChatViewModel

Thin UI layer:

- `inputText: String` — Current text field content
- `messages: [Message]` — From active conversation
- `isGenerating: Bool` — From ChatManager
- `sendMessage()`, `stopGeneration()`, `newConversation()` — Delegate to ChatManager

### Views

- **ContentView** — Routes between HomeView and ChatView based on activeConversationId
- **HomeView** — List of conversations, new chat button, swipe-to-delete
- **ChatView** — NavigationStack with toolbar (home button, model menu, new chat), contains ChatConversationView
- **ChatConversationView** — ScrollView with messages, typing indicator, floating input bar, scroll-to-bottom button
- **MessageRow** — Single message: gradient bubble for user, plain text for assistant
- **TypingIndicatorView** — Animated dots using TimelineView + sine wave
- **GlassInputView** — TextField + send/stop button with Liquid Glass effect
- **AnimatedBackgroundView** — Floating blurred gradient circles

---

## Usage Notes for AI Agents

When continuing development:

1. **To add a new feature to chat**, modify ChatManager first, then expose through ChatViewModel, then update views.

2. **To add persistence**, implement Codable on Message/Conversation, save ChatManager.conversations to UserDefaults or files.

3. **To add a new model preset**, add case to `MLXService.ModelPreset` and update `allCases`.

4. **Views are dumb** — They receive data and closures, they don't import or know about ChatManager/ChatViewModel directly (except ChatView which creates the ViewModel).

5. **Focus state for keyboard** — GlassInputView expects `@FocusState.Binding` to dismiss keyboard on send.

6. **Streaming works via AsyncStream** — MLXService yields full text so far, ChatManager extracts incremental tokens by tracking previous length.
