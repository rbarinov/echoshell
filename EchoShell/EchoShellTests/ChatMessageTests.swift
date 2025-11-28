//
//  ChatMessageTests.swift
//  EchoShellTests
//
//  Created for Voice-Controlled Terminal Management System
//  Tests for ChatMessage model
//

import Testing
@testable import EchoShell

struct ChatMessageTests {
    
    @Test func testChatMessageCodable() async throws {
        let message = ChatMessage(
            id: "msg-001",
            timestamp: 1701234567890,
            type: .assistant,
            content: "Hello, world!",
            metadata: ChatMessage.Metadata(
                toolName: "bash",
                toolInput: "ls -la",
                toolOutput: "file1.txt\nfile2.py"
            )
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ChatMessage.self, from: data)
        
        #expect(decoded.id == message.id)
        #expect(decoded.timestamp == message.timestamp)
        #expect(decoded.type == message.type)
        #expect(decoded.content == message.content)
        #expect(decoded.metadata?.toolName == message.metadata?.toolName)
    }
    
    @Test func testChatMessageEquatable() async throws {
        let message1 = ChatMessage(
            id: "msg-001",
            timestamp: 1701234567890,
            type: .user,
            content: "List files"
        )
        
        let message2 = ChatMessage(
            id: "msg-001",
            timestamp: 1701234567890,
            type: .user,
            content: "List files"
        )
        
        let message3 = ChatMessage(
            id: "msg-002",
            timestamp: 1701234567890,
            type: .user,
            content: "List files"
        )
        
        #expect(message1 == message2)
        #expect(message1 != message3)
    }
    
    @Test func testChatMessageTypes() async throws {
        let userMessage = ChatMessage(
            id: "1",
            timestamp: 0,
            type: .user,
            content: "User message"
        )
        #expect(userMessage.type == .user)
        
        let assistantMessage = ChatMessage(
            id: "2",
            timestamp: 0,
            type: .assistant,
            content: "Assistant message"
        )
        #expect(assistantMessage.type == .assistant)
        
        let toolMessage = ChatMessage(
            id: "3",
            timestamp: 0,
            type: .tool,
            content: "Tool message",
            metadata: ChatMessage.Metadata(toolName: "bash")
        )
        #expect(toolMessage.type == .tool)
        #expect(toolMessage.metadata?.toolName == "bash")
        
        let systemMessage = ChatMessage(
            id: "4",
            timestamp: 0,
            type: .system,
            content: "System message"
        )
        #expect(systemMessage.type == .system)
        
        let errorMessage = ChatMessage(
            id: "5",
            timestamp: 0,
            type: .error,
            content: "Error message",
            metadata: ChatMessage.Metadata(errorCode: "EACCES")
        )
        #expect(errorMessage.type == .error)
        #expect(errorMessage.metadata?.errorCode == "EACCES")
    }
    
    @Test func testChatMessageEventDecoding() async throws {
        let json = """
        {
            "type": "chat_message",
            "session_id": "session-123",
            "message": {
                "id": "msg-001",
                "timestamp": 1701234567890,
                "type": "assistant",
                "content": "Hello, world!"
            },
            "timestamp": 1701234567890
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let event = try decoder.decode(ChatMessageEvent.self, from: data)
        
        #expect(event.type == "chat_message")
        #expect(event.session_id == "session-123")
        #expect(event.message.type == .assistant)
        #expect(event.message.content == "Hello, world!")
    }
}
