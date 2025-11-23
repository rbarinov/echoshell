//
//  KeyResponse.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//

import Foundation

struct KeyResponse: Codable {
    let status: String
    let keys: Keys
    let expiresAt: Int
    let expiresIn: Int
    let permissions: [String]
    
    struct Keys: Codable {
        let openai: String
        let elevenlabs: String?
    }
    
    enum CodingKeys: String, CodingKey {
        case status
        case keys
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case permissions
    }
}
