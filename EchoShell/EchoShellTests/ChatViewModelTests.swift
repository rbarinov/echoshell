//
//  ChatViewModelTests.swift
//  EchoShellTests
//
//  Created for Voice-Controlled Terminal Management System
//  Tests for ChatViewModel
//

import Testing
@testable import EchoShell

struct ChatViewModelTests {
    
    @Test func testChatViewModelInitialization() async throws {
        let viewModel = ChatViewModel(sessionId: "test-session")
        
        #expect(viewModel.sessionId == "test-session")
        #expect(viewModel.chatHistory.isEmpty)
        #expect(viewModel.currentExecutionMessages.isEmpty)
        #expect(viewModel.viewMode == .agent)
    }
    
    @Test func testAddMessage() async throws {
        let viewModel = ChatViewModel(sessionId: "test-session")
        
        let message = ChatMessage(
            id: "msg-001",
            timestamp: 1701234567890,
            type: .user,
            content: "Test message"
        )
        
        viewModel.addMessage(message)
        
        #expect(viewModel.chatHistory.count == 1)
        #expect(viewModel.currentExecutionMessages.count == 1)
        #expect(viewModel.chatHistory.first?.id == "msg-001")
    }
    
    @Test func testClearCurrentExecution() async throws {
        let viewModel = ChatViewModel(sessionId: "test-session")
        
        let message = ChatMessage(
            id: "msg-001",
            timestamp: 1701234567890,
            type: .user,
            content: "Test message"
        )
        
        viewModel.addMessage(message)
        viewModel.clearCurrentExecution()
        
        #expect(viewModel.chatHistory.count == 1) // History preserved
        #expect(viewModel.currentExecutionMessages.isEmpty) // Current cleared
    }
    
    @Test func testFinalizeCurrentExecution() async throws {
        let viewModel = ChatViewModel(sessionId: "test-session")
        
        let message = ChatMessage(
            id: "msg-001",
            timestamp: 1701234567890,
            type: .assistant,
            content: "Response"
        )
        
        viewModel.addMessage(message)
        viewModel.finalizeCurrentExecution()
        
        #expect(viewModel.chatHistory.count == 1) // History preserved
        #expect(viewModel.currentExecutionMessages.isEmpty) // Current cleared
    }
    
    @Test func testToggleViewMode() async throws {
        let viewModel = ChatViewModel(sessionId: "test-session")
        
        #expect(viewModel.viewMode == .agent)
        
        viewModel.toggleViewMode()
        #expect(viewModel.viewMode == .history)
        
        viewModel.toggleViewMode()
        #expect(viewModel.viewMode == .agent)
    }
    
    @Test func testGetMessagesForCurrentMode() async throws {
        let viewModel = ChatViewModel(sessionId: "test-session")
        
        let historyMessage = ChatMessage(
            id: "msg-001",
            timestamp: 1701234567890,
            type: .user,
            content: "History message"
        )
        
        let currentMessage = ChatMessage(
            id: "msg-002",
            timestamp: 1701234567891,
            type: .assistant,
            content: "Current message"
        )
        
        viewModel.addMessage(historyMessage)
        viewModel.finalizeCurrentExecution()
        viewModel.addMessage(currentMessage)
        
        // In agent mode, should show current execution
        viewModel.viewMode = .agent
        let agentMessages = viewModel.getMessagesForCurrentMode()
        #expect(agentMessages.count == 1)
        #expect(agentMessages.first?.id == "msg-002")
        
        // In history mode, should show full history
        viewModel.viewMode = .history
        let historyMessages = viewModel.getMessagesForCurrentMode()
        #expect(historyMessages.count == 2)
    }
}
