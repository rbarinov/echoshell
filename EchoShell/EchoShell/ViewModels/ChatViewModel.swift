//
//  ChatViewModel.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  ViewModel for managing chat history and messages for headless terminals
//

import Foundation
import Combine

@MainActor
class ChatViewModel: ObservableObject, ChatViewModelProtocol {
    // MARK: - Published State
    
    /// Full chat history (all messages from session start, continuously accumulated)
    /// Messages are never cleared - they accumulate throughout the session
    @Published var chatHistory: [ChatMessage] = []
    
    /// Whether the chat is currently processing a request
    @Published var isProcessing: Bool = false
    
    // MARK: - Session Info
    
    let sessionId: String
    
    // MARK: - Private State
    
    private var cancellables = Set<AnyCancellable>()
    private var currentlyPlayingMessageId: String? // Track which message is currently playing
    
    // MARK: - Initialization
    
    init(sessionId: String) {
        self.sessionId = sessionId
    }
    
    // MARK: - Public Methods
    
    /// Add a chat message to history
    /// All messages are added except system messages
    /// Messages accumulate continuously - never cleared
    func addMessage(_ message: ChatMessage) {
        // Filter out system messages - don't add them to history
        guard message.type != .system else {
            print("ℹ️ ChatViewModel: Skipping system message: \(message.content.prefix(50))")
            return
        }
        
        // Add to full history (continuously accumulated, never cleared)
        chatHistory.append(message)
        print("✅ ChatViewModel: Added message (type: \(message.type), total: \(chatHistory.count))")
    }
    
    /// Load messages from history (used when restoring from server)
    func loadMessages(_ messages: [ChatMessage]) {
        // Filter out system messages, but keep all other types (user, assistant, tool, error, thinking, code, etc.)
        let filteredMessages = messages.filter { $0.type != .system }
        chatHistory = filteredMessages
        
        print("✅ ChatViewModel: Loaded \(filteredMessages.count) messages (filtered from \(messages.count))")
    }
    
    // MARK: - ChatViewModelProtocol (Audio Playback)
    // Note: ChatViewModel doesn't handle audio playback directly
    // Audio playback is handled by ChatTerminalView's own audio player
    // These methods are stubs that can be overridden by views that need audio
    
    func playAudioMessage(_ message: ChatMessage) {
        // Stub implementation - actual playback handled by view
        currentlyPlayingMessageId = message.id
        print("ℹ️ ChatViewModel: playAudioMessage called (stub - handled by view)")
    }
    
    func pauseAudio() {
        print("ℹ️ ChatViewModel: pauseAudio called (stub - handled by view)")
    }
    
    func stopAudio() {
        currentlyPlayingMessageId = nil
        print("ℹ️ ChatViewModel: stopAudio called (stub - handled by view)")
    }
    
    func isMessagePlaying(_ messageId: String) -> Bool {
        return currentlyPlayingMessageId == messageId
    }
    
    func isMessagePaused(_ messageId: String) -> Bool {
        return false // ChatViewModel doesn't track pause state
    }
    
    var audioPlaybackState: AudioPlaybackState {
        if let messageId = currentlyPlayingMessageId {
            return AudioPlaybackState(messageId: messageId, status: .stopped)
        }
        return .idle
    }
    
    // MARK: - ChatViewModelProtocol (Text Input & Recording)
    // Note: ChatViewModel doesn't handle text commands or recording directly
    // These are handled by the view (ChatTerminalView) which has access to WebSocket
    
    var isRecording: Bool {
        return false // ChatViewModel doesn't track recording state
    }
    
    func sendTextCommand(_ command: String) async {
        // Stub implementation - actual sending handled by view
        print("ℹ️ ChatViewModel: sendTextCommand called (stub - handled by view)")
    }
    
    func startRecording() {
        print("ℹ️ ChatViewModel: startRecording called (stub - handled by view)")
    }
    
    func stopRecording() {
        print("ℹ️ ChatViewModel: stopRecording called (stub - handled by view)")
    }
}
