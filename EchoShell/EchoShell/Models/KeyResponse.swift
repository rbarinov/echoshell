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
    let providers: Providers?
    let endpoints: Endpoints?
    let config: Config?
    let expiresAt: Int
    let expiresIn: Int
    let permissions: [String]
    
    struct Keys: Codable {
        let stt: String
        let tts: String
    }
    
    struct Providers: Codable {
        let stt: String
        let tts: String
    }
    
    struct Endpoints: Codable {
        let stt: String
        let tts: String
    }
    
    struct Config: Codable {
        let stt: STTConfig?
        let tts: TTSConfig?
    }
    
    struct STTConfig: Codable {
        let baseUrl: String?
        let model: String
    }
    
    struct TTSConfig: Codable {
        let baseUrl: String?
        let model: String
        let voice: String
    }
    
    enum CodingKeys: String, CodingKey {
        case status
        case keys
        case providers
        case endpoints
        case config
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case permissions
    }
}
