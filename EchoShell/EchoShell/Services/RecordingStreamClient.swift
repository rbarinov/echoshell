//
//  RecordingStreamClient.swift
//  EchoShell
//
//  Streams cleaned recording output from the backend.
//

import Foundation
import UIKit

struct RecordingStreamMessage: Codable {
    let type: String
    let session_id: String
    let text: String
    let delta: String?
    let raw: String?
    let timestamp: TimeInterval?
    let isComplete: Bool?
}

// TTS Ready event (for new architecture - accumulated assistant messages)
struct TTSReadyEvent: Codable {
    let type: String
    let session_id: String
    let text: String
    let timestamp: Int64
}

class RecordingStreamClient: ObservableObject {
    @Published var isConnected = false
    @Published var connectionError: String?
    @Published var connectionState: ConnectionState = .disconnected
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var config: TunnelConfig?
    private var sessionId: String?
    private var onMessageCallback: ((RecordingStreamMessage) -> Void)?
    private var onTTSReadyCallback: ((String) -> Void)? // For tts_ready events
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    
    // Heartbeat configuration
    private let pingInterval: TimeInterval = 20.0 // 20 seconds
    private let pongTimeout: TimeInterval = 30.0 // 30 seconds
    private var lastPongReceived: Date = Date()
    private var pingTimer: Timer?
    private var healthCheckTimer: Timer?
    
    func connect(config: TunnelConfig, sessionId: String, onMessage: @escaping (RecordingStreamMessage) -> Void, onTTSReady: ((String) -> Void)? = nil) {
        print("🔌🔌🔌 RecordingStreamClient: connect called for sessionId=\(sessionId)")
        print("🔌🔌🔌 RecordingStreamClient: config.tunnelId=\(config.tunnelId), config.wsUrl=\(config.wsUrl)")
        
        self.config = config
        self.sessionId = sessionId
        self.onMessageCallback = onMessage
        self.onTTSReadyCallback = onTTSReady
        
        let wsUrlString = "\(config.wsUrl)/api/\(config.tunnelId)/recording/\(sessionId)/stream"
        print("🔌🔌🔌 RecordingStreamClient: WebSocket URL: \(wsUrlString)")
        
        guard let url = URL(string: wsUrlString) else {
            print("❌❌❌ RecordingStreamClient: Invalid URL: \(wsUrlString)")
            Task { @MainActor in
                self.connectionError = "Invalid recording stream URL"
                self.connectionState = .disconnected
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(UIDevice.current.identifierForVendor?.uuidString ?? "", forHTTPHeaderField: "X-Device-ID")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        print("🔌🔌🔌 RecordingStreamClient: WebSocket task created and resumed")
        
        Task { @MainActor in
            self.isConnected = true
            self.connectionState = .connecting
            print("🔌🔌🔌 RecordingStreamClient: Connection state set to connecting")
        }
        reconnectAttempts = 0
        lastPongReceived = Date()
        
        setupHeartbeat()
        receiveMessage()
        print("🔌🔌🔌 RecordingStreamClient: Heartbeat setup and receiveMessage started")
    }
    
    func disconnect() {
        cleanupHeartbeat()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        Task { @MainActor in
            self.isConnected = false
            self.connectionState = .disconnected
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                // Update last pong on any message (indicates connection is alive)
                self.lastPongReceived = Date()
                if self.connectionState == .dead {
                    Task { @MainActor in
                        self.connectionState = .connected
                    }
                }
                
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()
            case .failure(let error):
                print("❌ Recording stream error: \(error.localizedDescription)")
                Task { @MainActor in
                    self.isConnected = false
                    self.connectionError = error.localizedDescription
                    self.connectionState = .disconnected
                }
                self.cleanupHeartbeat()
                self.attemptReconnect()
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        print("📨 RecordingStreamClient: Received raw message: \(text.prefix(200))...")
        
        guard let data = text.data(using: .utf8) else {
            print("❌❌❌ RecordingStreamClient: Failed to convert text to data")
            return
        }
        
        // Try to parse as JSON first
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌❌❌ RecordingStreamClient: Failed to parse JSON")
            return
        }
        
        let messageType = json["type"] as? String ?? ""
        
        // Handle tts_ready event (new architecture)
        if messageType == "tts_ready" {
            do {
                let ttsEvent = try JSONDecoder().decode(TTSReadyEvent.self, from: data)
                print("🎙️ RecordingStreamClient: tts_ready event received with \(ttsEvent.text.count) chars")
                
                DispatchQueue.main.async {
                    self.onTTSReadyCallback?(ttsEvent.text)
                }
                return // IMPORTANT: Return early to prevent processing as legacy message
            } catch {
                print("❌❌❌ RecordingStreamClient: Failed to decode TTSReadyEvent: \(error)")
                // Continue to legacy format handling
            }
        }
        
        // Handle legacy RecordingStreamMessage format
        guard let message = try? JSONDecoder().decode(RecordingStreamMessage.self, from: data) else {
            print("❌❌❌ RecordingStreamClient: Failed to decode RecordingStreamMessage")
            return
        }
        
        print("📨📨📨 RecordingStreamClient parsed message: type=\(message.type), session_id=\(message.session_id), text=\(message.text.count) chars, delta=\(message.delta?.count ?? 0) chars, isComplete=\(message.isComplete?.description ?? "nil")")
        
        // If message is complete and we have tts_ready callback, use it (for backward compatibility)
        // BUT: Only if we haven't already processed a tts_ready event (prevent duplicates)
        if message.isComplete == true, let ttsCallback = onTTSReadyCallback {
            // Check if this is a legacy format that should trigger TTS
            // Only trigger if message type is not already "tts_ready" (to prevent double processing)
            if messageType != "tts_ready" {
                print("🎙️ RecordingStreamClient: Legacy isComplete=true, triggering tts_ready callback")
                DispatchQueue.main.async {
                    ttsCallback(message.text)
                }
            } else {
                print("⚠️ RecordingStreamClient: Skipping legacy TTS callback (already processed tts_ready event)")
            }
        }
        
        DispatchQueue.main.async {
            self.onMessageCallback?(message)
        }
    }
    
    private func setupHeartbeat() {
        cleanupHeartbeat()
        
        // Send periodic pings
        pingTimer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            guard let self = self, let task = self.webSocketTask else { return }
            if task.state == .running {
                task.sendPing { error in
                    if let error = error {
                        print("❌ Recording stream ping error: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Check for dead connections
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: pongTimeout, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let timeSinceLastPong = Date().timeIntervalSince(self.lastPongReceived)
            if timeSinceLastPong > self.pongTimeout {
                print("⚠️ Recording stream appears dead (no pong for \(timeSinceLastPong)s)")
                Task { @MainActor in
                    self.connectionState = .dead
                    self.isConnected = false
                }
                self.cleanupHeartbeat()
                self.webSocketTask?.cancel()
                self.attemptReconnect()
            }
        }
    }
    
    private func cleanupHeartbeat() {
        pingTimer?.invalidate()
        pingTimer = nil
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }
    
    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("❌ Max reconnect attempts reached for recording stream")
            Task { @MainActor in
                self.connectionState = .disconnected
            }
            return
        }
        
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Exponential backoff, max 30s
        
        print("🔄 Attempting recording stream reconnect #\(reconnectAttempts) in \(delay)s...")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.connectionState = .reconnecting
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let config = self.config,
                  let sessionId = self.sessionId,
                  let callback = self.onMessageCallback else {
                return
            }
            
            self.connect(config: config, sessionId: sessionId, onMessage: callback, onTTSReady: self.onTTSReadyCallback)
        }
    }
}

