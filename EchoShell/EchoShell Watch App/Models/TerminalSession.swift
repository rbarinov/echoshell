//
//  TerminalSession.swift
//  EchoShell Watch App
//
//  Created for Voice-Controlled Terminal Management System
//

import Foundation

enum TerminalType: String, Codable {
    case regular = "regular"
    case cursorAgent = "cursor_agent"
}

struct TerminalSession: Identifiable, Codable, Hashable {
    let id: String
    let workingDir: String
    var isActive: Bool
    var lastOutput: String
    var lastUpdate: Date
    var terminalType: TerminalType
    var name: String?
    var cursorAgentWorkingDir: String?
    
    // Hashable conformance - hash based on unique id
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Equatable conformance (required by Hashable)
    static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        return lhs.id == rhs.id
    }
    
    // Memberwise initializer
    init(
        id: String,
        workingDir: String,
        isActive: Bool = true,
        lastOutput: String = "",
        lastUpdate: Date = Date(),
        terminalType: TerminalType = .regular,
        name: String? = nil,
        cursorAgentWorkingDir: String? = nil
    ) {
        self.id = id
        self.workingDir = workingDir
        self.isActive = isActive
        self.lastOutput = lastOutput
        self.lastUpdate = lastUpdate
        self.terminalType = terminalType
        self.name = name
        self.cursorAgentWorkingDir = cursorAgentWorkingDir
    }
    
    // Custom decoding to handle optional fields from API
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        workingDir = try container.decode(String.self, forKey: .workingDir)
        isActive = (try? container.decode(Bool.self, forKey: .isActive)) ?? true
        lastOutput = (try? container.decode(String.self, forKey: .lastOutput)) ?? ""
        lastUpdate = (try? container.decode(Date.self, forKey: .lastUpdate)) ?? Date()
        
        // Decode terminal type, default to regular if not present
        if let typeString = try? container.decode(String.self, forKey: .terminalType),
           let type = TerminalType(rawValue: typeString) {
            terminalType = type
        } else {
            terminalType = .regular
        }
        
        name = try? container.decode(String.self, forKey: .name)
        cursorAgentWorkingDir = try? container.decode(String.self, forKey: .cursorAgentWorkingDir)
    }
    
    // Custom encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(workingDir, forKey: .workingDir)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(lastOutput, forKey: .lastOutput)
        try container.encode(lastUpdate, forKey: .lastUpdate)
        try container.encode(terminalType.rawValue, forKey: .terminalType)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(cursorAgentWorkingDir, forKey: .cursorAgentWorkingDir)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case workingDir
        case isActive
        case lastOutput
        case lastUpdate
        case terminalType
        case name
        case cursorAgentWorkingDir
    }
}

