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

class RecordingStreamClient: ObservableObject {
    @Published var isConnected = false
    @Published var connectionError: String?
    @Published var connectionState: ConnectionState = .disconnected
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var config: TunnelConfig?
    private var sessionId: String?
    private var onMessageCallback: ((RecordingStreamMessage) -> Void)?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    
    // Heartbeat configuration
    private let pingInterval: TimeInterval = 20.0 // 20 seconds
    private let pongTimeout: TimeInterval = 30.0 // 30 seconds
    private var lastPongReceived: Date = Date()
    private var pingTimer: Timer?
    private var healthCheckTimer: Timer?
    
    func connect(config: TunnelConfig, sessionId: String, onMessage: @escaping (RecordingStreamMessage) -> Void) {
        print("🔌🔌🔌 RecordingStreamClient: connect called for sessionId=\(sessionId)")
        print("🔌🔌🔌 RecordingStreamClient: config.tunnelId=\(config.tunnelId), config.wsUrl=\(config.wsUrl)")
        
        self.config = config
        self.sessionId = sessionId
        self.onMessageCallback = onMessage
        
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
            case .failure:
                print("❌ Recording stream error: Connection failed")
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
        print("📨📨📨 RecordingStreamClient received raw message: \(text.prefix(500))")
        
        guard let data = text.data(using: .utf8) else {
            print("❌❌❌ RecordingStreamClient: Failed to convert text to data")
            return
        }
        
        // Try to parse as JSON first to see what we got
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("📨📨📨 RecordingStreamClient: Parsed JSON keys: \(json.keys.joined(separator: ", "))")
            print("📨📨📨 RecordingStreamClient: JSON isComplete value: \(json["isComplete"] ?? "nil"), type: \(type(of: json["isComplete"]))")
        }
        
        guard let message = try? JSONDecoder().decode(RecordingStreamMessage.self, from: data) else {
            print("❌❌❌ RecordingStreamClient: Failed to decode RecordingStreamMessage")
            if let error = try? JSONDecoder().decode(RecordingStreamMessage.self, from: data) {
                print("❌❌❌ This should not print")
            } else {
                print("❌❌❌ Decoding error details unavailable")
            }
            return
        }
        
        print("📨📨📨 RecordingStreamClient parsed message: type=\(message.type), session_id=\(message.session_id), text=\(message.text.count) chars, delta=\(message.delta?.count ?? 0) chars, isComplete=\(message.isComplete?.description ?? "nil")")
        print("📨📨📨 RecordingStreamClient: isComplete type: \(type(of: message.isComplete))")
        
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
            
            self.connect(config: config, sessionId: sessionId, onMessage: callback)
        }
    }
}

