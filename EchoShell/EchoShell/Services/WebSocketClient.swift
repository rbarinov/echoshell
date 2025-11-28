//
//  WebSocketClient.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Handles WebSocket communication for terminal streaming
//

import Foundation
import UIKit

/// TTS Audio event from server
struct TTSAudioEvent {
    let sessionId: String
    let audio: Data // Decoded audio data
    let format: String // e.g., "audio/mpeg"
    let text: String // Original text that was synthesized
    let timestamp: Date
}

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
    private var onChatMessageCallback: ((ChatMessage) -> Void)?
    private var onTTSAudioCallback: ((TTSAudioEvent) -> Void)?
    private var onTranscriptionCallback: ((String) -> Void)?
    private var onContextResetCallback: (() -> Void)?
    
    // Heartbeat configuration
    private let pingInterval: TimeInterval = 20.0 // 20 seconds
    private let pongTimeout: TimeInterval = 30.0 // 30 seconds
    private var lastPongReceived: Date = Date()
    private var pingTimer: Timer?
    private var healthCheckTimer: Timer?
    
    func connect(
        config: TunnelConfig,
        sessionId: String,
        onMessage: ((String) -> Void)? = nil,
        onChatMessage: ((ChatMessage) -> Void)? = nil,
        onTTSAudio: ((TTSAudioEvent) -> Void)? = nil,
        onTranscription: ((String) -> Void)? = nil,
        onContextReset: (() -> Void)? = nil
    ) {
        // Always preserve callbacks for reconnection
        if let callback = onMessage {
            self.onMessageCallback = callback
        }
        if let chatCallback = onChatMessage {
            self.onChatMessageCallback = chatCallback
        }
        if let ttsCallback = onTTSAudio {
            self.onTTSAudioCallback = ttsCallback
        }
        if let transcriptionCallback = onTranscription {
            self.onTranscriptionCallback = transcriptionCallback
        }
        if let contextResetCallback = onContextReset {
            self.onContextResetCallback = contextResetCallback
        }
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
            // Don't set isConnected = true here - wait for actual connection confirmation
            self.connectionState = .connecting
        }
        reconnectAttempts = 0
        lastPongReceived = Date()
        
        print("📡 WebSocket connecting to: \(wsUrlString)")
        print("   - tunnelId: \(config.tunnelId)")
        print("   - sessionId: \(sessionId)")
        
        setupHeartbeat()
        receiveMessage()
        
        // Send a ping after a short delay to ensure connection is established
        // Some WebSocket implementations need a moment to fully connect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, let task = self.webSocketTask else {
                print("⚠️ WebSocket: Task is nil, cannot send ping")
                return
            }
            
            print("📡 WebSocket: Sending initial ping to confirm connection (task state: \(task.state.rawValue))...")
            task.sendPing { [weak self] error in
                guard let self = self else { return }
                if error == nil {
                    // Ping succeeded - connection is established
                    Task { @MainActor in
                        self.isConnected = true
                        self.connectionState = .connected
                        print("✅ WebSocket connected (ping successful)")
                    }
                } else {
                    print("⚠️ WebSocket initial ping failed: \(error?.localizedDescription ?? "unknown")")
                    print("   - Task state: \(task.state.rawValue)")
                    // Try again after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self = self, let retryTask = self.webSocketTask else { return }
                        print("📡 WebSocket: Retrying ping...")
                        retryTask.sendPing { [weak self] retryError in
                            guard let self = self else { return }
                            if retryError == nil {
                                Task { @MainActor in
                                    self.isConnected = true
                                    self.connectionState = .connected
                                    print("✅ WebSocket connected (retry ping successful)")
                                }
                            } else {
                                print("❌ WebSocket retry ping also failed: \(retryError?.localizedDescription ?? "unknown")")
                            }
                        }
                    }
                }
            }
        }
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
        
        // Log input bytes for debugging (including backspace)
        let inputBytes = input.utf8.map { $0 }
        let inputDescription = input
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\u{0008}", with: "\\b") // Backspace
            .replacingOccurrences(of: "\t", with: "\\t")
        print("📤 Sending input to terminal: '\(inputDescription)' (bytes: \(inputBytes))")
        
        // Special handling for backspace - ensure it's sent correctly
        if inputBytes.count == 1 && (inputBytes[0] == 0x08 || inputBytes[0] == 0x7f) {
            print("⌨️ WebSocketClient: Sending backspace character (byte: \(inputBytes[0]))")
        }
        
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
    
    /// Execute a text command via WebSocket
    /// - Parameters:
    ///   - command: Text command to execute
    ///   - ttsEnabled: Whether to synthesize TTS audio on server
    ///   - ttsSpeed: TTS playback speed (0.7-1.2 for ElevenLabs, 0.25-4.0 for OpenAI)
    ///   - language: Language code for TTS
    func executeCommand(_ command: String, ttsEnabled: Bool = true, ttsSpeed: Double = 1.0, language: String = "en") {
        guard isConnected, let webSocketTask = webSocketTask else {
            print("⚠️ Cannot execute command - not connected")
            return
        }
        
        print("🎯 WebSocketClient: Executing command via WebSocket: \(command.prefix(100))...")
        
        let message: [String: Any] = [
            "type": "execute",
            "command": command,
            "tts_enabled": ttsEnabled,
            "tts_speed": ttsSpeed,
            "language": language
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask.send(.string(jsonString)) { error in
                if let error = error {
                    print("❌ Error sending execute command: \(error.localizedDescription)")
                } else {
                    print("✅ Execute command sent successfully")
                }
            }
        }
    }
    
    /// Send reset context message (agent mode only)
    func sendResetContext() {
        guard isConnected, let webSocketTask = webSocketTask else {
            print("⚠️ Cannot send reset_context - not connected")
            return
        }
        
        print("🔄 WebSocketClient: Sending reset_context message")
        
        let message: [String: Any] = [
            "type": "reset_context"
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask.send(.string(jsonString)) { error in
                if let error = error {
                    print("❌ Error sending reset_context: \(error.localizedDescription)")
                } else {
                    print("✅ Reset context message sent successfully")
                }
            }
        }
    }
    
    /// Execute a voice command via WebSocket (audio will be transcribed on server)
    /// - Parameters:
    ///   - audioData: Audio data to transcribe and execute
    ///   - audioFormat: Audio format (default: audio/m4a)
    ///   - ttsEnabled: Whether to synthesize TTS audio on server
    ///   - ttsSpeed: TTS playback speed
    ///   - language: Language code for STT/TTS
    func executeAudioCommand(_ audioData: Data, audioFormat: String = "audio/m4a", ttsEnabled: Bool = true, ttsSpeed: Double = 1.0, language: String = "en") {
        guard isConnected, let webSocketTask = webSocketTask else {
            print("⚠️ Cannot execute audio command - not connected")
            return
        }
        
        let audioBase64 = audioData.base64EncodedString()
        print("🎤 WebSocketClient: Executing audio command via WebSocket: \(audioData.count) bytes")
        
        let message: [String: Any] = [
            "type": "execute_audio",
            "audio": audioBase64,
            "audio_format": audioFormat,
            "tts_enabled": ttsEnabled,
            "tts_speed": ttsSpeed,
            "language": language
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask.send(.string(jsonString)) { error in
                if let error = error {
                    print("❌ Error sending execute_audio command: \(error.localizedDescription)")
                } else {
                    print("✅ Execute audio command sent successfully")
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
                // Mark connection as established on first successful message
                if self.connectionState != .connected {
                    Task { @MainActor in
                        self.isConnected = true
                        self.connectionState = .connected
                        print("✅ WebSocket connected (message received)")
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
        
        // Handle tts_audio event (server-side TTS)
        if type == "tts_audio" {
            guard let audioBase64 = json["audio"] as? String,
                  let audioData = Data(base64Encoded: audioBase64) else {
                print("❌ WebSocket: Invalid tts_audio event - missing or invalid audio data")
                return
            }
            
            let format = json["format"] as? String ?? "audio/mpeg"
            let ttsText = json["text"] as? String ?? ""
            let timestamp = json["timestamp"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)
            
            print("🔊 WebSocket tts_audio received: \(audioData.count) bytes, format: \(format), text: \(ttsText.prefix(50))...")
            
            let event = TTSAudioEvent(
                sessionId: sessionId,
                audio: audioData,
                format: format,
                text: ttsText,
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
            )
            
            DispatchQueue.main.async {
                if let callback = self.onTTSAudioCallback {
                    callback(event)
                } else {
                    print("⚠️ onTTSAudioCallback is nil!")
                }
            }
            return
        }
        
        // Handle transcription event (server-side STT)
        if type == "transcription" {
            let transcribedText = json["text"] as? String ?? ""
            print("🎤 WebSocket transcription received: \(transcribedText.prefix(100))...")
            
            DispatchQueue.main.async {
                if let callback = self.onTranscriptionCallback {
                    callback(transcribedText)
                }
            }
            return
        }
        
        // Handle context_reset event (agent mode)
        if type == "context_reset" {
            print("🔄 WebSocket context_reset received")
            
            DispatchQueue.main.async {
                if let callback = self.onContextResetCallback {
                    callback()
                }
            }
            return
        }
        
        // Handle chat_message format (for headless terminals)
        if type == "chat_message", let messageDict = json["message"] as? [String: Any] {
            do {
                let messageData = try JSONSerialization.data(withJSONObject: messageDict)
                let decoder = JSONDecoder()
                let chatMessage = try decoder.decode(ChatMessage.self, from: messageData)
                
                print("💬 WebSocket chat_message received: \(chatMessage.type.rawValue) - \(chatMessage.content.prefix(100))...")
                
                // Call chat message callback
                DispatchQueue.main.async {
                    if let callback = self.onChatMessageCallback {
                        callback(chatMessage)
                    }
                }
                
                // Also create TerminalMessage for compatibility
                let message = TerminalMessage(
                    type: .output,
                    sessionId: sessionId,
                    data: chatMessage.content,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(chatMessage.timestamp) / 1000.0)
                )
                
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.messages.append(message)
                    
                    // Keep only last 100 messages
                    if self.messages.count > 100 {
                        self.messages.removeFirst(self.messages.count - 100)
                    }
                }
                
                return
            } catch {
                print("❌ Error decoding chat_message: \(error)")
            }
        }
        
        // Handle regular output format (for regular terminals)
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
            
            self.connect(
                config: config,
                sessionId: sessionId,
                onMessage: self.onMessageCallback,
                onChatMessage: self.onChatMessageCallback,
                onTTSAudio: self.onTTSAudioCallback,
                onTranscription: self.onTranscriptionCallback,
                onContextReset: self.onContextResetCallback
            )
        }
    }
}
