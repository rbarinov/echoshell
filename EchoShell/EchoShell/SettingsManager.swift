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
            // Автоматическая синхронизация при изменении
            syncToWatch()
            // Notify AudioRecorder about API key change
            NotificationCenter.default.post(name: NSNotification.Name("APIKeyChanged"), object: nil)
        }
    }
    
    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet {
            UserDefaults.standard.set(transcriptionLanguage.rawValue, forKey: "transcriptionLanguage")
            print("📱 SettingsManager: Language updated to: \(transcriptionLanguage.displayName)")
            // Автоматическая синхронизация при изменении
            syncToWatch()
            // Notify AudioRecorder about language change
            NotificationCenter.default.post(name: NSNotification.Name("LanguageChanged"), object: nil)
        }
    }
    
    // NEW: Add laptop mode properties
    @Published var operationMode: OperationMode {
        didSet {
            UserDefaults.standard.set(operationMode.rawValue, forKey: "operationMode")
            print("📱 SettingsManager: Operation mode changed to: \(operationMode.displayName)")
            syncToWatch()
        }
    }
    
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
    
    // NEW: Computed property
    var isLaptopMode: Bool {
        return operationMode == .laptop && laptopConfig != nil
    }
    
    // NEW: Key refresh check
    func shouldRefreshKeys() -> Bool {
        guard let expiresAt = keyExpiresAt else { return true }
        return Date().addingTimeInterval(300) >= expiresAt // 5 minutes before expiry
    }
    
    init() {
        // Load API key from UserDefaults (user-entered in standalone mode)
        // In laptop mode, ephemeral keys are used instead
        self.apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        
        if let languageCode = UserDefaults.standard.string(forKey: "transcriptionLanguage"),
           let language = TranscriptionLanguage(rawValue: languageCode) {
            self.transcriptionLanguage = language
        } else {
            self.transcriptionLanguage = .auto // По умолчанию авто-определение (ru, en, ka)
        }
        
        // NEW: Load laptop config
        if let data = UserDefaults.standard.data(forKey: "laptopConfig"),
           let config = try? JSONDecoder().decode(TunnelConfig.self, from: data) {
            self.laptopConfig = config
        }
        
        let modeRaw = UserDefaults.standard.string(forKey: "operationMode") ?? "standalone"
        self.operationMode = OperationMode(rawValue: modeRaw) ?? .standalone
        
        // Load ephemeral keys from Keychain
        self.ephemeralKeys = SecureKeyStore.shared.load()
        if let timestamp = UserDefaults.standard.object(forKey: "keyExpiresAt") as? TimeInterval {
            self.keyExpiresAt = Date(timeIntervalSince1970: timestamp)
        }
        
        print("📱 SettingsManager: Initialized with API key length: \(self.apiKey.count)")
        print("📱 SettingsManager: Language: \(self.transcriptionLanguage.displayName)")
        print("📱 SettingsManager: Operation mode: \(self.operationMode.displayName)")
    }
    
    private func syncToWatch() {
        WatchConnectivityManager.shared.updateContext(apiKey: apiKey, language: transcriptionLanguage.rawValue, laptopConfig: laptopConfig)
    }
}

enum OperationMode: String, CaseIterable, Identifiable {
    case standalone = "standalone"
    case laptop = "laptop"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .standalone:
            return "Standalone (Direct OpenAI)"
        case .laptop:
            return "Laptop Mode (Terminal Control)"
        }
    }
    
    var icon: String {
        switch self {
        case .standalone:
            return "iphone"
        case .laptop:
            return "laptopcomputer"
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
            return "Auto (Русский, English, ქართული)"
        case .russian:
            return "Русский"
        case .english:
            return "English"
        case .georgian:
            return "ქართული (Georgian)"
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
            return nil // Whisper автоматически определит язык
        case .russian:
            return "ru"
        case .english:
            return "en"
        case .georgian:
            return "ka"
        }
    }
}

