//
//  ChatViewModel.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  ViewModel for managing chat history and messages for headless terminals
//

import Foundation
import Combine

enum ChatViewMode {
    case agent // Current execution
    case history // Full conversation history
}

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published State
    
    /// Full chat history (all messages from session start)
    @Published var chatHistory: [ChatMessage] = []
    
    /// Messages from current execution only
    @Published var currentExecutionMessages: [ChatMessage] = []
    
    /// Current view mode (Agent or History)
    @Published var viewMode: ChatViewMode = .agent
    
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
    func addMessage(_ message: ChatMessage) {
        // Add to full history
        chatHistory.append(message)
        
        // Add to current execution if it's part of current execution
        // (We'll track this based on execution state)
        currentExecutionMessages.append(message)
    }
    
    /// Clear current execution messages (when new command starts)
    func clearCurrentExecution() {
        currentExecutionMessages = []
    }
    
    /// Move current execution messages to history (when execution completes)
    func finalizeCurrentExecution() {
        // Current execution messages are already in chatHistory
        // Just clear the current execution list
        currentExecutionMessages = []
    }
    
    /// Toggle view mode
    func toggleViewMode() {
        viewMode = viewMode == .agent ? .history : .agent
    }
    
    /// Get messages for current view mode
    func getMessagesForCurrentMode() -> [ChatMessage] {
        switch viewMode {
        case .agent:
            return currentExecutionMessages
        case .history:
            return chatHistory
        }
    }
}
