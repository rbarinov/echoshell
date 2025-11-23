//
//  SettingsManager.swift
//  EchoShell
//
//  Created by Roman Barinov on 2025.11.21.
//

import Foundation

class SettingsManager: ObservableObject {
    // EXISTING: Keep all current properties
    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "apiKey")
            print("📱 SettingsManager: API key updated, length: \(apiKey.count)")
            // Automatic sync on change
            syncToWatch()
            // Notify AudioRecorder about API key change
            NotificationCenter.default.post(name: NSNotification.Name("APIKeyChanged"), object: nil)
        }
    }
    
    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet {
            UserDefaults.standard.set(transcriptionLanguage.rawValue, forKey: "transcriptionLanguage")
            print("📱 SettingsManager: Language updated to: \(transcriptionLanguage.displayName)")
            // Automatic sync on change
            syncToWatch()
            // Notify AudioRecorder about language change
            NotificationCenter.default.post(name: NSNotification.Name("LanguageChanged"), object: nil)
        }
    }
    
    // Laptop mode properties
    @Published var laptopConfig: TunnelConfig? {
        didSet {
            if let config = laptopConfig {
                if let encoded = try? JSONEncoder().encode(config) {
                    UserDefaults.standard.set(encoded, forKey: "laptopConfig")
                    print("📱 SettingsManager: Laptop config saved")
                }
            } else {
                UserDefaults.standard.removeObject(forKey: "laptopConfig")
                print("📱 SettingsManager: Laptop config cleared")
            }
            syncToWatch()
        }
    }
    
    @Published var ephemeralKeys: KeyResponse.Keys? {
        didSet {
            // Store in Keychain (more secure than UserDefaults)
            if let keys = ephemeralKeys {
                if let expiresAt = keyExpiresAt {
                    SecureKeyStore.shared.save(keys, expiresAt: expiresAt)
                }
            } else {
                SecureKeyStore.shared.clear()
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
    
    // Command execution mode
    @Published var commandMode: CommandMode {
        didSet {
            UserDefaults.standard.set(commandMode.rawValue, forKey: "commandMode")
            print("📱 SettingsManager: Command mode updated to: \(commandMode.displayName)")
        }
    }
    
    // Selected terminal session ID
    @Published var selectedSessionId: String? {
        didSet {
            if let sessionId = selectedSessionId {
                UserDefaults.standard.set(sessionId, forKey: "selectedSessionId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedSessionId")
            }
            print("📱 SettingsManager: Selected session updated: \(selectedSessionId ?? "none")")
        }
    }
    
    // Last terminal output for direct mode display
    @Published var lastTerminalOutput: String = ""
    
    // Key refresh check
    func shouldRefreshKeys() -> Bool {
        guard let expiresAt = keyExpiresAt else { return true }
        return Date().addingTimeInterval(300) >= expiresAt // 5 minutes before expiry
    }
    
    init() {
        // API key is only used for legacy purposes, ephemeral keys from laptop are used instead
        self.apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        
        if let languageCode = UserDefaults.standard.string(forKey: "transcriptionLanguage"),
           let language = TranscriptionLanguage(rawValue: languageCode) {
            self.transcriptionLanguage = language
        } else {
            self.transcriptionLanguage = .auto // Default to auto-detection (ru, en, ka)
        }
        
        // Load laptop config
        if let data = UserDefaults.standard.data(forKey: "laptopConfig"),
           let config = try? JSONDecoder().decode(TunnelConfig.self, from: data) {
            self.laptopConfig = config
        }
        
        // Load ephemeral keys from Keychain
        self.ephemeralKeys = SecureKeyStore.shared.load()
        if let timestamp = UserDefaults.standard.object(forKey: "keyExpiresAt") as? TimeInterval {
            self.keyExpiresAt = Date(timeIntervalSince1970: timestamp)
        }
        
        // Load command mode
        if let modeRaw = UserDefaults.standard.string(forKey: "commandMode"),
           let mode = CommandMode(rawValue: modeRaw) {
            self.commandMode = mode
        } else {
            self.commandMode = .agent // Default to agent mode
        }
        
        // Load selected session
        self.selectedSessionId = UserDefaults.standard.string(forKey: "selectedSessionId")
        
        print("📱 SettingsManager: Initialized with API key length: \(self.apiKey.count)")
        print("📱 SettingsManager: Language: \(self.transcriptionLanguage.displayName)")
        print("📱 SettingsManager: Command mode: \(self.commandMode.displayName)")
        print("📱 SettingsManager: Operation mode: Laptop Mode (Terminal Control)")
    }
    
    private func syncToWatch() {
        // Only sync if Watch app is installed (silently skip if not)
        if WatchConnectivityManager.shared.isWatchAppInstalled {
            WatchConnectivityManager.shared.updateContext(apiKey: apiKey, language: transcriptionLanguage.rawValue, laptopConfig: laptopConfig)
        }
    }
}

enum CommandMode: String, CaseIterable, Identifiable {
    case agent = "agent"
    case direct = "direct"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .agent:
            return "AI Agent"
        case .direct:
            return "Direct Terminal"
        }
    }
    
    var description: String {
        switch self {
        case .agent:
            return "AI Agent: answers questions, manages terminals (create/delete/navigate)"
        case .direct:
            return "Direct Terminal: commands are executed directly in the terminal"
        }
    }
    
    var icon: String {
        switch self {
        case .agent:
            return "brain.head.profile"
        case .direct:
            return "terminal"
        }
    }
}

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case auto = "auto"
    case russian = "ru"
    case english = "en"
    case georgian = "ka"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .auto:
            return "Auto (Russian, English, Georgian)"
        case .russian:
            return "Russian"
        case .english:
            return "English"
        case .georgian:
            return "Georgian"
        }
    }
    
    var flag: String {
        switch self {
        case .auto:
            return "🌐"
        case .russian:
            return "🇷🇺"
        case .english:
            return "🇬🇧"
        case .georgian:
            return "🇬🇪"
        }
    }
    
    var whisperCode: String? {
        switch self {
        case .auto:
            return nil // Whisper will automatically detect language
        case .russian:
            return "ru"
        case .english:
            return "en"
        case .georgian:
            return "ka"
        }
    }
}

