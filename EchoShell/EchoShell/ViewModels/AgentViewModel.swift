//
//  AgentViewModel.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  ViewModel for agent-based voice command execution
//  Uses WebSocket /agent/ws - supports streaming responses and TTS
//

import Foundation
import Combine
import SwiftUI
import AVFoundation

/// ViewModel for agent-based voice command interface
/// WebSocket-based: audio/text → streaming chunks → TTS audio
@MainActor
class AgentViewModel: ObservableObject {

    // MARK: - Published State

    @Published var recognizedText: String = ""
    @Published var agentResponseText: String = ""
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var currentOperationId: UUID?
    @Published var pulseAnimation: Bool = false
    @Published var errorMessage: String?
    @Published var chatHistory: [ChatMessage] = []
    @Published var lastTTSOutput: String = ""
    @Published var isConnected: Bool = false

    // MARK: - Dependencies

    private let audioRecorder: AudioRecorder
    let ttsService: TTSService
    private var apiClient: APIClient
    private var config: TunnelConfig

    // MARK: - WebSocket

    private var webSocketTask: URLSessionWebSocketTask?
    private var isReceivingMessages = false

    // MARK: - Audio Playback

    private var avAudioPlayer: AVAudioPlayer?
    private var audioPlayerDelegate: AudioPlayerDelegateWrapper?

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()
    private var settingsManagerRef: SettingsManager?

    // MARK: - Initialization

    init(
        audioRecorder: AudioRecorder,
        ttsService: TTSService,
        apiClient: APIClient,
        config: TunnelConfig
    ) {
        self.audioRecorder = audioRecorder
        self.ttsService = ttsService
        self.apiClient = apiClient
        self.config = config

        setupBindings()
    }

    // MARK: - Configuration

    func configure(with settingsManager: SettingsManager) {
        self.settingsManagerRef = settingsManager
        audioRecorder.configure(with: settingsManager)
        audioRecorder.autoSendCommand = false
        
        audioRecorder.onAudioFileReady = { [weak self] audioURL in
            Task { @MainActor in
                await self?.handleAudioFileReady(audioURL, settingsManager: settingsManager)
            }
        }
        
        print("✅ AgentViewModel: Configured (WebSocket /agent/ws mode)")
    }

    func updateConfig(_ newConfig: TunnelConfig) {
        self.config = newConfig
        self.apiClient = APIClient(config: newConfig)
        // Reconnect WebSocket with new config
        disconnectWebSocket()
        print("✅ AgentViewModel: Config updated")
    }

    // MARK: - WebSocket Connection

    func ensureAgentSession() async {
        guard !config.tunnelId.isEmpty else {
            print("⚠️ AgentViewModel: No tunnel config")
            return
        }
        
        if isConnected {
            print("✅ AgentViewModel: Already connected")
            return
        }
        
        connectWebSocket()
        
        // Wait for connection
        let maxWait: TimeInterval = 3.0
        let start = Date()
        while !isConnected && Date().timeIntervalSince(start) < maxWait {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        print(isConnected ? "✅ AgentViewModel: WebSocket connected" : "⚠️ AgentViewModel: Connection timeout")
    }

    private func connectWebSocket() {
        guard !config.tunnelId.isEmpty else { return }
        
        // Build WebSocket URL through tunnel: wss://server/api/{tunnelId}/agent/ws
        let wsUrl = config.wsUrl.isEmpty ? config.apiBaseUrl.replacingOccurrences(of: "http", with: "ws") : config.wsUrl
        let urlString = "\(wsUrl)/api/\(config.tunnelId)/agent/ws"
        
        guard let url = URL(string: urlString) else {
            print("❌ AgentViewModel: Invalid WebSocket URL: \(urlString)")
            return
        }
        
        print("📡 AgentViewModel: Connecting to \(urlString)")
        
        var request = URLRequest(url: url)
        request.setValue(config.authKey, forHTTPHeaderField: "X-Laptop-Auth-Key")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start receiving messages
        isReceivingMessages = true
        receiveMessage()
        
        // Send ping to confirm connection
        webSocketTask?.sendPing { [weak self] error in
            Task { @MainActor in
                if error == nil {
                    self?.isConnected = true
                    print("✅ AgentViewModel: WebSocket connected (ping OK)")
                } else {
                    print("⚠️ AgentViewModel: Ping failed: \(error?.localizedDescription ?? "")")
                }
            }
        }
    }

    private func disconnectWebSocket() {
        isReceivingMessages = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    func disconnect() {
        disconnectWebSocket()
        print("🔌 AgentViewModel: Disconnected")
    }

    // MARK: - Receive Messages

    private func receiveMessage() {
        guard isReceivingMessages else { return }
        
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self.isConnected = true
                    
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
                    
                    // Continue receiving
                    self.receiveMessage()
                    
                case .failure(let error):
                    print("❌ AgentViewModel: WebSocket error: \(error.localizedDescription)")
                    self.isConnected = false
                    // Try to reconnect after delay
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if self.isReceivingMessages {
                            self.connectWebSocket()
                        }
                    }
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "transcription":
            if let transcribedText = json["text"] as? String {
                recognizedText = transcribedText
                print("🎤 AgentViewModel: Transcription: \(transcribedText)")
                
                // Add user message to chat
                let userMessage = ChatMessage(
                    id: UUID().uuidString,
                    timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                    type: .user,
                    content: transcribedText,
                    metadata: nil
                )
                chatHistory.append(userMessage)
            }

        case "chunk":
            if let chunkText = json["text"] as? String {
                agentResponseText = chunkText
                print("📝 AgentViewModel: Chunk: \(chunkText.prefix(50))...")
            }

        case "complete":
            if let finalText = json["text"] as? String {
                agentResponseText = finalText
                
                // Add assistant message to chat
                let assistantMessage = ChatMessage(
                    id: UUID().uuidString,
                    timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                    type: .assistant,
                    content: finalText,
                    metadata: nil
                )
                chatHistory.append(assistantMessage)
                
                print("✅ AgentViewModel: Complete: \(finalText.prefix(50))...")
            }
            
            // Play audio if present
            if let audioBase64 = json["audio"] as? String,
               let audioData = Data(base64Encoded: audioBase64) {
                print("🔊 AgentViewModel: Playing TTS audio (\(audioData.count) bytes)")
                playAudio(audioData, text: agentResponseText)
            } else {
                isProcessing = false
                IdleTimerManager.shared.endOperation("agent_processing")
            }

        case "error":
            let errorText = json["error"] as? String ?? "Unknown error"
            print("❌ AgentViewModel: Error: \(errorText)")
            errorMessage = errorText
            isProcessing = false
            IdleTimerManager.shared.endOperation("agent_processing")

        case "context_reset":
            print("🔄 AgentViewModel: Context reset confirmed")
            chatHistory = []

        default:
            print("⚠️ AgentViewModel: Unknown message type: \(type)")
        }
    }

    // MARK: - Execute

    private func handleAudioFileReady(_ audioURL: URL, settingsManager: SettingsManager) async {
        guard let audioData = try? Data(contentsOf: audioURL) else {
            errorMessage = "Error loading audio file"
            return
        }
        
        // Direct mode uses different flow
        if settingsManager.commandMode == .direct {
            EventBus.shared.audioReadyForTransmissionPublisher.send(
                EventBus.AudioReadyEvent(
                    audioData: audioData,
                    audioURL: audioURL,
                    language: settingsManager.transcriptionLanguage.whisperCode ?? "en",
                    ttsEnabled: settingsManager.ttsEnabled,
                    ttsSpeed: settingsManager.ttsSpeed
                )
            )
            return
        }
        
        // Agent mode: send via WebSocket
        guard !config.tunnelId.isEmpty else {
            errorMessage = "Not connected. Please scan QR code."
            return
        }
        
        await ensureAgentSession()
        
        guard isConnected else {
            errorMessage = "Connection failed. Is laptop app running?"
            return
        }
        
        // Send execute_audio message with audio data
        let message: [String: Any] = [
            "type": "execute_audio",
            "audio": audioData.base64EncodedString(),
            "audio_format": "audio/m4a",
            "language": settingsManager.transcriptionLanguage.whisperCode ?? "en",
            "tts_enabled": settingsManager.ttsEnabled,
            "tts_speed": settingsManager.ttsSpeed
        ]
        
        sendMessage(message)
        isProcessing = true
        IdleTimerManager.shared.beginOperation("agent_processing")
        
        try? FileManager.default.removeItem(at: audioURL)
    }

    func executeCommand(_ command: String, sessionId: String?, ttsEnabled: Bool = true, ttsSpeed: Double = 1.0, language: String = "en") async {
        guard !command.isEmpty else { return }

        await ensureAgentSession()

        guard isConnected else {
            errorMessage = "Connection failed"
            return
        }

        recognizedText = command
        
        // Add user message
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: .user,
            content: command,
            metadata: nil
        )
        chatHistory.append(userMessage)
        
        // Send execute message with text
        let message: [String: Any] = [
            "type": "execute",
            "command": command,
            "language": language,
            "tts_enabled": ttsEnabled,
            "tts_speed": ttsSpeed
        ]
        
        sendMessage(message)
        isProcessing = true
        IdleTimerManager.shared.beginOperation("agent_processing")
    }

    private func sendMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                print("❌ AgentViewModel: Send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Audio Playback

    private func playAudio(_ audioData: Data, text: String) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            let delegate = AudioPlayerDelegateWrapper { [weak self] in
                Task { @MainActor in
                    self?.audioPlayerDelegate = nil
                    self?.avAudioPlayer = nil
                    self?.isProcessing = false
                    IdleTimerManager.shared.endOperation("agent_processing")
                    IdleTimerManager.shared.endOperation("tts_playback")
                    EventBus.shared.ttsPlaybackFinishedPublisher.send()
                }
            }
            audioPlayerDelegate = delegate

            IdleTimerManager.shared.beginOperation("tts_playback")

            let player = try AVAudioPlayer(data: audioData)
            player.delegate = delegate
            player.play()
            avAudioPlayer = player

            ttsService.lastAudioData = audioData
            lastTTSOutput = text

            EventBus.shared.ttsReadyPublisher.send(
                EventBus.TTSReadyEvent(
                    audioData: audioData,
                    text: text,
                    operationId: currentOperationId?.uuidString ?? UUID().uuidString,
                    sessionId: nil
                )
            )

        } catch {
            print("❌ AgentViewModel: Playback error: \(error)")
            isProcessing = false
            IdleTimerManager.shared.endOperation("agent_processing")
        }
    }

    private func stopAudioPlayback() {
        avAudioPlayer?.stop()
        avAudioPlayer = nil
        audioPlayerDelegate = nil
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }
        cancelCurrentOperation()
        resetStateForNewCommand()
        IdleTimerManager.shared.beginOperation("recording")
        audioRecorder.startRecording()
        startPulseAnimation()
    }

    func stopRecording() {
        guard isRecording else { return }
        IdleTimerManager.shared.endOperation("recording")
        audioRecorder.stopRecording()
        stopPulseAnimation()
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    // MARK: - Other Methods

    func replayLastTTS() {
        Task { await ttsService.replay() }
    }

    func stopAllTTSAndClearOutput() {
        ttsService.stop()
        stopAudioPlayback()
    }

    func cancelCurrentOperation() {
        currentOperationId = nil
        if isRecording {
            IdleTimerManager.shared.endOperation("recording")
            audioRecorder.stopRecording()
        }
        IdleTimerManager.shared.endOperation("agent_processing")
        IdleTimerManager.shared.endOperation("tts_playback")
        stopAudioPlayback()
        stopPulseAnimation()
    }

    func resetStateForNewCommand() {
        recognizedText = ""
        agentResponseText = ""
        lastTTSOutput = ""
        errorMessage = nil
        ttsService.reset()
    }

    func getCurrentState() -> RecordingState {
        if isRecording { return .recording }
        if isProcessing { return .waitingForAgent }
        if avAudioPlayer?.isPlaying == true || ttsService.audioPlayer.isPlaying { return .playingTTS }
        return .idle
    }

    func resetContext() async {
        sendMessage(["type": "reset_context"])
        chatHistory = []
        recognizedText = ""
        agentResponseText = ""
    }

    // MARK: - Bindings & Animation

    private func setupBindings() {
        audioRecorder.$isRecording.assign(to: &$isRecording)
    }

    private func startPulseAnimation() {
        pulseAnimation = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.pulseAnimation = true
        }
    }

    private func stopPulseAnimation() {
        pulseAnimation = false
    }

    // MARK: - State Persistence

    func loadState() {
        guard let data = UserDefaults.standard.data(forKey: "global_agent_state"),
              let state = try? JSONDecoder().decode(RecordingStateData.self, from: data) else { return }
        recognizedText = state.recognizedText
        agentResponseText = state.agentResponseText
        lastTTSOutput = state.lastTTSOutput
    }

    func saveState() {
        let state = RecordingStateData(recognizedText: recognizedText, agentResponseText: agentResponseText, lastTTSOutput: lastTTSOutput)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "global_agent_state")
        }
    }

    // Backward compatibility
    func connectToRecordingStream(sessionId: String?) {}
    func scheduleAutoTTS(lastTerminalOutput: String, isHeadlessTerminal: Bool, ttsSpeed: Double, language: String) {}
    var isTranscribing: Bool { isProcessing }

    deinit {
        // Note: Can't call MainActor methods from deinit
        // WebSocket will be automatically closed when task is deallocated
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
}

// MARK: - Supporting Types

private struct RecordingStateData: Codable {
    let recognizedText: String
    let agentResponseText: String
    let lastTTSOutput: String
}

private class AudioPlayerDelegateWrapper: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish; super.init() }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish() }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { onFinish() }
}
