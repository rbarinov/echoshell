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
        self.config = config
        self.sessionId = sessionId
        self.onMessageCallback = onMessage
        
        let wsUrlString = "\(config.wsUrl)/api/\(config.tunnelId)/recording/\(sessionId)/stream"
        guard let url = URL(string: wsUrlString) else {
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
        
        Task { @MainActor in
            self.isConnected = true
            self.connectionState = .connecting
        }
        reconnectAttempts = 0
        lastPongReceived = Date()
        
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
        print("📨📨📨 RecordingStreamClient received raw message: \(text.prefix(200))")
        
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(RecordingStreamMessage.self, from: data) else {
            print("❌❌❌ RecordingStreamClient: Failed to parse message")
            return
        }
        
        print("📨📨📨 RecordingStreamClient parsed message: type=\(message.type), session_id=\(message.session_id), text=\(message.text.count) chars, delta=\(message.delta?.count ?? 0) chars, isComplete=\(message.isComplete?.description ?? "nil")")
        
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

