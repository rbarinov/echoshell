//
//  TerminalSession.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//

import Foundation

struct TerminalSession: Identifiable, Codable, Hashable {
    let id: String
    let workingDir: String
    var isActive: Bool
    var lastOutput: String
    var lastUpdate: Date
    
    // Hashable conformance - hash based on unique id
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Equatable conformance (required by Hashable)
    static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        return lhs.id == rhs.id
    }
}
