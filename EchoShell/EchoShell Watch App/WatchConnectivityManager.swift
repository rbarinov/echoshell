//
//  WatchConnectivityManager.swift
//  EchoShell Watch App
//
//  Created by Roman Barinov on 2025.11.21.
//

import Foundation
import WatchConnectivity

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var isPhoneConnected = false
    
    private let settingsManager: WatchSettingsManager
    
    private override init() {
        // Initialize settings manager first
        self.settingsManager = WatchSettingsManager()
        super.init()
        
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    // Expose settings manager
    var settings: WatchSettingsManager {
        return settingsManager
    }
    
    // Legacy properties for backward compatibility
    var apiKey: String {
        get { settingsManager.apiKey }
        set { settingsManager.apiKey = newValue }
    }
    
    var transcriptionLanguage: String {
        get { settingsManager.transcriptionLanguage.rawValue }
        set { 
            if let lang = TranscriptionLanguage(rawValue: newValue) {
                settingsManager.transcriptionLanguage = lang
            }
        }
    }
    
    private func updateSettings(from context: [String: Any]) {
        DispatchQueue.main.async {
            // Update ephemeral keys first (priority)
            if let keysDict = context["ephemeralKeys"] as? [String: Any],
               let keysData = try? JSONSerialization.data(withJSONObject: keysDict),
               let keys = try? JSONDecoder().decode(KeyResponse.Keys.self, from: keysData) {
                self.settingsManager.ephemeralKeys = keys
                // Set apiKey from ephemeral keys for backward compatibility
                self.settingsManager.apiKey = keys.openai
                print("✅ Watch: Updated ephemeral keys and apiKey")
            } else if let apiKey = context["apiKey"] as? String, !apiKey.isEmpty {
                // Fallback to apiKey if ephemeral keys not available
                self.settingsManager.apiKey = apiKey
                print("✅ Watch: Updated apiKey (fallback)")
            }
            
            if let language = context["language"] as? String,
               let lang = TranscriptionLanguage(rawValue: language) {
                self.settingsManager.transcriptionLanguage = lang
            }
            if let configDict = context["laptopConfig"] as? [String: Any],
               let configData = try? JSONSerialization.data(withJSONObject: configDict),
               let config = try? JSONDecoder().decode(TunnelConfig.self, from: configData) {
                self.settingsManager.laptopConfig = config
            }
            if let expiresAt = context["keyExpiresAt"] as? TimeInterval {
                self.settingsManager.keyExpiresAt = Date(timeIntervalSince1970: expiresAt)
            }
            if let modeRaw = context["commandMode"] as? String,
               let mode = CommandMode(rawValue: modeRaw) {
                self.settingsManager.commandMode = mode
            }
            if let sessionId = context["selectedSessionId"] as? String {
                self.settingsManager.selectedSessionId = sessionId
            }
            if let speed = context["ttsSpeed"] as? Double {
                self.settingsManager.ttsSpeed = max(0.8, min(2.0, speed))
            }
            
            // Notify that settings changed
            NotificationCenter.default.post(name: NSNotification.Name("SettingsUpdated"), object: nil)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isPhoneConnected = session.isReachable
        }
        
        if let error = error {
            print("❌ Watch: WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("✅ Watch: WCSession activated with state: \(activationState.rawValue)")
            print("   iPhone reachable: \(session.isReachable)")
            
            // Check for existing context after activation
            let context = session.applicationContext
            if !context.isEmpty {
                print("📥 Watch: Found existing context on activation")
                self.updateSettings(from: context)
                print("   ✅ Loaded all settings from context")
            } else {
                print("⚠️ Watch: Application context data is nil")
                print("   Checking UserDefaults for cached settings...")
                if !self.settingsManager.apiKey.isEmpty {
                    print("   ✅ Found cached settings")
                } else {
                    print("   ❌ No cached settings found")
                    print("   💡 Please open iPhone app to configure")
                }
            }
        }
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("⚠️ Watch: WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("⚠️ Watch: WCSession deactivated, reactivating...")
        session.activate()
    }
    #endif
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPhoneConnected = session.isReachable
        }
        print("iPhone reachability changed: \(session.isReachable)")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("📨 Watch: Received message from iPhone")
        updateSettings(from: message)
        print("   💾 Settings updated and notification sent")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("📨 Watch: Received message with reply handler from iPhone")
        updateSettings(from: message)
        print("   💾 Settings updated and notification sent")
        // Send reply
        replyHandler(["status": "received"])
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("📥 Watch: Received application context from iPhone")
        updateSettings(from: applicationContext)
        print("   💾 Settings updated from context")
    }
    
    // Send transcription statistics to iPhone
    func sendTranscriptionStats(text: String, recordingDuration: TimeInterval, transcriptionCost: Double, processingTime: TimeInterval, uploadSize: Int64, downloadSize: Int64) {
        guard WCSession.default.activationState == .activated else {
            print("⚠️ Watch: WCSession not activated, cannot send stats")
            return
        }
        
        let stats: [String: Any] = [
            "text": text,
            "recordingDuration": recordingDuration,
            "transcriptionCost": transcriptionCost,
            "processingTime": processingTime,
            "uploadSize": uploadSize,
            "downloadSize": downloadSize
        ]
        
        print("📤 Watch: Preparing to send transcription stats...")
        print("   Text length: \(text.count) chars")
        print("   Recording: \(recordingDuration)s")
        print("   Cost: $\(transcriptionCost)")
        print("   Processing: \(processingTime)s")
        print("   Upload: \(uploadSize) bytes, Download: \(downloadSize) bytes")
        print("   iPhone reachable: \(WCSession.default.isReachable)")
        
        // Try to send immediately if reachable
        if WCSession.default.isReachable {
            print("📨 Watch: Sending message to iPhone...")
            WCSession.default.sendMessage(stats, replyHandler: { reply in
                print("✅ Watch: Stats delivered to iPhone, reply: \(reply)")
            }) { error in
                print("❌ Watch: Error sending stats: \(error.localizedDescription)")
            }
        } else {
            print("⚠️ Watch: iPhone not reachable, stats not sent")
            print("   Try to keep iPhone app open and Watch nearby")
        }
    }
}

