//
//  ChatMessage.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Chat message model for headless terminals (cursor, claude)
//

import Foundation

struct ChatMessage: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: Int64
    let type: MessageType
    let content: String
    let metadata: Metadata?
    
    enum MessageType: String, Codable {
        case user
        case assistant
        case tool
        case system
        case error
    }
    
    struct Metadata: Codable, Equatable {
        let toolName: String?
        let toolInput: String?
        let toolOutput: String?
        let thinking: String?
        let errorCode: String?
        let stackTrace: String?
        let completion: Bool?
        
        init(
            toolName: String? = nil,
            toolInput: String? = nil,
            toolOutput: String? = nil,
            thinking: String? = nil,
            errorCode: String? = nil,
            stackTrace: String? = nil,
            completion: Bool? = nil
        ) {
            self.toolName = toolName
            self.toolInput = toolInput
            self.toolOutput = toolOutput
            self.thinking = thinking
            self.errorCode = errorCode
            self.stackTrace = stackTrace
            self.completion = completion
        }
    }
    
    init(
        id: String,
        timestamp: Int64,
        type: MessageType,
        content: String,
        metadata: Metadata? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.content = content
        self.metadata = metadata
    }
}

// MARK: - Chat Message Event (from WebSocket)
struct ChatMessageEvent: Codable {
    let type: String
    let session_id: String
    let message: ChatMessage
    let timestamp: Int64
}
