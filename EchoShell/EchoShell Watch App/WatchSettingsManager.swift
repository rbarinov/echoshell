//
//  WatchSettingsManager.swift
//  EchoShell Watch App
//
//  Created for Voice-Controlled Terminal Management System
//  Manages all settings on Watch app (synced from iPhone)
//

import Foundation

// Models needed for Watch
struct TunnelConfig: Codable, Equatable {
    let tunnelId: String
    let tunnelUrl: String
    let wsUrl: String
    let keyEndpoint: String
    let authKey: String
    
    var apiBaseUrl: String {
        return "\(tunnelUrl)/api/\(tunnelId)"
    }
}

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

enum TranscriptionLanguage: String, CaseIterable {
    case auto = "auto"
    case russian = "ru"
    case english = "en"
    case georgian = "ka"
}

enum CommandMode: String, CaseIterable {
    case agent = "agent"
    case direct = "direct"
}

class WatchSettingsManager: ObservableObject {
    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "apiKey")
        }
    }
    
    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet {
            UserDefaults.standard.set(transcriptionLanguage.rawValue, forKey: "transcriptionLanguage")
        }
    }
    
    @Published var laptopConfig: TunnelConfig? {
        didSet {
            if let config = laptopConfig {
                if let encoded = try? JSONEncoder().encode(config) {
                    UserDefaults.standard.set(encoded, forKey: "laptopConfig")
                }
            } else {
                UserDefaults.standard.removeObject(forKey: "laptopConfig")
            }
        }
    }
    
    @Published var ephemeralKeys: KeyResponse.Keys? {
        didSet {
            if let keys = ephemeralKeys {
                if let encoded = try? JSONEncoder().encode(keys) {
                    UserDefaults.standard.set(encoded, forKey: "ephemeralKeys")
                }
            } else {
                UserDefaults.standard.removeObject(forKey: "ephemeralKeys")
            }
        }
    }
    
    @Published var keyExpiresAt: Date? {
        didSet {
            if let expiresAt = keyExpiresAt {
                UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: "keyExpiresAt")
            } else {
                UserDefaults.standard.removeObject(forKey: "keyExpiresAt")
            }
        }
    }
    
    @Published var commandMode: CommandMode {
        didSet {
            UserDefaults.standard.set(commandMode.rawValue, forKey: "commandMode")
        }
    }
    
    @Published var selectedSessionId: String? {
        didSet {
            if let sessionId = selectedSessionId {
                UserDefaults.standard.set(sessionId, forKey: "selectedSessionId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedSessionId")
            }
        }
    }
    
    @Published var ttsSpeed: Double {
        didSet {
            UserDefaults.standard.set(ttsSpeed, forKey: "ttsSpeed")
        }
    }
    
    init() {
        // Load from UserDefaults
        self.apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        
        if let languageCode = UserDefaults.standard.string(forKey: "transcriptionLanguage"),
           let language = TranscriptionLanguage(rawValue: languageCode) {
            self.transcriptionLanguage = language
        } else {
            self.transcriptionLanguage = .auto
        }
        
        if let data = UserDefaults.standard.data(forKey: "laptopConfig"),
           let config = try? JSONDecoder().decode(TunnelConfig.self, from: data) {
            self.laptopConfig = config
        }
        
        if let data = UserDefaults.standard.data(forKey: "ephemeralKeys"),
           let keys = try? JSONDecoder().decode(KeyResponse.Keys.self, from: data) {
            self.ephemeralKeys = keys
        }
        
        if let timestamp = UserDefaults.standard.object(forKey: "keyExpiresAt") as? TimeInterval {
            self.keyExpiresAt = Date(timeIntervalSince1970: timestamp)
        }
        
        if let modeRaw = UserDefaults.standard.string(forKey: "commandMode"),
           let mode = CommandMode(rawValue: modeRaw) {
            self.commandMode = mode
        } else {
            self.commandMode = .agent
        }
        
        self.selectedSessionId = UserDefaults.standard.string(forKey: "selectedSessionId")
        
        if UserDefaults.standard.object(forKey: "ttsSpeed") != nil {
            self.ttsSpeed = UserDefaults.standard.double(forKey: "ttsSpeed")
            self.ttsSpeed = max(0.8, min(2.0, self.ttsSpeed))
        } else {
            self.ttsSpeed = 1.2
        }
    }
    
    func shouldRefreshKeys() -> Bool {
        guard let expiresAt = keyExpiresAt else { return true }
        return Date().addingTimeInterval(300) >= expiresAt // 5 minutes before expiry
    }
}

