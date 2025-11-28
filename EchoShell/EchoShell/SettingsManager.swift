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
            Task { @MainActor in
                EventBus.shared.apiKeyChangedPublisher.send()
            }
        }
    }
    
    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet {
            UserDefaults.standard.set(transcriptionLanguage.rawValue, forKey: "transcriptionLanguage")
            print("📱 SettingsManager: Language updated to: \(transcriptionLanguage.displayName)")
            // Automatic sync on change
            syncToWatch()
            // Notify AudioRecorder about language change
            Task { @MainActor in
                EventBus.shared.languageChangedPublisher.send()
            }
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
    
    @Published var providerEndpoints: KeyResponse.Endpoints? {
        didSet {
            if let endpoints = providerEndpoints,
               let encoded = try? JSONEncoder().encode(endpoints) {
                UserDefaults.standard.set(encoded, forKey: "providerEndpoints")
            } else {
                UserDefaults.standard.removeObject(forKey: "providerEndpoints")
            }
        }
    }
    
    @Published var providerConfig: KeyResponse.Config? {
        didSet {
            if let config = providerConfig,
               let encoded = try? JSONEncoder().encode(config) {
                UserDefaults.standard.set(encoded, forKey: "providerConfig")
            } else {
                UserDefaults.standard.removeObject(forKey: "providerConfig")
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
    
    // TTS enabled (default true) - when disabled, server won't synthesize TTS audio
    @Published var ttsEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(ttsEnabled, forKey: "ttsEnabled")
            print("📱 SettingsManager: TTS enabled updated to: \(ttsEnabled)")
        }
    }
    
    // TTS playback speed (0.7 to 1.2, default 1.0) - compatible with ElevenLabs API requirements
    private var isUpdatingTtsSpeed = false
    @Published var ttsSpeed: Double = 1.0 {
        didSet {
            // Prevent infinite recursion
            guard !isUpdatingTtsSpeed else { return }
            
            // Clamp to valid range (0.7-1.2 for ElevenLabs compatibility)
            let clampedSpeed = max(0.7, min(1.2, ttsSpeed))
            // Round to 1 decimal place to avoid floating point precision issues
            let roundedSpeed = round(clampedSpeed * 10) / 10
            
            if roundedSpeed != ttsSpeed {
                isUpdatingTtsSpeed = true
                ttsSpeed = roundedSpeed
                isUpdatingTtsSpeed = false
            }
            
            UserDefaults.standard.set(ttsSpeed, forKey: "ttsSpeed")
            print("📱 SettingsManager: TTS speed updated to: \(ttsSpeed)")
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
        
        // Load provider endpoints
        if let data = UserDefaults.standard.data(forKey: "providerEndpoints"),
           let endpoints = try? JSONDecoder().decode(KeyResponse.Endpoints.self, from: data) {
            self.providerEndpoints = endpoints
        }
        
        // Load provider config
        if let data = UserDefaults.standard.data(forKey: "providerConfig"),
           let config = try? JSONDecoder().decode(KeyResponse.Config.self, from: data) {
            self.providerConfig = config
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
        
        // Load TTS enabled (default true)
        if UserDefaults.standard.object(forKey: "ttsEnabled") != nil {
            self.ttsEnabled = UserDefaults.standard.bool(forKey: "ttsEnabled")
        } else {
            self.ttsEnabled = true // Default enabled
        }
        
        // Load TTS speed (default 1.0, range 0.7-1.2 for ElevenLabs compatibility)
        if UserDefaults.standard.object(forKey: "ttsSpeed") != nil {
            let loadedSpeed = UserDefaults.standard.double(forKey: "ttsSpeed")
            // Clamp to valid range (0.7-1.2) and round to 1 decimal place
            isUpdatingTtsSpeed = true
            ttsSpeed = round(max(0.7, min(1.2, loadedSpeed)) * 10) / 10
            isUpdatingTtsSpeed = false
        } else {
            isUpdatingTtsSpeed = true
            ttsSpeed = 1.0 // Default speed
            isUpdatingTtsSpeed = false
        }
        
        print("📱 SettingsManager: Initialized with API key length: \(self.apiKey.count)")
        print("📱 SettingsManager: Language: \(self.transcriptionLanguage.displayName)")
        print("📱 SettingsManager: Command mode: \(self.commandMode.displayName)")
        print("📱 SettingsManager: TTS enabled: \(self.ttsEnabled)")
        print("📱 SettingsManager: TTS speed: \(self.ttsSpeed)")
        print("📱 SettingsManager: Operation mode: Laptop Mode (Terminal Control)")
    }
    
    private func syncToWatch() {
        // Only sync if Watch app is installed (silently skip if not)
        if WatchConnectivityManager.shared.isWatchAppInstalled {
            WatchConnectivityManager.shared.updateContext(apiKey: apiKey, language: transcriptionLanguage.rawValue, laptopConfig: laptopConfig, settingsManager: self)
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
            return "Auto (Russian, English)"
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

