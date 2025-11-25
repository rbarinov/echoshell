//
//  WebSocketClient.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Handles WebSocket communication for terminal streaming
//

import Foundation
import UIKit

class WebSocketClient: ObservableObject {
    @Published var isConnected = false
    @Published var messages: [TerminalMessage] = []
    @Published var connectionError: String?
    @Published var connectionState: ConnectionState = .disconnected
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var config: TunnelConfig?
    private var sessionId: String?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var onMessageCallback: ((String) -> Void)?
    
    // Heartbeat configuration
    private let pingInterval: TimeInterval = 20.0 // 20 seconds
    private let pongTimeout: TimeInterval = 30.0 // 30 seconds
    private var lastPongReceived: Date = Date()
    private var pingTimer: Timer?
    private var healthCheckTimer: Timer?
    
    func connect(config: TunnelConfig, sessionId: String, onMessage: ((String) -> Void)? = nil) {
        self.onMessageCallback = onMessage
        self.config = config
        self.sessionId = sessionId
        
        let wsUrlString = "\(config.wsUrl)/api/\(config.tunnelId)/terminal/\(sessionId)/stream"
        guard let url = URL(string: wsUrlString) else {
            Task { @MainActor in
                self.connectionError = "Invalid WebSocket URL"
                self.connectionState = .disconnected
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(UIDevice.current.identifierForVendor?.uuidString ?? "", forHTTPHeaderField: "X-Device-ID")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        Task { @MainActor in
            self.isConnected = true
            self.connectionState = .connecting
        }
        reconnectAttempts = 0
        lastPongReceived = Date()
        
        print("📡 WebSocket connecting to: \(wsUrlString)")
        
        setupHeartbeat()
        receiveMessage()
    }
    
    func disconnect() {
        cleanupHeartbeat()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        Task { @MainActor in
            self.isConnected = false
            self.connectionState = .disconnected
        }
        print("📡 WebSocket disconnected")
    }
    
    func sendInput(_ input: String) {
        guard isConnected, let webSocketTask = webSocketTask else {
            print("⚠️ Cannot send input - not connected")
            return
        }
        
        // Log input bytes for debugging
        let inputBytes = input.utf8.map { $0 }
        let inputDescription = input
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        print("📤 Sending input to terminal: '\(inputDescription)' (bytes: \(inputBytes))")
        
        // Send input as JSON message
        let message: [String: Any] = [
            "type": "input",
            "data": input
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask.send(.string(jsonString)) { error in
                if let error = error {
                    print("❌ Error sending input: \(error.localizedDescription)")
                } else {
                    print("✅ Input sent successfully")
                }
            }
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
                
                // Continue listening
                self.receiveMessage()
                
            case .failure(let error):
                print("❌ WebSocket error: \(error.localizedDescription)")
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
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
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        let type = json["type"] as? String ?? "output"
        let sessionId = json["session_id"] as? String ?? ""
        let messageData = json["data"] as? String ?? ""
        let timestamp = Date()
        
        let message = TerminalMessage(
            type: TerminalMessage.MessageType(rawValue: type) ?? .output,
            sessionId: sessionId,
            data: messageData,
            timestamp: timestamp
        )
        
        // Log message data for debugging
        print("📨 WebSocket message received: \(messageData.prefix(100))...")
        print("📨 Message data length: \(messageData.count) bytes")
        
        // Call callback on main thread for terminal display
        DispatchQueue.main.async {
            if let callback = self.onMessageCallback {
                print("📞 Calling onMessageCallback with \(messageData.count) bytes")
                callback(messageData)
            } else {
                print("⚠️ onMessageCallback is nil!")
            }
        }
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.messages.append(message)
            
            // Keep only last 100 messages
            if self.messages.count > 100 {
                self.messages.removeFirst(self.messages.count - 100)
            }
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
                        print("❌ Ping error: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Check for dead connections
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: pongTimeout, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let timeSinceLastPong = Date().timeIntervalSince(self.lastPongReceived)
            if timeSinceLastPong > self.pongTimeout {
                print("⚠️ WebSocket appears dead (no pong for \(timeSinceLastPong)s)")
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
            print("❌ Max reconnect attempts reached")
            Task { @MainActor in
                self.connectionState = .disconnected
            }
            return
        }
        
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Exponential backoff, max 30s
        
        print("🔄 Attempting reconnect #\(reconnectAttempts) in \(delay)s...")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.connectionState = .reconnecting
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let config = self.config,
                  let sessionId = self.sessionId else {
                return
            }
            
            self.connect(config: config, sessionId: sessionId)
        }
    }
}
