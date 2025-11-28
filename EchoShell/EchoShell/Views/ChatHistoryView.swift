//
//  ChatHistoryView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  IDE-style chat interface for headless terminals
//

import SwiftUI

struct ChatHistoryView: View {
    let messages: [ChatMessage]
    let isAgentMode: Bool // true = current execution, false = full history
    var onPlayAudio: ((ChatMessage) -> Void)? = nil // Callback to play audio message
    var onPauseAudio: (() -> Void)? = nil // Callback to pause audio
    var onStopAudio: (() -> Void)? = nil // Callback to stop audio
    
    @State private var expandedToolMessages: Set<String> = []
    @State private var copiedMessageId: String? = nil
    @State private var playingMessageId: String? = nil
    @State private var pausedMessageId: String? = nil
    
    // Subscribe to playback finished events to reset playing state
    private let playbackFinishedPublisher = EventBus.shared.ttsPlaybackFinishedPublisher
    
    // Group messages by conversation turn (user + assistant responses)
    // Filter out system messages before grouping
    private var filteredMessages: [ChatMessage] {
        messages.filter { $0.type != .system }
    }
    
    private var groupedMessages: [[ChatMessage]] {
        var groups: [[ChatMessage]] = []
        var currentGroup: [ChatMessage] = []
        var lastMessageType: ChatMessage.MessageType? = nil
        
        for message in filteredMessages {
            // Start new group when:
            // 1. We see a user message (new conversation turn)
            // 2. Message type changes (e.g., assistant -> tool, tool -> assistant)
            let shouldStartNewGroup = message.type == .user || 
                                     (lastMessageType != nil && message.type != lastMessageType)
            
            if shouldStartNewGroup && !currentGroup.isEmpty {
                groups.append(currentGroup)
                currentGroup = [message]
            } else {
                // Merge consecutive messages of same type into one block
                currentGroup.append(message)
            }
            
            lastMessageType = message.type
        }
        
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }
        
        return groups
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(groupedMessages.enumerated()), id: \.offset) { groupIndex, group in
                        VStack(alignment: .leading, spacing: 8) {
                            // No dividers - cleaner look
                            
                            // If group has multiple messages of same type, merge them
                            if group.count > 1 && group.allSatisfy({ $0.type == group.first?.type }) {
                                // Merge multiple messages into one bubble
                                let mergedContent = group.map { $0.content }.joined(separator: "\n\n")
                                let firstMessage = group.first!
                                let mergedMessage = ChatMessage(
                                    id: firstMessage.id,
                                    timestamp: firstMessage.timestamp,
                                    type: firstMessage.type,
                                    content: mergedContent,
                                    metadata: firstMessage.metadata
                                )
                                
                                ChatBubbleView(
                                    message: mergedMessage,
                                    isExpanded: expandedToolMessages.contains(firstMessage.id),
                                    isCopied: copiedMessageId == firstMessage.id,
                                    isPlaying: playingMessageId == firstMessage.id,
                                    isPaused: pausedMessageId == firstMessage.id,
                                    onToggleExpand: {
                                        if expandedToolMessages.contains(firstMessage.id) {
                                            expandedToolMessages.remove(firstMessage.id)
                                        } else {
                                            expandedToolMessages.insert(firstMessage.id)
                                        }
                                    },
                                    onCopy: {
                                        UIPasteboard.general.string = mergedContent
                                        copiedMessageId = firstMessage.id
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            if copiedMessageId == firstMessage.id {
                                                copiedMessageId = nil
                                            }
                                        }
                                    },
                                    onPlayAudio: { msg in
                                        // Stop previous and start new
                                        pausedMessageId = nil
                                        playingMessageId = msg.id
                                        onPlayAudio?(msg)
                                    },
                                    onPauseAudio: {
                                        pausedMessageId = playingMessageId
                                        playingMessageId = nil
                                        onPauseAudio?()
                                    },
                                    onStopAudio: {
                                        playingMessageId = nil
                                        pausedMessageId = nil
                                        onStopAudio?()
                                    }
                                )
                                .id(firstMessage.id)
                            } else {
                                // Show messages separately
                                ForEach(group) { message in
                                    ChatBubbleView(
                                        message: message,
                                        isExpanded: expandedToolMessages.contains(message.id),
                                        isCopied: copiedMessageId == message.id,
                                        isPlaying: playingMessageId == message.id,
                                        isPaused: pausedMessageId == message.id,
                                        onToggleExpand: {
                                            if expandedToolMessages.contains(message.id) {
                                                expandedToolMessages.remove(message.id)
                                            } else {
                                                expandedToolMessages.insert(message.id)
                                            }
                                        },
                                        onCopy: {
                                            UIPasteboard.general.string = message.content
                                            copiedMessageId = message.id
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                                if copiedMessageId == message.id {
                                                    copiedMessageId = nil
                                                }
                                            }
                                        },
                                        onPlayAudio: { msg in
                                            // Stop previous and start new
                                            pausedMessageId = nil
                                            playingMessageId = msg.id
                                            onPlayAudio?(msg)
                                        },
                                        onPauseAudio: {
                                            pausedMessageId = playingMessageId
                                            playingMessageId = nil
                                            onPauseAudio?()
                                        },
                                        onStopAudio: {
                                            playingMessageId = nil
                                            pausedMessageId = nil
                                            onStopAudio?()
                                        }
                                    )
                                    .id(message.id)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { oldCount, newCount in
                // Auto-scroll to bottom when new messages arrive (only in Agent mode)
                if isAgentMode && newCount > oldCount, let lastMessage = messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                // Scroll to bottom on appear (only in Agent mode)
                if isAgentMode, let lastMessage = messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .onReceive(playbackFinishedPublisher) { _ in
                // Reset playing/paused state when playback finishes
                playingMessageId = nil
                pausedMessageId = nil
            }
        }
    }
}

// MARK: - Chat Bubble View
struct ChatBubbleView: View {
    let message: ChatMessage
    let isExpanded: Bool
    let isCopied: Bool
    var isPlaying: Bool = false
    var isPaused: Bool = false
    let onToggleExpand: () -> Void
    let onCopy: () -> Void
    var onPlayAudio: ((ChatMessage) -> Void)? = nil
    var onPauseAudio: (() -> Void)? = nil
    var onStopAudio: (() -> Void)? = nil
    
    /// Check if this is a user-side message (right-aligned)
    /// User type OR user's voice recording (tts_audio with user_ file)
    private var isUserSideMessage: Bool {
        if message.type == .user {
            return true
        }
        if message.type == .tts_audio {
            // User's voice recording has "user_" in filename
            if let path = message.metadata?.audioFilePath, path.contains("user_") {
                return true
            }
        }
        return false
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUserSideMessage {
                Spacer()
            }
            
            VStack(alignment: isUserSideMessage ? .trailing : .leading, spacing: 6) {
                // Message header with timestamp
                HStack(spacing: 6) {
                    if !isUserSideMessage {
                        messageIcon
                    }
                    Text(messageHeader)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Timestamp
                    Text(formatTimestamp(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    if isUserSideMessage {
                        messageIcon
                    }
                    
                    // Copy button (for assistant messages)
                    if message.type == .assistant || message.type == .tool {
                        Button(action: onCopy) {
                            Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(isCopied ? .green : .secondary)
                        }
                    }
                }
                
                // Message content
                messageContentView
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubbleBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            // Voice messages: fit content. Text messages: max 80% width
            .frame(maxWidth: message.type == .tts_audio ? nil : UIScreen.main.bounds.width * 0.80, alignment: isUserSideMessage ? .trailing : .leading)
            
            if !isUserSideMessage {
                Spacer()
            }
        }
    }
    
    private var messageIcon: some View {
        Group {
            switch message.type {
            case .user:
                Image(systemName: "person.fill")
                    .font(.caption)
            case .assistant:
                Image(systemName: "brain.head.profile")
                    .font(.caption)
            case .tool:
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.caption)
            case .system:
                Image(systemName: "gear")
                    .font(.caption)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
            case .tts_audio:
                // User's voice or assistant's TTS
                if isUserSideMessage {
                    Image(systemName: "mic.fill")
                        .font(.caption)
                } else {
                    Image(systemName: "waveform.circle.fill")
                        .font(.caption)
                }
            }
        }
        .foregroundColor(messageIconColor)
    }
    
    private var messageHeader: String {
        switch message.type {
        case .user:
            return "You"
        case .assistant:
            return "Assistant"
        case .tool:
            return message.metadata?.toolName ?? "Tool"
        case .system:
            return "System"
        case .error:
            return "Error"
        case .tts_audio:
            return isUserSideMessage ? "You" : "Voice Response"
        }
    }
    
    private var messageIconColor: Color {
        switch message.type {
        case .user:
            return .blue
        case .assistant:
            return .green
        case .tool:
            return .orange
        case .system:
            return .gray
        case .error:
            return .red
        case .tts_audio:
            return isUserSideMessage ? .blue : .purple
        }
    }
    
    private var bubbleBackground: Color {
        switch message.type {
        case .user:
            return Color.blue.opacity(0.1)
        case .assistant:
            return Color.green.opacity(0.1)
        case .tool:
            return Color.orange.opacity(0.1)
        case .system:
            return Color.gray.opacity(0.1)
        case .error:
            return Color.red.opacity(0.1)
        case .tts_audio:
            return isUserSideMessage ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1)
        }
    }
    
    @ViewBuilder
    private var messageContentView: some View {
        switch message.type {
        case .tool:
            ToolMessageView(
                message: message,
                isExpanded: isExpanded,
                onToggleExpand: onToggleExpand
            )
        case .tts_audio:
            VoiceMessageView(
                message: message,
                isExpanded: isExpanded,
                isPlaying: isPlaying,
                isPaused: isPaused,
                onToggleExpand: onToggleExpand,
                onPlay: { onPlayAudio?(message) },
                onPause: { onPauseAudio?() },
                onStop: { onStopAudio?() }
            )
        default:
            // Try to detect and render code blocks
            if message.content.contains("```") {
                MarkdownContentView(text: message.content)
            } else {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func formatTimestamp(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Markdown Content View
struct MarkdownContentView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Simple markdown parsing for code blocks
            let parts = parseMarkdown(text)
            
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if part.isCode {
                    CodeBlockView(code: part.text, language: part.language)
                } else {
                    Text(part.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private func parseMarkdown(_ text: String) -> [MarkdownPart] {
        var parts: [MarkdownPart] = []
        let codeBlockRegex = try! NSRegularExpression(pattern: "```(\\w+)?\\n([\\s\\S]*?)```", options: [])
        let nsString = text as NSString
        var lastIndex = 0
        
        codeBlockRegex.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) { match, _, _ in
            guard let match = match else { return }
            
            // Add text before code block
            if match.range.location > lastIndex {
                let textRange = NSRange(location: lastIndex, length: match.range.location - lastIndex)
                let textPart = nsString.substring(with: textRange)
                if !textPart.isEmpty {
                    parts.append(MarkdownPart(text: textPart, isCode: false, language: nil))
                }
            }
            
            // Add code block
            let languageRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            let language = languageRange.location != NSNotFound ? nsString.substring(with: languageRange) : nil
            let code = nsString.substring(with: codeRange)
            parts.append(MarkdownPart(text: code, isCode: true, language: language))
            
            lastIndex = match.range.location + match.range.length
        }
        
        // Add remaining text
        if lastIndex < nsString.length {
            let textPart = nsString.substring(from: lastIndex)
            if !textPart.isEmpty {
                parts.append(MarkdownPart(text: textPart, isCode: false, language: nil))
            }
        }
        
        return parts.isEmpty ? [MarkdownPart(text: text, isCode: false, language: nil)] : parts
    }
}

struct MarkdownPart {
    let text: String
    let isCode: Bool
    let language: String?
}

// MARK: - Code Block View
struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Code block header with language and copy button
            HStack {
                if let language = language {
                    Text(language)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    UIPasteboard.general.string = code
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCopied = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            
            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

// MARK: - Tool Message View
struct ToolMessageView: View {
    let message: ChatMessage
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tool name and expand button
            HStack {
                Text(message.metadata?.toolName ?? "Tool")
                    .font(.headline)
                Spacer()
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
            
            // Tool content (always show main content)
            Text(message.content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            
            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let input = message.metadata?.toolInput, !input.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Input:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(input)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(6)
                        }
                    }
                    
                    if let output = message.metadata?.toolOutput, !output.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Output:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ScrollView {
                                Text(output)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 200)
                            .padding(8)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Voice Message View
struct VoiceMessageView: View {
    let message: ChatMessage
    let isExpanded: Bool
    var isPlaying: Bool = false
    var isPaused: Bool = false
    let onToggleExpand: () -> Void
    var onPlay: (() -> Void)? = nil
    var onPause: (() -> Void)? = nil
    var onStop: (() -> Void)? = nil
    
    private var hasAudio: Bool {
        message.metadata?.audioFilePath != nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Compact player controls
            HStack(spacing: 8) {
                // Play/Pause/Stop buttons
                if isPlaying {
                    // Pause button
                    Button(action: { onPause?() }) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.purple)
                    }
                    // Stop button
                    Button(action: { onStop?() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.purple.opacity(0.7))
                    }
                } else if isPaused {
                    // Resume button
                    Button(action: { onPlay?() }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.purple)
                    }
                    // Stop button
                    Button(action: { onStop?() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.purple.opacity(0.7))
                    }
                } else {
                    // Play button
                    Button(action: { onPlay?() }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(hasAudio ? .purple : .gray)
                    }
                    .disabled(!hasAudio)
                }
                
                // Waveform bars
                HStack(spacing: 2) {
                    ForEach(0..<10, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.purple.opacity(isPlaying ? 0.8 : 0.4))
                            .frame(width: 2, height: CGFloat(6 + (index % 4) * 3))
                    }
                }
                .frame(width: 40, height: 20)
                
                // Expand button for text
                if message.metadata?.ttsText != nil {
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up" : "text.bubble")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Show TTS text when expanded
            if isExpanded, let ttsText = message.metadata?.ttsText {
                Text(ttsText)
                    .font(.caption2)
                    .foregroundColor(.primary.opacity(0.7))
                    .lineLimit(3)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ChatHistoryView(
        messages: [
            ChatMessage(
                id: "1",
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                type: .user,
                content: "List files in current directory"
            ),
            ChatMessage(
                id: "2",
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                type: .assistant,
                content: "I'll list the files for you."
            ),
            ChatMessage(
                id: "3",
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                type: .tool,
                content: "Tool: bash\nInput: ls -la\nOutput: file1.txt\nfile2.py",
                metadata: ChatMessage.Metadata(
                    toolName: "bash",
                    toolInput: "ls -la",
                    toolOutput: "total 24\ndrwxr-xr-x  5 user staff  160 Nov 28 10:00 .\ndrwxr-xr-x 10 user staff  320 Nov 27 15:30 ..\n-rw-r--r--  1 user staff 1234 Nov 28 09:45 file1.txt\n-rw-r--r--  1 user staff 5678 Nov 28 09:50 file2.py"
                )
            ),
            ChatMessage(
                id: "4",
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                type: .assistant,
                content: "Here are the files in the directory."
            )
        ],
        isAgentMode: true
    )
    .padding()
}
