//
//  SecureKeyStore.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Manages ephemeral API keys in iOS Keychain
//

import Foundation
import Security

class SecureKeyStore {
    static let shared = SecureKeyStore()
    
    private let service = "com.roman.terminalcontrol"
    private let openAIKeyAccount = "ephemeral_openai_key"
    private let expirationAccount = "key_expiration"
    
    private init() {}
    
    func save(_ keys: KeyResponse.Keys, expiresAt: Date) {
        // Save OpenAI key
        saveToKeychain(account: openAIKeyAccount, value: keys.openai)
        
        // Save expiration date
        let timestamp = String(expiresAt.timeIntervalSince1970)
        saveToKeychain(account: expirationAccount, value: timestamp)
        
        print("🔐 SecureKeyStore: Keys saved to Keychain")
        print("   Expires at: \(expiresAt)")
    }
    
    func load() -> KeyResponse.Keys? {
        guard let openAIKey = loadFromKeychain(account: openAIKeyAccount) else {
            return nil
        }
        
        return KeyResponse.Keys(openai: openAIKey, elevenlabs: nil)
    }
    
    func getExpirationDate() -> Date? {
        guard let timestampStr = loadFromKeychain(account: expirationAccount),
              let timestamp = TimeInterval(timestampStr) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }
    
    func clear() {
        deleteFromKeychain(account: openAIKeyAccount)
        deleteFromKeychain(account: expirationAccount)
        print("🔐 SecureKeyStore: Keys cleared from Keychain")
    }
    
    // MARK: - Keychain Helpers
    
    private func saveToKeychain(account: String, value: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("❌ Keychain save error: \(status)")
        }
    }
    
    private func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    private func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
