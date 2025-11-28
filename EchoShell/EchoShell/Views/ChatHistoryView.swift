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
    
    @State private var expandedToolMessages: Set<String> = []
    @State private var copiedMessageId: String? = nil
    
    // Group messages by conversation turn (user + assistant responses)
    private var groupedMessages: [[ChatMessage]] {
        var groups: [[ChatMessage]] = []
        var currentGroup: [ChatMessage] = []
        
        for message in messages {
            if message.type == .user && !currentGroup.isEmpty {
                // Start new group when we see a user message
                groups.append(currentGroup)
                currentGroup = [message]
            } else {
                currentGroup.append(message)
            }
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
                            // Show separator between conversation turns (except first)
                            if groupIndex > 0 {
                                Divider()
                                    .padding(.vertical, 8)
                            }
                            
                            ForEach(group) { message in
                                ChatBubbleView(
                                    message: message,
                                    isExpanded: expandedToolMessages.contains(message.id),
                                    isCopied: copiedMessageId == message.id,
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
                                        // Reset copied state after 2 seconds
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            if copiedMessageId == message.id {
                                                copiedMessageId = nil
                                            }
                                        }
                                    }
                                )
                                .id(message.id)
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
        }
    }
}

// MARK: - Chat Bubble View
struct ChatBubbleView: View {
    let message: ChatMessage
    let isExpanded: Bool
    let isCopied: Bool
    let onToggleExpand: () -> Void
    let onCopy: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.type == .user {
                Spacer()
            }
            
            VStack(alignment: message.type == .user ? .trailing : .leading, spacing: 6) {
                // Message header with timestamp
                HStack(spacing: 6) {
                    if message.type != .user {
                        messageIcon
                    }
                    Text(messageHeader)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Timestamp
                    Text(formatTimestamp(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    if message.type == .user {
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
            .frame(maxWidth: UIScreen.main.bounds.width * 0.80, alignment: message.type == .user ? .trailing : .leading)
            
            if message.type != .user {
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

// MARK: - Preview
#Preview {
    ChatHistoryView(
        messages: [
            ChatMessage(
                id: "1",
                timestamp: Date().timeIntervalSince1970.magnitude,
                type: .user,
                content: "List files in current directory"
            ),
            ChatMessage(
                id: "2",
                timestamp: Date().timeIntervalSince1970.magnitude,
                type: .assistant,
                content: "I'll list the files for you."
            ),
            ChatMessage(
                id: "3",
                timestamp: Date().timeIntervalSince1970.magnitude,
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
                timestamp: Date().timeIntervalSince1970.magnitude,
                type: .assistant,
                content: "Here are the files in the directory."
            )
        ],
        isAgentMode: true
    )
    .padding()
}
