//
//  TerminalMessage.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//

import Foundation

struct TerminalMessage: Identifiable, Codable {
    let id = UUID()
    let type: MessageType
    let sessionId: String
    let data: String
    let timestamp: Date
    
    enum MessageType: String, Codable {
        case output
        case command
        case error
        case status
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case sessionId
        case data
        case timestamp
    }
    
    init(type: MessageType, sessionId: String, data: String, timestamp: Date) {
        self.type = type
        self.sessionId = sessionId
        self.data = data
        self.timestamp = timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(MessageType.self, forKey: .type)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        data = try container.decode(String.self, forKey: .data)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
}
