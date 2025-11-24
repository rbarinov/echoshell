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
}

class RecordingStreamClient: ObservableObject {
    @Published var isConnected = false
    @Published var connectionError: String?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var config: TunnelConfig?
    private var sessionId: String?
    private var onMessageCallback: ((RecordingStreamMessage) -> Void)?
    
    func connect(config: TunnelConfig, sessionId: String, onMessage: @escaping (RecordingStreamMessage) -> Void) {
        self.config = config
        self.sessionId = sessionId
        self.onMessageCallback = onMessage
        
        let wsUrlString = "\(config.wsUrl)/api/\(config.tunnelId)/recording/\(sessionId)/stream"
        guard let url = URL(string: wsUrlString) else {
            Task { @MainActor in
                self.connectionError = "Invalid recording stream URL"
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
        
        receiveMessage()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        Task { @MainActor in
            self.isConnected = false
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
                self.receiveMessage()
            case .failure(let error):
                print("❌ Recording stream error: \(error.localizedDescription)")
                Task { @MainActor in
                    self.isConnected = false
                    self.connectionError = error.localizedDescription
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(RecordingStreamMessage.self, from: data) else {
            return
        }
        
        DispatchQueue.main.async {
            self.onMessageCallback?(message)
        }
    }
}

