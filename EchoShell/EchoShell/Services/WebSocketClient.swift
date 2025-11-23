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
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var config: TunnelConfig?
    private var sessionId: String?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var onMessageCallback: ((String) -> Void)?
    
    func connect(config: TunnelConfig, sessionId: String, onMessage: ((String) -> Void)? = nil) {
        self.onMessageCallback = onMessage
        self.config = config
        self.sessionId = sessionId
        
        let wsUrlString = "\(config.wsUrl)/api/\(config.tunnelId)/terminal/\(sessionId)/stream"
        guard let url = URL(string: wsUrlString) else {
            Task { @MainActor in
                self.connectionError = "Invalid WebSocket URL"
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(UIDevice.current.identifierForVendor?.uuidString ?? "", forHTTPHeaderField: "X-Device-ID")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        Task { @MainActor in
            self.isConnected = true
        }
        reconnectAttempts = 0
        
        print("📡 WebSocket connecting to: \(wsUrlString)")
        
        receiveMessage()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        Task { @MainActor in
            self.isConnected = false
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
                }
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
    
    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("❌ Max reconnect attempts reached")
            return
        }
        
        reconnectAttempts += 1
        let delay = pow(2.0, Double(reconnectAttempts)) // Exponential backoff
        
        print("🔄 Attempting reconnect #\(reconnectAttempts) in \(delay)s...")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let config = self.config,
                  let sessionId = self.sessionId else {
                return
            }
            
            self.connect(config: config, sessionId: sessionId)
        }
    }
}
