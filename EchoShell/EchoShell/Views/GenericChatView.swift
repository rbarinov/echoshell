//
//  GenericChatView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Generic Telegram-style chat interface for supervisor and terminal sessions
//

import SwiftUI

struct GenericChatView<ViewModel: ChatViewModelProtocol>: View {
    @ObservedObject var viewModel: ViewModel
    let isAgentMode: Bool // true = auto-scroll on new messages
    
    @State private var expandedToolMessages: Set<String> = []
    @State private var copiedMessageId: String? = nil
    @State private var inputText: String = ""
    
    // Subscribe to playback finished events
    private let playbackFinishedPublisher = EventBus.shared.ttsPlaybackFinishedPublisher
    
    // Filter out system messages
    private var filteredMessages: [ChatMessage] {
        viewModel.chatHistory.filter { $0.type != .system }
    }
    
    // Group messages by sender and time (Telegram-style)
    // Messages from same sender within 5 minutes are grouped together
    private var groupedMessages: [[ChatMessage]] {
        var groups: [[ChatMessage]] = []
        var currentGroup: [ChatMessage] = []
        var lastSenderType: ChatMessage.MessageType? = nil
        var lastTimestamp: Int64? = nil
        
        for message in filteredMessages {
            // Determine sender type (user vs assistant)
            let senderType: ChatMessage.MessageType = {
                if message.type == .user {
                    return .user
                }
                if message.type == .tts_audio {
                    // User's voice recording has "user_" in filename
                    if let path = message.metadata?.audioFilePath, path.contains("user_") {
                        return .user
                    }
                }
                // Everything else is assistant-side
                return .assistant
            }()
            
            // Start new group when:
            // 1. Sender changes (user -> assistant or vice versa)
            // 2. More than 5 minutes passed since last message
            let timeDiff = lastTimestamp != nil ? abs(message.timestamp - lastTimestamp!) : 0
            let fiveMinutes = 5 * 60 * 1000 // 5 minutes in milliseconds
            
            let shouldStartNewGroup = senderType != lastSenderType || 
                                     (lastTimestamp != nil && timeDiff > fiveMinutes)
            
            if shouldStartNewGroup && !currentGroup.isEmpty {
                groups.append(currentGroup)
                currentGroup = [message]
            } else {
                currentGroup.append(message)
            }
            
            lastSenderType = senderType
            lastTimestamp = message.timestamp
        }
        
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }
        
        return groups
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Chat messages area (scrollable)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(groupedMessages.enumerated()), id: \.offset) { groupIndex, group in
                                MessageGroupView(
                                    messages: group,
                                    expandedToolMessages: $expandedToolMessages,
                                    copiedMessageId: $copiedMessageId,
                                    viewModel: viewModel
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .padding(.bottom, 8) // Extra padding at bottom
                    }
                    .frame(height: geometry.size.height - 70) // Reserve space for input bar
                    .onChange(of: viewModel.chatHistory.count) { oldCount, newCount in
                        // Auto-scroll to bottom when new messages arrive (only in Agent mode)
                        if isAgentMode && newCount > oldCount, let lastMessage = viewModel.chatHistory.last {
                            // Small delay to ensure message is rendered
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .onAppear {
                        // Scroll to bottom on appear (only in Agent mode)
                        if isAgentMode, let lastMessage = viewModel.chatHistory.last {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onReceive(playbackFinishedPublisher) { _ in
                        // Playback finished - view will update via viewModel state
                    }
                }
                
                // Fixed input bar at bottom (Telegram-style) - pinned to bottom
                ChatInputBar(
                    text: $inputText,
                    onSendText: { text in
                        Task {
                            await viewModel.sendTextCommand(text)
                        }
                    },
                    onStartRecording: {
                        viewModel.startRecording()
                    },
                    onStopRecording: {
                        viewModel.stopRecording()
                    },
                    isRecording: viewModel.isRecording,
                    isProcessing: viewModel.isProcessing,
                    isEnabled: true
                )
                .background(
                    Color(.systemBackground)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: -2)
                )
            }
        }
    }
}

// MARK: - Message Group View
struct MessageGroupView<ViewModel: ChatViewModelProtocol>: View {
    let messages: [ChatMessage]
    @Binding var expandedToolMessages: Set<String>
    @Binding var copiedMessageId: String?
    @ObservedObject var viewModel: ViewModel
    
    // Determine if this is a user-side group
    private var isUserSideGroup: Bool {
        guard let firstMessage = messages.first else { return false }
        if firstMessage.type == .user {
            return true
        }
        if firstMessage.type == .tts_audio {
            if let path = firstMessage.metadata?.audioFilePath, path.contains("user_") {
                return true
            }
        }
        return false
    }
    
    var body: some View {
        VStack(alignment: isUserSideGroup ? .trailing : .leading, spacing: 8) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                let playbackState = viewModel.audioPlaybackState
                
                TelegramBubbleView(
                    message: message,
                    isFirstInGroup: index == 0,
                    isLastInGroup: index == messages.count - 1,
                    isUserSide: isUserSideGroup,
                    isExpanded: expandedToolMessages.contains(message.id),
                    isCopied: copiedMessageId == message.id,
                    isPlaying: playbackState.isPlaying(message.id),
                    isPaused: playbackState.isPaused(message.id),
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
                        // Haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    },
                    onPlayAudio: {
                        viewModel.playAudioMessage(message)
                    },
                    onPauseAudio: {
                        viewModel.pauseAudio()
                    },
                    onStopAudio: {
                        viewModel.stopAudio()
                    }
                )
                .id(message.id)
            }
        }
    }
}

// MARK: - Telegram-Style Bubble View
struct TelegramBubbleView: View {
    let message: ChatMessage
    let isFirstInGroup: Bool
    let isLastInGroup: Bool
    let isUserSide: Bool
    let isExpanded: Bool
    let isCopied: Bool
    let isPlaying: Bool
    let isPaused: Bool
    let onToggleExpand: () -> Void
    let onCopy: () -> Void
    let onPlayAudio: () -> Void
    let onPauseAudio: () -> Void
    let onStopAudio: () -> Void
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isUserSide {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: isUserSide ? .trailing : .leading, spacing: 4) {
                // Timestamp and icon (only on first message in group)
                if isFirstInGroup {
                    HStack(spacing: 4) {
                        if !isUserSide {
                            messageIcon
                        }
                        Text(formatTimestamp(message.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if isUserSide {
                            messageIcon
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
                }
                
                // Message bubble
                messageBubble
                    .frame(maxWidth: bubbleMaxWidth, alignment: isUserSide ? .trailing : .leading)
            }
            
            if !isUserSide {
                Spacer(minLength: 50)
            }
        }
    }
    
    private var bubbleMaxWidth: CGFloat {
        let defaultWidth = UIScreen.main.bounds.width * 0.75
        if message.type == .tts_audio {
            return UIScreen.main.bounds.width * 0.55
        }
        return defaultWidth
    }
    
    private var messageIcon: some View {
        Group {
            switch message.type {
            case .user:
                Image(systemName: "person.fill")
                    .font(.caption2)
            case .assistant:
                Image(systemName: "brain.head.profile")
                    .font(.caption2)
            case .tool:
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.caption2)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
            case .tts_audio:
                if isUserSide {
                    Image(systemName: "mic.fill")
                        .font(.caption2)
                } else {
                    Image(systemName: "waveform.circle.fill")
                        .font(.caption2)
                }
            default:
                EmptyView()
            }
        }
        .foregroundColor(messageIconColor)
    }
    
    private var messageIconColor: Color {
        if isUserSide {
            return .blue
        }
        switch message.type {
        case .assistant:
            return .green
        case .tool:
            return .orange
        case .error:
            return .red
        case .tts_audio:
            return .purple
        default:
            return .secondary
        }
    }
    
    @ViewBuilder
    private var messageBubble: some View {
        VStack(alignment: isUserSide ? .trailing : .leading, spacing: 6) {
            // Message content
            messageContentView
            
            // Copy button for assistant messages (bottom right)
            if !isUserSide && (message.type == .assistant || message.type == .tool) {
                HStack {
                    Spacer()
                    Button(action: onCopy) {
                        Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.caption2)
                            .foregroundColor(isCopied ? .green : .secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bubbleBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private var bubbleBackground: some View {
        Group {
            if isUserSide {
                // User messages: blue gradient (Telegram-style)
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                // Assistant messages: light gray/white
                Color(.systemGray6)
            }
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
            TelegramVoiceMessageView(
                message: message,
                isExpanded: isExpanded,
                isPlaying: isPlaying,
                isPaused: isPaused,
                isUserSide: isUserSide,
                onToggleExpand: onToggleExpand,
                onPlay: onPlayAudio,
                onPause: onPauseAudio,
                onStop: onStopAudio
            )
        default:
            // Text messages with markdown support
            if message.content.contains("```") {
                MarkdownContentView(text: message.content)
            } else {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(isUserSide ? .white : .primary)
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

// MARK: - Telegram-Style Voice Message View
struct TelegramVoiceMessageView: View {
    let message: ChatMessage
    let isExpanded: Bool
    let isPlaying: Bool
    let isPaused: Bool
    let isUserSide: Bool
    let onToggleExpand: () -> Void
    let onPlay: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    
    private var hasAudio: Bool {
        message.metadata?.audioFilePath != nil
    }
    
    // Get audio duration from metadata or estimate
    private var duration: TimeInterval {
        if let duration = message.metadata?.ttsDuration {
            return duration
        }
        // Estimate based on text length (average speaking rate: 150 words/min)
        let wordCount = message.metadata?.ttsText?.components(separatedBy: .whitespaces).count ?? 0
        return Double(wordCount) / 2.5 // ~2.5 words per second
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Inline audio player (Telegram-style)
            HStack(spacing: 6) {
                // Play/Pause button (single control)
                Button(action: {
                    if isPlaying {
                        onPause()
                    } else {
                        onPlay()
                    }
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(isUserSide ? .white : .blue)
                }
                .disabled(!hasAudio)
                .buttonStyle(.plain)
                
                // Waveform visualization (compact width)
                WaveformView(
                    barCount: 10,
                    isPlaying: isPlaying,
                    progress: isPlaying ? 0.5 : 1.0, // TODO: Get actual progress from player
                    color: isUserSide ? .white.opacity(0.8) : .blue,
                    height: 20
                )
                .frame(width: 70)
                
                // Duration label
                Text(formatDuration(duration))
                    .font(.caption2)
                    .foregroundColor(isUserSide ? .white.opacity(0.8) : .secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                
                // Expand button for transcript
                if message.metadata?.ttsText != nil {
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up" : "text.bubble")
                            .font(.caption2)
                            .foregroundColor(isUserSide ? .white.opacity(0.8) : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
            
            // Show transcript when expanded
            if isExpanded, let ttsText = message.metadata?.ttsText {
                Text(ttsText)
                    .font(.caption)
                    .foregroundColor(isUserSide ? .white.opacity(0.9) : .primary)
                    .padding(.top, 4)
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Supporting Views
// Note: MarkdownContentView, CodeBlockView, ToolMessageView, and MarkdownPart
// are defined in ChatHistoryView.swift and reused here

