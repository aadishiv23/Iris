//
//  DebugLogView.swift
//  Iris
//
//  Created by Claude on 12/28/25.
//

import SwiftUI

/// Debug log viewer showing all logs and per-conversation logs
struct DebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var minLevel: LoggingService.LogLevel = .debug
    @State private var searchText = ""
    @State private var showExportSheet = false
    @State private var exportText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("View", selection: $selectedTab) {
                    Text("All Logs").tag(0)
                    Text("Files").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                // Filter bar
                HStack {
                    Menu {
                        ForEach(LoggingService.LogLevel.allCases, id: \.self) { level in
                            Button {
                                minLevel = level
                            } label: {
                                HStack {
                                    Text("\(level.emoji) \(level.rawValue)")
                                    if minLevel == level {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(minLevel.emoji)
                            Text(minLevel.rawValue)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }

                    Spacer()

                    Text("\(filteredLogs.count) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                if selectedTab == 0 {
                    logListView
                } else {
                    fileListView
                }
            }
            .navigationTitle("Debug Logs")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            exportText = Logger.exportLogs()
                            showExportSheet = true
                        } label: {
                            Label("Export All Logs", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            Logger.clearLogs()
                        } label: {
                            Label("Clear Logs", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                ExportLogSheet(content: exportText)
            }
            .searchable(text: $searchText, prompt: "Search logs...")
        }
    }

    private var filteredLogs: [LoggingService.LogEntry] {
        let logs = Logger.recentLogs(minLevel: minLevel, limit: 500)

        if searchText.isEmpty {
            return logs
        }

        return logs.filter { entry in
            entry.message.localizedCaseInsensitiveContains(searchText) ||
            entry.category.localizedCaseInsensitiveContains(searchText) ||
            entry.function.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var logListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if filteredLogs.isEmpty {
                    emptyStateView
                } else {
                    ForEach(filteredLogs) { entry in
                        LogEntryRow(entry: entry)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }

    private var fileListView: some View {
        List {
            let files = Logger.persistedLogFiles()

            if files.isEmpty {
                Text("No persisted log files")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(files, id: \.url) { file in
                    NavigationLink {
                        PersistedLogFileView(fileURL: file.url, fileName: file.name)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(file.name)
                                    .font(.subheadline)
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section {
                Text("Log files are stored in Documents/Logs/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("These persist across app restarts and crashes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)

            Text("No logs found")
                .foregroundStyle(.secondary)

            Text("Try adjusting the filter level")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LoggingService.LogEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(alignment: .top, spacing: 6) {
                Text(entry.level.emoji)
                    .font(.caption)

                Text(entry.formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)

                Text("[\(entry.category)]")
                    .font(.caption2)
                    .foregroundStyle(categoryColor(entry.category))
                    .fontWeight(.medium)

                Spacer()
            }

            // Message
            Text(entry.message)
                .font(.caption)
                .foregroundStyle(levelColor(entry.level))
                .lineLimit(isExpanded ? nil : 2)

            // Expandable details
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.shortFile):\(entry.line)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fontDesign(.monospaced)

                    Text(entry.function)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fontDesign(.monospaced)

                    if let metadata = entry.metadata, !metadata.isEmpty {
                        ForEach(Array(metadata.keys.sorted()), id: \.self) { key in
                            Text("\(key): \(metadata[key] ?? "")")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fontDesign(.monospaced)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(10)
        .background(levelBackground(entry.level))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private func levelColor(_ level: LoggingService.LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        case .fatal: return .red
        }
    }

    private func levelBackground(_ level: LoggingService.LogLevel) -> Color {
        switch level {
        case .debug: return .gray.opacity(0.1)
        case .info: return .blue.opacity(0.1)
        case .warning: return .orange.opacity(0.15)
        case .error: return .red.opacity(0.15)
        case .fatal: return .red.opacity(0.25)
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "MLX": return .purple
        case "Generation": return .green
        case "Chat": return .blue
        case "LoggingService": return .gray
        default: return .secondary
        }
    }
}

// MARK: - Export Sheet

struct ExportLogSheet: View {
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Log Export")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: content) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Conversation Log View

struct ConversationLogView: View {
    let conversationID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let logs = Logger.logs(for: conversationID)

                    if logs.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 40))
                                .foregroundStyle(.quaternary)

                            Text("No logs for this conversation")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(logs.reversed()) { entry in
                            LogEntryRow(entry: entry)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationTitle("Conversation Logs")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: Logger.exportLogs(for: conversationID)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Persisted Log File View

struct PersistedLogFileView: View {
    let fileURL: URL
    let fileName: String
    @State private var content: String = "Loading..."
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            Text(filteredContent)
                .font(.caption)
                .fontDesign(.monospaced)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .navigationTitle(fileName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: content) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search in file...")
        .task {
            loadContent()
        }
    }

    private var filteredContent: String {
        guard !searchText.isEmpty else { return content }

        let entries = content.components(separatedBy: "\n---\n")
        let filtered = entries.filter { $0.localizedCaseInsensitiveContains(searchText) }
        return filtered.joined(separator: "\n---\n")
    }

    private func loadContent() {
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            content = "Failed to load file: \(error.localizedDescription)"
        }
    }
}

#Preview {
    DebugLogView()
}
