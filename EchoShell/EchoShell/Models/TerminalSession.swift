//
//  TerminalSession.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//

import Foundation

struct TerminalSession: Identifiable, Codable {
    let id: String
    let workingDir: String
    var isActive: Bool
    var lastOutput: String
    var lastUpdate: Date
}
