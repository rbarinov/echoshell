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
    
    func connect(config: TunnelConfig, sessionId: String) {
        self.config = config
        self.sessionId = sessionId
        
        let wsUrlString = "\(config.wsUrl)/api/\(config.tunnelId)/terminal/\(sessionId)/stream"
        guard let url = URL(string: wsUrlString) else {
            connectionError = "Invalid WebSocket URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(UIDevice.current.identifierForVendor?.uuidString ?? "", forHTTPHeaderField: "X-Device-ID")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        isConnected = true
        reconnectAttempts = 0
        
        print("📡 WebSocket connecting to: \(wsUrlString)")
        
        receiveMessage()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        print("📡 WebSocket disconnected")
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
                self.isConnected = false
                self.connectionError = error.localizedDescription
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
        
        DispatchQueue.main.async {
            self.messages.append(message)
            
            // Keep only last 100 messages
            if self.messages.count > 100 {
                self.messages.removeFirst(self.messages.count - 100)
            }
        }
        
        print("📨 WebSocket message received: \(messageData.prefix(50))...")
    }
    
    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("❌ Max reconnect attempts reached")
            return
        }
        
        reconnectAttempts += 1
        let delay = pow(2.0, Double(reconnectAttempts)) // Exponential backoff
        
        print("🔄 Attempting reconnect #\(reconnectAttempts) in \(delay)s...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self,
                  let config = self.config,
                  let sessionId = self.sessionId else {
                return
            }
            
            self.connect(config: config, sessionId: sessionId)
        }
    }
}
