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
class ChatViewModel: ObservableObject {
    // MARK: - Published State
    
    /// Full chat history (all messages from session start, continuously accumulated)
    /// Messages are never cleared - they accumulate throughout the session
    @Published var chatHistory: [ChatMessage] = []
    
    // MARK: - Session Info
    
    let sessionId: String
    
    // MARK: - Private State
    
    private var cancellables = Set<AnyCancellable>()
    
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
}
