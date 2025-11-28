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
        let viewModel = await ChatViewModel(sessionId: "test-session")
        
        let sessionId = await viewModel.sessionId
        let chatHistory = await viewModel.chatHistory
        
        #expect(sessionId == "test-session")
        #expect(chatHistory.isEmpty)
    }
    
    @Test func testAddMessage() async throws {
        let viewModel = await ChatViewModel(sessionId: "test-session")
        
        let message = ChatMessage(
            id: "msg-001",
            timestamp: 1701234567890,
            type: .user,
            content: "Test message"
        )
        
        await viewModel.addMessage(message)
        
        let chatHistory = await viewModel.chatHistory
        #expect(chatHistory.count == 1)
        #expect(chatHistory.first?.id == "msg-001")
    }
    
    @Test func testAddMultipleMessages() async throws {
        let viewModel = await ChatViewModel(sessionId: "test-session")
        
        let message1 = ChatMessage(
            id: "msg-001",
            timestamp: 1701234567890,
            type: .user,
            content: "User message"
        )
        
        let message2 = ChatMessage(
            id: "msg-002",
            timestamp: 1701234567891,
            type: .assistant,
            content: "Assistant response"
        )
        
        await viewModel.addMessage(message1)
        await viewModel.addMessage(message2)
        
        let chatHistory = await viewModel.chatHistory
        #expect(chatHistory.count == 2)
        #expect(chatHistory[0].type == .user)
        #expect(chatHistory[1].type == .assistant)
    }
    
    @Test func testSystemMessagesAreFiltered() async throws {
        let viewModel = await ChatViewModel(sessionId: "test-session")
        
        let systemMessage = ChatMessage(
            id: "msg-001",
            timestamp: 1701234567890,
            type: .system,
            content: "System message"
        )
        
        await viewModel.addMessage(systemMessage)
        
        let chatHistory = await viewModel.chatHistory
        #expect(chatHistory.isEmpty) // System messages should be filtered out
    }
    
    @Test func testLoadMessages() async throws {
        let viewModel = await ChatViewModel(sessionId: "test-session")
        
        let messages = [
            ChatMessage(id: "msg-001", timestamp: 1701234567890, type: .user, content: "First"),
            ChatMessage(id: "msg-002", timestamp: 1701234567891, type: .system, content: "System"),
            ChatMessage(id: "msg-003", timestamp: 1701234567892, type: .assistant, content: "Response")
        ]
        
        await viewModel.loadMessages(messages)
        
        let chatHistory = await viewModel.chatHistory
        #expect(chatHistory.count == 2) // System message filtered
        #expect(chatHistory[0].id == "msg-001")
        #expect(chatHistory[1].id == "msg-003")
    }
}
