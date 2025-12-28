# Tool Calling System Implementation Guide

This document outlines the implementation plan for adding tool/function calling capabilities to Iris, enabling the LLM to search the web and use information agentically.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Tool Protocol](#tool-protocol)
3. [Tool Registry](#tool-registry)
4. [Tool Call Parser](#tool-call-parser)
5. [Data Models](#data-models)
6. [Web Search Tool](#web-search-tool)
7. [Agentic Generation Loop](#agentic-generation-loop)
8. [System Prompt](#system-prompt)
9. [UI Components](#ui-components)
10. [File Organization](#file-organization)
11. [Implementation Checklist](#implementation-checklist)

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────────┐
│                           Agentic Tool Loop                                │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  User Message                                                              │
│       │                                                                    │
│       ▼                                                                    │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────┐                │
│  │   MLX LLM   │────▶│ Tool Parser  │────▶│ Tool Found? │                │
│  │  Generate   │     │ <tool_use>   │     └──────┬──────┘                │
│  └─────────────┘     └──────────────┘            │                        │
│       ▲                                     Yes  │  No                    │
│       │                                    ┌─────┴─────┐                  │
│       │                                    ▼           ▼                  │
│       │                            ┌─────────────┐  ┌──────────┐         │
│       │                            │  Execute    │  │  Done!   │         │
│       │                            │   Tool      │  │ Display  │         │
│       │                            └──────┬──────┘  └──────────┘         │
│       │                                   │                               │
│       │                                   ▼                               │
│       │                            ┌─────────────┐                        │
│       └────────────────────────────│ Add Result  │                        │
│            (Continue generating)   │ to Messages │                        │
│                                    └─────────────┘                        │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. User sends a message
2. LLM generates response, may include `<tool_use>` XML tags
3. Parser detects tool calls in streaming output
4. Tool is executed (e.g., web search)
5. Result is added to conversation as a tool message
6. LLM continues generating with tool result context
7. Loop repeats until no more tool calls (max 5 iterations)
8. Final response displayed with collapsible tool blocks + citations

---

## Tool Protocol

The core protocol that all tools implement:

```swift
// Iris/Tools/ToolProtocol.swift

import Foundation
import SwiftUI

/// Protocol defining a tool that can be invoked by the LLM
protocol Tool: Identifiable, Sendable {
    /// Unique identifier used in <tool_use name="...">
    var id: String { get }

    /// Human-readable name for UI
    var name: String { get }

    /// Description for the LLM to understand when to use this tool
    var description: String { get }

    /// SF Symbol name for UI
    var iconName: String { get }

    /// Accent color for UI theming
    var accentColor: Color { get }

    /// JSON-like schema of parameters
    var parametersSchema: ToolParametersSchema { get }

    /// Execute the tool with given arguments
    @MainActor
    func execute(arguments: [String: Any]) async throws -> ToolResult
}

// MARK: - Parameter Schema

struct ToolParametersSchema: Codable, Sendable {
    let properties: [String: ParameterDefinition]
    let required: [String]

    struct ParameterDefinition: Codable, Sendable {
        let type: String          // "string", "number", "boolean", "array"
        let description: String
        let enumValues: [String]? // Optional enum constraint

        enum CodingKeys: String, CodingKey {
            case type, description
            case enumValues = "enum"
        }
    }

    /// Generate XML example for system prompt
    func xmlExample(toolId: String) -> String {
        let params = properties.map { name, _ in
            "  <\(name)>value</\(name)>"
        }.joined(separator: "\n")

        return """
        <tool_use name="\(toolId)">
        \(params)
        </tool_use>
        """
    }
}

// MARK: - Tool Result

struct ToolResult: Sendable {
    let content: String          // Markdown-formatted result
    let citations: [Citation]    // Source links
    let isError: Bool

    static func success(_ content: String, citations: [Citation] = []) -> ToolResult {
        ToolResult(content: content, citations: citations, isError: false)
    }

    static func error(_ message: String) -> ToolResult {
        ToolResult(content: "Error: \(message)", citations: [], isError: true)
    }
}

// MARK: - Citation

struct Citation: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let title: String
    let url: URL
    let snippet: String?

    init(title: String, url: URL, snippet: String? = nil) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.snippet = snippet
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: Citation, rhs: Citation) -> Bool {
        lhs.url == rhs.url
    }
}
```

---

## Tool Registry

Singleton that manages available tools:

```swift
// Iris/Tools/ToolRegistry.swift

import Foundation
import Observation

@Observable
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()

    private(set) var tools: [String: any Tool] = [:]

    private init() {
        // Register default tools
        register(WebSearchTool())
        // Future: register(CalculatorTool())
        // Future: register(WeatherTool())
    }

    // MARK: - Tool Management

    func register(_ tool: any Tool) {
        tools[tool.id] = tool
    }

    func unregister(_ toolId: String) {
        tools.removeValue(forKey: toolId)
    }

    func tool(for id: String) -> (any Tool)? {
        tools[id]
    }

    var allTools: [any Tool] {
        Array(tools.values)
    }

    var enabledTools: [any Tool] {
        // Future: filter by user preferences
        allTools
    }

    // MARK: - System Prompt Generation

    /// Generate tool descriptions for system prompt
    func systemPromptSection() -> String {
        guard !enabledTools.isEmpty else {
            return ""
        }

        let toolDescriptions = enabledTools.map { tool in
            let paramList = tool.parametersSchema.properties.map { name, def in
                "    - `\(name)` (\(def.type)): \(def.description)"
            }.joined(separator: "\n")

            return """
            ### \(tool.name)
            **ID:** `\(tool.id)`
            **Description:** \(tool.description)
            **Parameters:**
            \(paramList)

            **Usage:**
            ```xml
            \(tool.parametersSchema.xmlExample(toolId: tool.id))
            ```
            """
        }.joined(separator: "\n\n")

        return """
        ## Available Tools

        You have access to the following tools. Use them when you need current information or capabilities beyond your training data.

        \(toolDescriptions)

        ## Tool Usage Guidelines

        1. **When to use tools:** Use tools when you need up-to-date information, need to verify facts, or the user asks about current events.
        2. **Format:** Output tool calls in the exact XML format shown above.
        3. **Wait for results:** After outputting a tool call, stop and wait for the result before continuing.
        4. **Cite sources:** When using search results, cite your sources inline like [Title](url).
        5. **Multiple tools:** You can use multiple tools in sequence if needed.

        """
    }
}
```

---

## Tool Call Parser

Parses `<tool_use>` XML tags from LLM output:

```swift
// Iris/Tools/ToolCallParser.swift

import Foundation

/// Parses tool calls from streaming LLM output
struct ToolCallParser {

    // MARK: - Types

    struct ParsedToolCall: Sendable {
        let toolId: String
        let arguments: [String: String]
        let rawXML: String
        let range: Range<String.Index>
    }

    struct ParseResult: Sendable {
        let textBeforeToolCall: String
        let toolCall: ParsedToolCall?
        let textAfterToolCall: String
        let isToolCallStreaming: Bool  // True if <tool_use> started but not closed
    }

    // MARK: - Parsing

    /// Parse text for tool calls
    /// Returns the first tool call found (if any) with surrounding text
    static func parse(_ text: String) -> ParseResult {
        // Pattern: <tool_use name="...">...</tool_use>
        let pattern = #"<tool_use\s+name="([^"]+)">(.*?)</tool_use>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let toolIdRange = Range(match.range(at: 1), in: text),
              let contentRange = Range(match.range(at: 2), in: text),
              let fullRange = Range(match.range, in: text) else {

            // Check for incomplete/streaming tool call
            if let startIndex = text.range(of: "<tool_use")?.lowerBound {
                // Tool call started but not completed
                return ParseResult(
                    textBeforeToolCall: String(text[..<startIndex]),
                    toolCall: nil,
                    textAfterToolCall: "",
                    isToolCallStreaming: true
                )
            }

            // No tool call found
            return ParseResult(
                textBeforeToolCall: text,
                toolCall: nil,
                textAfterToolCall: "",
                isToolCallStreaming: false
            )
        }

        let toolId = String(text[toolIdRange])
        let innerContent = String(text[contentRange])
        let arguments = parseArguments(innerContent)

        return ParseResult(
            textBeforeToolCall: String(text[..<fullRange.lowerBound]),
            toolCall: ParsedToolCall(
                toolId: toolId,
                arguments: arguments,
                rawXML: String(text[fullRange]),
                range: fullRange
            ),
            textAfterToolCall: String(text[fullRange.upperBound...]),
            isToolCallStreaming: false
        )
    }

    /// Parse all tool calls in text (for multiple tool invocations)
    static func parseAll(_ text: String) -> [ParsedToolCall] {
        let pattern = #"<tool_use\s+name="([^"]+)">(.*?)</tool_use>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        return matches.compactMap { match -> ParsedToolCall? in
            guard let toolIdRange = Range(match.range(at: 1), in: text),
                  let contentRange = Range(match.range(at: 2), in: text),
                  let fullRange = Range(match.range, in: text) else {
                return nil
            }

            return ParsedToolCall(
                toolId: String(text[toolIdRange]),
                arguments: parseArguments(String(text[contentRange])),
                rawXML: String(text[fullRange]),
                range: fullRange
            )
        }
    }

    // MARK: - Argument Parsing

    /// Parse XML arguments from tool call body
    /// Supports: <param_name>value</param_name>
    private static func parseArguments(_ content: String) -> [String: String] {
        var arguments: [String: String] = [:]

        let pattern = #"<(\w+)>(.*?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return arguments
        }

        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))

        for match in matches {
            if let nameRange = Range(match.range(at: 1), in: content),
               let valueRange = Range(match.range(at: 2), in: content) {
                let name = String(content[nameRange])
                let value = String(content[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                arguments[name] = value
            }
        }

        return arguments
    }
}
```

---

## Data Models

### ToolCallData

```swift
// Iris/Models/ToolCallData.swift

import Foundation

/// Represents a tool invocation and its result
struct ToolCallData: Codable, Identifiable, Sendable {
    let id: UUID
    let toolId: String
    let arguments: [String: String]
    var status: ToolCallStatus
    var result: String?
    var citations: [Citation]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        toolId: String,
        arguments: [String: String] = [:],
        status: ToolCallStatus = .executing,
        result: String? = nil,
        citations: [Citation] = []
    ) {
        self.id = id
        self.toolId = toolId
        self.arguments = arguments
        self.status = status
        self.result = result
        self.citations = citations
        self.timestamp = Date()
    }

    /// Create a completed tool call
    static func completed(
        toolId: String,
        arguments: [String: String],
        result: ToolResult
    ) -> ToolCallData {
        ToolCallData(
            toolId: toolId,
            arguments: arguments,
            status: result.isError ? .failed : .completed,
            result: result.content,
            citations: result.citations
        )
    }
}

enum ToolCallStatus: String, Codable, Sendable {
    case executing   // Tool is currently running
    case completed   // Tool finished successfully
    case failed      // Tool encountered an error
}
```

### Updated Message Model

```swift
// Iris/Models/Message.swift (MODIFICATIONS)

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case tool       // NEW: For tool results
}

struct Message: Codable, Identifiable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let attachments: [MessageAttachment]
    let timestamp: Date
    let metrics: GenerationMetrics?

    // NEW: Tool-related fields
    let toolCalls: [ToolCallData]?   // For assistant messages that invoke tools
    let toolCallId: UUID?             // For tool messages, links to the invoking call

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        attachments: [MessageAttachment] = [],
        timestamp: Date = Date(),
        metrics: GenerationMetrics? = nil,
        toolCalls: [ToolCallData]? = nil,
        toolCallId: UUID? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.timestamp = timestamp
        self.metrics = metrics
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}
```

---

## Web Search Tool

### Search Service Protocol

```swift
// Iris/Tools/SearchTool/WebSearchService.swift

import Foundation

/// Protocol for web search providers
protocol WebSearchService: Sendable {
    func search(query: String, maxResults: Int) async throws -> [SearchResult]
}

extension WebSearchService {
    func search(query: String) async throws -> [SearchResult] {
        try await search(query: query, maxResults: 5)
    }
}

struct SearchResult: Sendable {
    let title: String
    let url: URL
    let snippet: String
}

enum SearchError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case parseError
    case noResults
    case rateLimited
    case apiKeyMissing

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid search URL"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .parseError: return "Failed to parse search results"
        case .noResults: return "No results found"
        case .rateLimited: return "Search rate limit exceeded"
        case .apiKeyMissing: return "API key not configured"
        }
    }
}
```

### DuckDuckGo Service (Free)

```swift
// Iris/Tools/SearchTool/DuckDuckGoService.swift

import Foundation

/// DuckDuckGo Instant Answer API
/// Free, no API key required
/// Note: Returns limited results (instant answers, not full web search)
final class DuckDuckGoService: WebSearchService, Sendable {

    private let baseURL = "https://api.duckduckgo.com/"

    func search(query: String, maxResults: Int = 5) async throws -> [SearchResult] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1")
        ]

        guard let url = components.url else {
            throw SearchError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SearchError.networkError(URLError(.badServerResponse))
        }

        let ddgResponse = try JSONDecoder().decode(DDGResponse.self, from: data)

        var results: [SearchResult] = []

        // Add abstract if available (main answer)
        if !ddgResponse.abstractText.isEmpty,
           let abstractURL = URL(string: ddgResponse.abstractURL) {
            results.append(SearchResult(
                title: ddgResponse.heading.isEmpty ? "Summary" : ddgResponse.heading,
                url: abstractURL,
                snippet: ddgResponse.abstractText
            ))
        }

        // Add related topics
        for topic in ddgResponse.relatedTopics.prefix(maxResults - results.count) {
            guard let text = topic.text,
                  let urlString = topic.firstURL,
                  let url = URL(string: urlString) else {
                continue
            }

            results.append(SearchResult(
                title: extractTitle(from: text),
                url: url,
                snippet: text
            ))
        }

        // Add results from related topics' topics (nested)
        for topic in ddgResponse.relatedTopics {
            if let topics = topic.topics {
                for nested in topics.prefix(maxResults - results.count) {
                    guard let text = nested.text,
                          let urlString = nested.firstURL,
                          let url = URL(string: urlString) else {
                        continue
                    }

                    results.append(SearchResult(
                        title: extractTitle(from: text),
                        url: url,
                        snippet: text
                    ))
                }
            }
        }

        if results.isEmpty {
            throw SearchError.noResults
        }

        return Array(results.prefix(maxResults))
    }

    private func extractTitle(from text: String) -> String {
        // DDG format is often: "Title - Description"
        if let dashIndex = text.firstIndex(of: "-") {
            let title = String(text[..<dashIndex]).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty {
                return title
            }
        }
        // Fallback: first 60 characters
        return String(text.prefix(60)) + (text.count > 60 ? "..." : "")
    }
}

// MARK: - DDG Response Models

private struct DDGResponse: Codable {
    let abstractText: String
    let abstractURL: String
    let heading: String
    let relatedTopics: [DDGTopic]

    enum CodingKeys: String, CodingKey {
        case abstractText = "AbstractText"
        case abstractURL = "AbstractURL"
        case heading = "Heading"
        case relatedTopics = "RelatedTopics"
    }
}

private struct DDGTopic: Codable {
    let text: String?
    let firstURL: String?
    let topics: [DDGTopic]?  // Nested topics

    enum CodingKeys: String, CodingKey {
        case text = "Text"
        case firstURL = "FirstURL"
        case topics = "Topics"
    }
}
```

### Tavily Service (Premium)

```swift
// Iris/Tools/SearchTool/TavilyService.swift

import Foundation

/// Tavily Search API - optimized for LLM applications
/// Requires API key: https://tavily.com
/// Free tier: 1000 searches/month
final class TavilyService: WebSearchService, Sendable {

    private let apiKey: String
    private let baseURL = "https://api.tavily.com/search"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Create from stored API key
    static func fromStoredKey() -> TavilyService? {
        guard let apiKey = UserDefaults.standard.string(forKey: "tavily_api_key"),
              !apiKey.isEmpty else {
            return nil
        }
        return TavilyService(apiKey: apiKey)
    }

    func search(query: String, maxResults: Int = 5) async throws -> [SearchResult] {
        guard !apiKey.isEmpty else {
            throw SearchError.apiKeyMissing
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "search_depth": "basic",  // or "advanced" for deeper search
            "max_results": maxResults,
            "include_answer": false,
            "include_raw_content": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 429 {
            throw SearchError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw SearchError.networkError(URLError(.badServerResponse))
        }

        let tavilyResponse = try JSONDecoder().decode(TavilyResponse.self, from: data)

        if tavilyResponse.results.isEmpty {
            throw SearchError.noResults
        }

        return tavilyResponse.results.compactMap { result -> SearchResult? in
            guard let url = URL(string: result.url) else { return nil }
            return SearchResult(
                title: result.title,
                url: url,
                snippet: result.content
            )
        }
    }
}

// MARK: - Tavily Response Models

private struct TavilyResponse: Codable {
    let results: [TavilyResult]
}

private struct TavilyResult: Codable {
    let title: String
    let url: String
    let content: String
    let score: Double?
}
```

### Web Search Tool Implementation

```swift
// Iris/Tools/SearchTool/WebSearchTool.swift

import Foundation
import SwiftUI

/// Web search tool for the LLM
struct WebSearchTool: Tool {
    let id = "web_search"
    let name = "Web Search"
    let description = "Search the web for current information, news, facts, or any topic. Use this when you need up-to-date information not in your training data."
    let iconName = "magnifyingglass.circle.fill"
    let accentColor = Color.blue

    var parametersSchema: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "query": .init(
                    type: "string",
                    description: "The search query to look up on the web",
                    enumValues: nil
                )
            ],
            required: ["query"]
        )
    }

    // Use Tavily if API key is set, otherwise fall back to DuckDuckGo
    private var searchService: WebSearchService {
        TavilyService.fromStoredKey() ?? DuckDuckGoService()
    }

    @MainActor
    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return .error("Missing or empty 'query' parameter")
        }

        do {
            let results = try await searchService.search(query: query, maxResults: 5)

            if results.isEmpty {
                return .success("No results found for: \"\(query)\"")
            }

            // Format results as markdown
            let formattedResults = results.enumerated().map { index, result in
                """
                **\(index + 1). [\(result.title)](\(result.url.absoluteString))**
                \(result.snippet)
                """
            }.joined(separator: "\n\n")

            let citations = results.map { result in
                Citation(title: result.title, url: result.url, snippet: result.snippet)
            }

            return .success(
                "Search results for \"\(query)\":\n\n\(formattedResults)",
                citations: citations
            )

        } catch let error as SearchError {
            return .error(error.localizedDescription)
        } catch {
            return .error("Search failed: \(error.localizedDescription)")
        }
    }
}
```

---

## Agentic Generation Loop

Modified `ChatManager.performGeneration()`:

```swift
// Iris/Managers/ChatManager.swift (MODIFICATIONS)

private func performGeneration(
    conversationId: UUID,
    assistantMessageId: UUID
) async {
    defer {
        if generatingConversationID == conversationId {
            isGenerating = false
            generatingConversationID = nil
            generationTask = nil

            // Save final state
            if let conversation = conversations.first(where: { $0.id == conversationId }) {
                saveConversation(conversation)
            }
        }
    }

    guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }) else {
        return
    }

    var iterationCount = 0
    let maxIterations = 5  // Prevent infinite tool loops
    var currentAssistantMessageId = assistantMessageId

    // Agentic loop: generate -> check for tools -> execute -> repeat
    while iterationCount < maxIterations {
        iterationCount += 1

        // Get messages excluding current placeholder
        let messages = conversations[conversationIndex].messages.filter {
            $0.id != currentAssistantMessageId
        }

        var fullResponse = ""
        var previousLength = 0

        // Stream generation
        for await fullText in mlxService.generateStream(
            messages: messages,
            config: generationConfig(withTools: true)
        ) {
            // Check for cancellation
            if Task.isCancelled { return }
            guard generatingConversationID == conversationId else { return }

            // Extract new tokens
            let newText = String(fullText.dropFirst(previousLength))
            previousLength = fullText.count
            fullResponse += newText

            // Update UI with streaming content
            updateAssistantMessage(
                conversationId: conversationId,
                messageId: currentAssistantMessageId,
                content: fullResponse
            )
        }

        // Parse for tool calls
        let parseResult = ToolCallParser.parse(fullResponse)

        // If no tool call, we're done
        guard let toolCall = parseResult.toolCall else {
            // Finalize message with metrics
            let metrics = mlxService.lastGenerationMetrics
            updateAssistantMessage(
                conversationId: conversationId,
                messageId: currentAssistantMessageId,
                content: fullResponse,
                metrics: metrics
            )
            break
        }

        // Look up the tool
        guard let tool = ToolRegistry.shared.tool(for: toolCall.toolId) else {
            // Unknown tool - add error and stop
            let errorMessage = fullResponse + "\n\n[Error: Unknown tool '\(toolCall.toolId)']"
            updateAssistantMessage(
                conversationId: conversationId,
                messageId: currentAssistantMessageId,
                content: errorMessage
            )
            break
        }

        // Update message to show tool is executing
        let executingToolCall = ToolCallData(
            toolId: toolCall.toolId,
            arguments: toolCall.arguments,
            status: .executing
        )

        updateAssistantMessage(
            conversationId: conversationId,
            messageId: currentAssistantMessageId,
            content: parseResult.textBeforeToolCall,
            toolCalls: [executingToolCall]
        )

        // Execute the tool
        let result: ToolResult
        do {
            result = try await tool.execute(arguments: toolCall.arguments)
        } catch {
            result = .error("Tool execution failed: \(error.localizedDescription)")
        }

        // Update message with completed tool call
        let completedToolCall = ToolCallData.completed(
            toolId: toolCall.toolId,
            arguments: toolCall.arguments,
            result: result
        )

        updateAssistantMessage(
            conversationId: conversationId,
            messageId: currentAssistantMessageId,
            content: parseResult.textBeforeToolCall,
            toolCalls: [completedToolCall]
        )

        // Add tool result as new message
        let toolResultMessage = Message(
            role: .tool,
            content: result.content,
            toolCallId: currentAssistantMessageId
        )
        appendMessage(toolResultMessage, to: conversationId)

        // Create new assistant message for continuation
        let continuationMessage = Message(role: .assistant, content: "")
        appendMessage(continuationMessage, to: conversationId)
        currentAssistantMessageId = continuationMessage.id

        // Save progress
        if let conversation = conversations.first(where: { $0.id == conversationId }) {
            saveConversation(conversation)
        }

        // Continue loop to generate response with tool result
    }

    // Handle max iterations reached
    if iterationCount >= maxIterations {
        NSLog("[ChatManager] Max tool iterations reached")
    }
}

// MARK: - Helper Methods

private func generationConfig(withTools: Bool) -> MLXService.GenerationConfig {
    var config = MLXService.GenerationConfig.default

    if withTools {
        let toolPrompt = ToolRegistry.shared.systemPromptSection()
        config.systemPrompt = AppConfig.systemPrompt + "\n\n" + toolPrompt
    }

    return config
}

private func updateAssistantMessage(
    conversationId: UUID,
    messageId: UUID,
    content: String,
    metrics: GenerationMetrics? = nil,
    toolCalls: [ToolCallData]? = nil
) {
    guard let convIndex = conversations.firstIndex(where: { $0.id == conversationId }),
          let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageId }) else {
        return
    }

    let existingMessage = conversations[convIndex].messages[msgIndex]

    conversations[convIndex].messages[msgIndex] = Message(
        id: existingMessage.id,
        role: .assistant,
        content: content,
        attachments: existingMessage.attachments,
        timestamp: existingMessage.timestamp,
        metrics: metrics ?? existingMessage.metrics,
        toolCalls: toolCalls ?? existingMessage.toolCalls,
        toolCallId: existingMessage.toolCallId
    )
}

private func appendMessage(_ message: Message, to conversationId: UUID) {
    guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else {
        return
    }
    conversations[index].messages.append(message)
    conversations[index].updatedAt = Date()
}
```

---

## System Prompt

Update `AppConfig.swift`:

```swift
// Iris/AppConfig.swift (MODIFICATIONS)

enum AppConfig {
    /// Base system prompt (without tools)
    static let baseSystemPrompt = """
    You are Iris, a helpful and knowledgeable AI assistant. You provide clear, accurate, and thoughtful responses.

    ## Response Guidelines
    - Be concise but thorough
    - Use markdown formatting for code, lists, and emphasis
    - When reasoning through complex problems, wrap your thinking in <think></think> tags
    - Cite sources when referencing specific information
    """

    /// System prompt with tool capabilities (used by ChatManager)
    static var systemPrompt: String {
        baseSystemPrompt
        // Tool section is appended dynamically by ChatManager
    }

    /// Full system prompt including tools
    static func systemPromptWithTools() -> String {
        let toolSection = ToolRegistry.shared.systemPromptSection()

        if toolSection.isEmpty {
            return baseSystemPrompt
        }

        return baseSystemPrompt + "\n\n" + toolSection
    }
}
```

---

## UI Components

### ToolUseView

```swift
// Iris/Chat/Components/ToolUseView.swift

import SwiftUI

/// Displays a collapsible tool invocation with result
struct ToolUseView: View {
    let toolCall: ToolCallData

    @State private var isExpanded = false

    private var tool: (any Tool)? {
        ToolRegistry.shared.tool(for: toolCall.toolId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header button
            headerButton

            // Expandable content
            if isExpanded {
                expandedContent
            }

            // Citations (always visible when present)
            if !toolCall.citations.isEmpty {
                citationsSection
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header

    private var headerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                // Icon
                Image(systemName: tool?.iconName ?? "wrench.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 20)

                // Status text
                statusText

                Spacer()

                // Loading indicator or chevron
                if toolCall.status == .executing {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusText: some View {
        switch toolCall.status {
        case .executing:
            ShimmerText(toolCall.toolId == "web_search" ? "Searching the web..." : "Running \(tool?.name ?? "tool")...")
                .font(.subheadline)
        case .completed:
            Text(toolCall.toolId == "web_search" ? "Searched the web" : "Used \(tool?.name ?? "tool")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .failed:
            Text("Failed")
                .font(.subheadline)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        if let result = toolCall.result {
            VStack(alignment: .leading, spacing: 8) {
                // Query (if web search)
                if let query = toolCall.arguments["query"] {
                    HStack(spacing: 6) {
                        Text("Query:")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(query)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Result content
                ScrollView(.vertical, showsIndicators: true) {
                    Text(result)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(0.05))
            )
        }
    }

    // MARK: - Citations

    private var citationsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(toolCall.citations.prefix(5)) { citation in
                    CitationChip(citation: citation)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var accentColor: Color {
        tool?.accentColor ?? .gray
    }
}
```

### CitationsFooter

```swift
// Iris/Chat/Components/CitationsFooter.swift

import SwiftUI

/// Horizontal list of source citations
struct CitationsFooter: View {
    let citations: [Citation]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.caption2)
                Text("Sources")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(uniqueCitations) { citation in
                        CitationChip(citation: citation)
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    private var uniqueCitations: [Citation] {
        var seen = Set<URL>()
        return citations.filter { citation in
            if seen.contains(citation.url) {
                return false
            }
            seen.insert(citation.url)
            return true
        }
    }
}

/// Single citation chip
struct CitationChip: View {
    let citation: Citation

    var body: some View {
        Link(destination: citation.url) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))

                Text(citation.title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.1))
            )
            .foregroundStyle(.blue)
        }
    }
}
```

### Updated MessageRow

```swift
// Iris/Chat/Components/MessageRow.swift (MODIFICATIONS)

// In assistant message rendering, add tool handling:

private func assistantMessageContent(_ message: Message) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        // Parse content for thinking blocks and tool calls
        let segments = parseContent(message.content)

        ForEach(segments) { segment in
            switch segment.type {
            case .text:
                if !segment.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(markdownContent(segment.content))
                        .font(.body)
                        .textSelection(.enabled)
                }

            case .thinking(let isStreaming):
                ThinkingView(
                    content: segment.content,
                    isStreaming: isStreaming
                )
            }
        }

        // Tool calls (if any)
        if let toolCalls = message.toolCalls {
            ForEach(toolCalls) { toolCall in
                ToolUseView(toolCall: toolCall)
            }
        }

        // Citations footer (aggregate from all tool calls)
        let allCitations = message.toolCalls?.flatMap { $0.citations } ?? []
        if !allCitations.isEmpty {
            CitationsFooter(citations: allCitations)
        }
    }
}

// MARK: - Content Parsing

private enum SegmentType {
    case text
    case thinking(isStreaming: Bool)
}

private struct ContentSegment: Identifiable {
    let id = UUID()
    let type: SegmentType
    let content: String
}

private func parseContent(_ text: String) -> [ContentSegment] {
    // Use existing ThinkingParser and extend for tool parsing
    let thinkingSegments = ThinkingParser.parse(text)

    return thinkingSegments.map { segment in
        ContentSegment(
            type: segment.isThinking ? .thinking(isStreaming: segment.isStreaming) : .text,
            content: segment.content
        )
    }
}
```

---

## File Organization

```
Iris/
├── Tools/
│   ├── ToolProtocol.swift           # Protocol, ToolResult, Citation
│   ├── ToolRegistry.swift           # Tool management singleton
│   ├── ToolCallParser.swift         # XML parsing
│   └── SearchTool/
│       ├── WebSearchTool.swift      # Search tool implementation
│       ├── WebSearchService.swift   # Protocol for search providers
│       ├── DuckDuckGoService.swift  # Free DDG API
│       └── TavilyService.swift      # Premium Tavily API
│
├── Models/
│   ├── Message.swift                # MODIFY: Add tool fields
│   ├── Conversation.swift           # (no changes)
│   └── ToolCallData.swift           # NEW: Tool call model
│
├── Managers/
│   └── ChatManager.swift            # MODIFY: Agentic loop
│
├── Chat/
│   └── Components/
│       ├── MessageRow.swift         # MODIFY: Render tools
│       ├── ThinkingView.swift       # (no changes)
│       ├── ToolUseView.swift        # NEW: Tool UI
│       └── CitationsFooter.swift    # NEW: Citations UI
│
└── AppConfig.swift                  # MODIFY: Tool prompts
```

---

## Implementation Checklist

### Phase 1: Core Infrastructure
- [ ] Create `Tools/` directory
- [ ] Implement `ToolProtocol.swift`
- [ ] Implement `ToolRegistry.swift`
- [ ] Implement `ToolCallParser.swift`
- [ ] Add `ToolCallData.swift` model
- [ ] Update `Message.swift` with tool fields

### Phase 2: Web Search Tool
- [ ] Create `SearchTool/` directory
- [ ] Implement `WebSearchService.swift` protocol
- [ ] Implement `DuckDuckGoService.swift`
- [ ] Implement `TavilyService.swift`
- [ ] Implement `WebSearchTool.swift`
- [ ] Register tool in `ToolRegistry`

### Phase 3: Agentic Loop
- [ ] Modify `ChatManager.performGeneration()` for multi-turn
- [ ] Add tool detection in generation loop
- [ ] Implement tool execution handling
- [ ] Add tool result message creation
- [ ] Add continuation message for follow-up
- [ ] Add max iteration limit (5)

### Phase 4: System Prompt
- [ ] Update `AppConfig.swift` with tool prompt generation
- [ ] Add `systemPromptWithTools()` method
- [ ] Test prompt with different tools registered

### Phase 5: UI Components
- [ ] Implement `ToolUseView.swift`
- [ ] Implement `CitationsFooter.swift`
- [ ] Update `MessageRow.swift` to render tool calls
- [ ] Add shimmer animation for executing state
- [ ] Test collapsible behavior

### Phase 6: Testing & Polish
- [ ] Test single tool call flow
- [ ] Test multiple sequential tool calls
- [ ] Test tool error handling
- [ ] Test conversation persistence with tools
- [ ] Test UI during streaming
- [ ] Test cancellation during tool execution

---

## Future Enhancements

Once the tool infrastructure is in place, adding new tools is simple:

```swift
// Example: Calculator tool
struct CalculatorTool: Tool {
    let id = "calculator"
    let name = "Calculator"
    let description = "Perform mathematical calculations"
    let iconName = "function"
    let accentColor = Color.orange

    var parametersSchema: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "expression": .init(type: "string", description: "Math expression to evaluate", enumValues: nil)
            ],
            required: ["expression"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        // Implementation
    }
}

// Register it
ToolRegistry.shared.register(CalculatorTool())
```

Potential future tools:
- **Calculator** - Math expressions
- **Weather** - Current weather lookup
- **Wikipedia** - Encyclopedia lookups
- **URL Fetch** - Read webpage content
- **Code Execution** - Run code snippets (sandboxed)
- **Image Generation** - Generate images (via API)
