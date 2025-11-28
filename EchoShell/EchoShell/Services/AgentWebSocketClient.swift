/**
 * Unified Agent WebSocket Client
 * 
 * Connects to tunnel server's unified /agent/ws endpoint
 * Handles all AgentEvent communication for both Supervisor and Headless agents
 */

import Foundation
import Combine

class AgentWebSocketClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isConnected: Bool = false
    @Published private(set) var connectionError: String?
    
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession!
    private let sessionId: String
    private let tunnelConfig: TunnelConfig
    
    // Event publisher for received events
    let eventPublisher = PassthroughSubject<AgentEvent, Never>()
    
    private var reconnectTimer: Timer?
    private var shouldReconnect = true
    private let maxReconnectDelay: TimeInterval = 30.0
    private var currentReconnectDelay: TimeInterval = 1.0
    
    init(sessionId: String, tunnelConfig: TunnelConfig) {
        self.sessionId = sessionId
        self.tunnelConfig = tunnelConfig
        super.init()
        
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - Connection Management
    
    func connect() {
        guard !isConnected else { return }
        
        // Build WebSocket URL: wss://tunnel-server/api/{tunnelId}/agent/ws?session_id={sessionId}
        var urlComponents = URLComponents(string: tunnelConfig.apiBaseUrl)!
        urlComponents.scheme = urlComponents.scheme == "https" ? "wss" : "ws"
        urlComponents.path = urlComponents.path + "/agent/ws"
        urlComponents.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId)
        ]
        
        guard let url = urlComponents.url else {
            connectionError = "Invalid WebSocket URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(tunnelConfig.authKey)", forHTTPHeaderField: "Authorization")
        
        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()
        
        receiveMessage()
        
        print("AgentWebSocketClient: Connecting to \(url)")
    }
    
    func disconnect() {
        shouldReconnect = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
    }
    
    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: currentReconnectDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("AgentWebSocketClient: Attempting reconnect...")
            self.connect()
            
            // Exponential backoff
            self.currentReconnectDelay = min(self.currentReconnectDelay * 2, self.maxReconnectDelay)
        }
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionError = nil
            self.currentReconnectDelay = 1.0
            print("AgentWebSocketClient: Connected to session \(self.sessionId)")
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            print("AgentWebSocketClient: Disconnected (code: \(closeCode.rawValue))")
            
            if self.shouldReconnect {
                self.scheduleReconnect()
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.isConnected = false
                self.connectionError = error.localizedDescription
                print("AgentWebSocketClient: Error - \(error.localizedDescription)")
                
                if self.shouldReconnect {
                    self.scheduleReconnect()
                }
            }
        }
    }
    
    // MARK: - Send Events
    
    func sendTextCommand(_ text: String) {
        let event = CommandTextEvent(sessionId: sessionId, text: text).toAgentEvent()
        sendEvent(event)
    }
    
    func sendVoiceCommand(audioData: Data, format: String = "m4a") {
        let audioBase64 = audioData.base64EncodedString()
        let event = CommandVoiceEvent(
            sessionId: sessionId,
            audioBase64: audioBase64,
            format: format
        ).toAgentEvent()
        sendEvent(event)
    }
    
    func resetContext() {
        let event = ContextResetEvent(sessionId: sessionId).toAgentEvent()
        sendEvent(event)
    }
    
    private func sendEvent(_ event: AgentEvent) {
        guard isConnected else {
            print("AgentWebSocketClient: Cannot send event - not connected")
            return
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(event)
            
            let message = URLSessionWebSocketTask.Message.data(data)
            webSocket?.send(message) { error in
                if let error = error {
                    print("AgentWebSocketClient: Send error - \(error.localizedDescription)")
                } else {
                    print("AgentWebSocketClient: Sent \(event.type.rawValue) event")
                }
            }
        } catch {
            print("AgentWebSocketClient: Encoding error - \(error.localizedDescription)")
        }
    }
    
    // MARK: - Receive Events
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handleReceivedData(data)
                case .string(let string):
                    if let data = string.data(using: .utf8) {
                        self.handleReceivedData(data)
                    }
                @unknown default:
                    break
                }
                
                // Continue listening
                self.receiveMessage()
                
            case .failure(let error):
                print("AgentWebSocketClient: Receive error - \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    if self.shouldReconnect {
                        self.scheduleReconnect()
                    }
                }
            }
        }
    }
    
    private func handleReceivedData(_ data: Data) {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let event = try decoder.decode(AgentEvent.self, from: data)
            
            print("AgentWebSocketClient: Received \(event.type.rawValue) event")
            
            DispatchQueue.main.async {
                self.eventPublisher.send(event)
            }
        } catch {
            print("AgentWebSocketClient: Decoding error - \(error.localizedDescription)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("AgentWebSocketClient: Raw data - \(jsonString)")
            }
        }
    }
    
    deinit {
        disconnect()
    }
}

