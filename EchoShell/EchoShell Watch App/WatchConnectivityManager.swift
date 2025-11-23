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
    
    @Published var apiKey: String = ""
    @Published var transcriptionLanguage: String = "auto"
    @Published var isPhoneConnected = false
    
    private override init() {
        super.init()
        
        // Load saved values
        apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        transcriptionLanguage = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "auto"
        
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(apiKey, forKey: "apiKey")
        UserDefaults.standard.set(transcriptionLanguage, forKey: "transcriptionLanguage")
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
                print("📥 Watch: Found existing context on activation: \(context)")
                DispatchQueue.main.async {
                    if let apiKey = context["apiKey"] as? String {
                        self.apiKey = apiKey
                        print("   ✅ Loaded API key: \(apiKey.count) chars")
                    }
                    if let language = context["language"] as? String {
                        self.transcriptionLanguage = language
                        print("   ✅ Loaded language: \(language)")
                    }
                    self.saveSettings()
                }
            } else {
                print("⚠️ Watch: Application context data is nil")
                print("   Checking UserDefaults for cached settings...")
                if !self.apiKey.isEmpty {
                    print("   ✅ Found cached API key: \(self.apiKey.count) chars")
                    print("   ✅ Found cached language: \(self.transcriptionLanguage)")
                } else {
                    print("   ❌ No cached settings found")
                    print("   💡 Please open iPhone app to configure")
                }
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPhoneConnected = session.isReachable
        }
        print("iPhone reachability changed: \(session.isReachable)")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("📨 Watch: Received message from iPhone: \(message)")
        DispatchQueue.main.async {
            if let apiKey = message["apiKey"] as? String {
                self.apiKey = apiKey
                print("   ✅ Updated API key from message: \(apiKey.count) chars")
            }
            if let language = message["language"] as? String {
                self.transcriptionLanguage = language
                print("   ✅ Updated language from message: \(language)")
            }
            self.saveSettings()
            // Notify that settings changed
            NotificationCenter.default.post(name: NSNotification.Name("SettingsUpdated"), object: nil)
            print("   💾 Settings saved and notification sent")
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("📨 Watch: Received message with reply handler from iPhone")
        // Process the message
        DispatchQueue.main.async {
            if let apiKey = message["apiKey"] as? String {
                self.apiKey = apiKey
                print("   ✅ Updated API key from message: \(apiKey.count) chars")
            }
            if let language = message["language"] as? String {
                self.transcriptionLanguage = language
                print("   ✅ Updated language from message: \(language)")
            }
            self.saveSettings()
            // Notify that settings changed
            NotificationCenter.default.post(name: NSNotification.Name("SettingsUpdated"), object: nil)
            print("   💾 Settings saved and notification sent")
        }
        // Send reply
        replyHandler(["status": "received"])
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("Received context from iPhone: \(applicationContext)")
        DispatchQueue.main.async {
            if let apiKey = applicationContext["apiKey"] as? String {
                self.apiKey = apiKey
                print("Updated API key, length: \(apiKey.count)")
            }
            if let language = applicationContext["language"] as? String {
                self.transcriptionLanguage = language
                print("Updated language: \(language)")
            }
            self.saveSettings()
            // Notify that settings changed
            NotificationCenter.default.post(name: NSNotification.Name("SettingsUpdated"), object: nil)
        }
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

