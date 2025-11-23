//
//  WatchConnectivityManager.swift
//  EchoShell
//
//  Created by Roman Barinov on 2025.11.21.
//

import Foundation
import WatchConnectivity

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var isWatchConnected = false
    @Published var isWatchAppInstalled = false
    
    private override init() {
        super.init()
        
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    func sendSettings(apiKey: String, language: String = "auto") {
        guard WCSession.default.isReachable else {
            print("⚠️ iOS: Watch is not reachable, cannot send message")
            return
        }
        
        let message: [String: Any] = [
            "apiKey": apiKey,
            "language": language
        ]
        
        print("📨 iOS: Sending message to Watch (immediate)...")
        WCSession.default.sendMessage(message, replyHandler: { reply in
            print("✅ iOS: Message delivered successfully: \(reply)")
        }, errorHandler: { error in
            print("❌ iOS: Error sending message: \(error.localizedDescription)")
        })
    }
    
    func updateContext(apiKey: String, language: String = "auto", laptopConfig: TunnelConfig? = nil) {
        guard WCSession.default.activationState == .activated else {
            // Silently skip if not activated (Watch app might not be installed)
            return
        }
        
        // Only try to update context if Watch app is installed
        guard WCSession.default.isWatchAppInstalled else {
            // Silently skip if Watch app is not installed (this is normal)
            return
        }
        
        var context: [String: Any] = [
            "apiKey": apiKey,
            "language": language
        ]
        
        // Add laptop config if available
        if let config = laptopConfig,
           let configData = try? JSONEncoder().encode(config),
           let configDict = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
            context["laptopConfig"] = configDict
        }
        
        do {
            try WCSession.default.updateApplicationContext(context)
            print("✅ iOS: Context updated successfully")
            print("   Sent: apiKey=\(apiKey.count) chars, language=\(language)")
        } catch {
            // Only log if it's not the "not installed" error
            let errorDescription = error.localizedDescription
            if !errorDescription.contains("not installed") && !errorDescription.contains("WCErrorCodeWatchAppNotInstalled") {
                print("⚠️ iOS: Error updating context: \(errorDescription)")
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchConnected = session.isReachable
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
        
        if let error = error {
            print("❌ iOS: WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("✅ iOS: WCSession activated with state: \(activationState.rawValue)")
            print("   Watch reachable: \(session.isReachable)")
            print("   Watch app installed: \(session.isWatchAppInstalled)")
            
            // Send initial settings after activation (only if Watch app is installed)
            if activationState == .activated && session.isWatchAppInstalled {
                // Get current settings from UserDefaults
                let apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
                let language = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "auto"
                
                print("📤 iOS: Sending initial settings to Watch...")
                print("   API key length: \(apiKey.count)")
                print("   Language: \(language)")
                
                // Save language default if not exists
                if UserDefaults.standard.string(forKey: "transcriptionLanguage") == nil {
                    UserDefaults.standard.set(language, forKey: "transcriptionLanguage")
                    print("   Saved language to UserDefaults")
                }
                
                updateContext(apiKey: apiKey, language: language)
            } else if !session.isWatchAppInstalled {
                print("ℹ️ iOS: Watch app not installed, skipping context update")
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated")
        session.activate()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = session.isReachable
        }
        print("📡 iOS: Watch reachability changed: \(session.isReachable)")
        
        // When Watch becomes available - send settings (only if Watch app is installed)
        if session.isReachable && session.isWatchAppInstalled {
            print("📤 iOS: Watch just became reachable, sending settings...")
            
            let apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
            let language = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "auto"
            
            // Use sendMessage for immediate delivery
            sendSettings(apiKey: apiKey, language: language)
            
            // Also update context for reliability
            updateContext(apiKey: apiKey, language: language)
        }
    }
    
    // Receive messages from Watch
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("📥 iOS: Received message from Watch")
        
        // Check if it's a transcription stats message
        if let text = message["text"] as? String,
           let recordingDuration = message["recordingDuration"] as? TimeInterval,
           let transcriptionCost = message["transcriptionCost"] as? Double,
           let processingTime = message["processingTime"] as? TimeInterval,
           let uploadSize = message["uploadSize"] as? Int64,
           let downloadSize = message["downloadSize"] as? Int64 {
            
            print("   📊 Transcription stats received:")
            print("      Text: \(text.prefix(50))...")
            print("      Recording: \(recordingDuration)s")
            print("      Cost: $\(transcriptionCost)")
            print("      Processing: \(processingTime)s")
            print("      Upload: \(uploadSize) bytes, Download: \(downloadSize) bytes")
            
            // Post notification to update UI
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("TranscriptionStatsUpdated"),
                    object: nil,
                    userInfo: message
                )
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("📥 iOS: Received message with reply handler from Watch")
        
        // Check if it's a transcription stats message
        if let text = message["text"] as? String,
           let recordingDuration = message["recordingDuration"] as? TimeInterval,
           let transcriptionCost = message["transcriptionCost"] as? Double,
           let processingTime = message["processingTime"] as? TimeInterval,
           let uploadSize = message["uploadSize"] as? Int64,
           let downloadSize = message["downloadSize"] as? Int64 {
            
            print("   📊 Transcription stats received:")
            print("      Text: \(text.prefix(50))...")
            print("      Recording: \(recordingDuration)s")
            print("      Cost: $\(transcriptionCost)")
            print("      Processing: \(processingTime)s")
            print("      Upload: \(uploadSize) bytes, Download: \(downloadSize) bytes")
            
            // Post notification to update UI
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("TranscriptionStatsUpdated"),
                    object: nil,
                    userInfo: message
                )
            }
            
            // Reply to Watch
            replyHandler(["status": "received"])
        }
    }
}

