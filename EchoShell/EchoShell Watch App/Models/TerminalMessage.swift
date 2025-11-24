//
//  TerminalMessage.swift
//  EchoShell Watch App
//
//  Created for Voice-Controlled Terminal Management System
//

import Foundation

struct TerminalMessage: Identifiable, Codable {
    let id: UUID
    let type: MessageType
    let sessionId: String
    let data: String
    let timestamp: Date
    
    enum MessageType: String, Codable {
        case output
        case input
        case error
    }
    
    init(type: MessageType, sessionId: String, data: String, timestamp: Date) {
        self.id = UUID()
        self.type = type
        self.sessionId = sessionId
        self.data = data
        self.timestamp = timestamp
    }
}

