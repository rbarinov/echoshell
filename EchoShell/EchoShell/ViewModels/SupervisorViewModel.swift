//
//  SupervisorViewModel.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  ViewModel for supervisor voice command execution
//  Uses WebSocket /agent/ws - supports streaming responses and TTS
//

import Foundation
import Combine
import SwiftUI
import AVFoundation

/// ViewModel for supervisor voice command interface
/// WebSocket-based: audio/text → streaming chunks → TTS audio
@MainActor
class SupervisorViewModel: ObservableObject, ChatViewModelProtocol {

    // MARK: - Published State

    @Published var recognizedText: String = ""
    @Published var supervisorResponseText: String = ""
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var currentOperationId: UUID?
    @Published var pulseAnimation: Bool = false
    @Published var errorMessage: String?
    @Published var chatHistory: [ChatMessage] = []
    @Published var lastTTSOutput: String = ""
    @Published var isConnected: Bool = false
    @Published private(set) var audioPlaybackState: AudioPlaybackState = .idle

    // MARK: - Dependencies

    private let audioRecorder: AudioRecorder
    let ttsService: TTSService
    private var apiClient: APIClient
    private var config: TunnelConfig

    // MARK: - WebSocket

    private var webSocketTask: URLSessionWebSocketTask?
    private var isReceivingMessages = false

    // MARK: - Audio Playback
    // Note: We use ttsService.audioPlayer for all playback to avoid conflicts

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()
    private var settingsManagerRef: SettingsManager?
    private var pendingUserAudioMessageId: String? // Track user's audio message to update with transcription
    private var isAwaitingResponse: Bool = false // Only auto-play TTS when we're actively waiting for response
    private var currentlyPlayingMessageId: String? // Track which message is currently playing
    private var currentPlaybackToken: UUID?
    private var playbackTask: Task<Void, Never>?

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
        
        print("✅ SupervisorViewModel: Configured (WebSocket /agent/ws mode)")
    }

    func updateConfig(_ newConfig: TunnelConfig) {
        self.config = newConfig
        self.apiClient = APIClient(config: newConfig)
        // Reconnect WebSocket with new config
        disconnectWebSocket()
        print("✅ SupervisorViewModel: Config updated")
    }

    // MARK: - WebSocket Connection

    func ensureSupervisorSession() async {
        guard !config.tunnelId.isEmpty else {
            print("⚠️ SupervisorViewModel: No tunnel config")
            return
        }
        
        if isConnected {
            print("✅ SupervisorViewModel: Already connected")
            return
        }
        
        connectWebSocket()
        
        // Wait for connection
        let maxWait: TimeInterval = 3.0
        let start = Date()
        while !isConnected && Date().timeIntervalSince(start) < maxWait {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        print(isConnected ? "✅ SupervisorViewModel: WebSocket connected" : "⚠️ SupervisorViewModel: Connection timeout")
    }

    private func connectWebSocket() {
        guard !config.tunnelId.isEmpty else { return }
        
        // Build WebSocket URL through tunnel: wss://server/api/{tunnelId}/agent/ws
        let wsUrl = config.wsUrl.isEmpty ? config.apiBaseUrl.replacingOccurrences(of: "http", with: "ws") : config.wsUrl
        let urlString = "\(wsUrl)/api/\(config.tunnelId)/agent/ws"
        
        guard let url = URL(string: urlString) else {
            print("❌ SupervisorViewModel: Invalid WebSocket URL: \(urlString)")
            return
        }
        
        print("📡 SupervisorViewModel: Connecting to \(urlString)")
        
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
                    print("✅ SupervisorViewModel: WebSocket connected (ping OK)")
                } else {
                    print("⚠️ SupervisorViewModel: Ping failed: \(error?.localizedDescription ?? "")")
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
        print("🔌 SupervisorViewModel: Disconnected")
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
                    print("❌ SupervisorViewModel: WebSocket error: \(error.localizedDescription)")
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
                print("🎤 SupervisorViewModel: Transcription: \(transcribedText)")
                
                // If we have a pending audio message, update it with the transcription
                if let pendingId = pendingUserAudioMessageId,
                   let index = chatHistory.firstIndex(where: { $0.id == pendingId }) {
                    // Update the audio message with transcription text in metadata
                    let existingMessage = chatHistory[index]
                    let updatedMessage = ChatMessage(
                        id: existingMessage.id,
                        timestamp: existingMessage.timestamp,
                        type: .tts_audio,
                        content: "🎤 \(transcribedText)", // Show transcription in content
                        metadata: ChatMessage.Metadata(
                            ttsText: transcribedText,
                            audioFilePath: existingMessage.metadata?.audioFilePath
                        )
                    )
                    chatHistory[index] = updatedMessage
                    pendingUserAudioMessageId = nil
                } else {
                    // No pending audio message - create text-only user message
                    let userMessage = ChatMessage(
                        id: UUID().uuidString,
                        timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                        type: .user,
                        content: transcribedText,
                        metadata: nil
                    )
                    chatHistory.append(userMessage)
                }
                saveChatHistory() // Persist after user message
            }

        case "chunk":
            if let chunkText = json["text"] as? String {
                supervisorResponseText = chunkText
                print("📝 SupervisorViewModel: Chunk: \(chunkText.prefix(50))...")
            }

        case "complete":
            if let finalText = json["text"] as? String {
                supervisorResponseText = finalText
                
                // Add assistant message to chat
                let assistantMessage = ChatMessage(
                    id: UUID().uuidString,
                    timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                    type: .assistant,
                    content: finalText,
                    metadata: nil
                )
                chatHistory.append(assistantMessage)
                
                print("✅ SupervisorViewModel: Complete: \(finalText.prefix(50))...")
            }
            
            // Play audio if present and save to chat
            if let audioBase64 = json["audio"] as? String,
               let audioData = Data(base64Encoded: audioBase64) {
                
                // Save audio to file and add to chat
                if let audioFilePath = saveAudioToFile(audioData) {
                    let audioMessage = ChatMessage(
                        id: UUID().uuidString,
                        timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                        type: .tts_audio,
                        content: "🔊 Voice response",
                        metadata: ChatMessage.Metadata(
                            ttsText: supervisorResponseText,
                            audioFilePath: audioFilePath
                        )
                    )
                    chatHistory.append(audioMessage)
                    saveChatHistory() // Persist after adding audio
                }
                
                // Only auto-play if we're actively waiting for this response
                // (not when returning to screen after navigation)
                if isAwaitingResponse {
                    print("🔊 SupervisorViewModel: Auto-playing TTS audio (\(audioData.count) bytes)")
                    playAudio(audioData, text: supervisorResponseText)
                } else {
                    print("ℹ️ SupervisorViewModel: TTS audio saved but not auto-playing (not awaiting response)")
                    isProcessing = false
                    IdleTimerManager.shared.endOperation("supervisor_processing")
                }
                isAwaitingResponse = false // Response received, stop auto-play on next navigation
            } else {
                isProcessing = false
                isAwaitingResponse = false
                IdleTimerManager.shared.endOperation("supervisor_processing")
            }
            
            saveChatHistory() // Persist chat history

        case "error":
            let errorText = json["error"] as? String ?? "Unknown error"
            print("❌ SupervisorViewModel: Error: \(errorText)")
            errorMessage = errorText
            isProcessing = false
            isAwaitingResponse = false
            IdleTimerManager.shared.endOperation("supervisor_processing")

        case "context_reset":
            print("🔄 SupervisorViewModel: Context reset confirmed")
            chatHistory = []

        default:
            print("⚠️ SupervisorViewModel: Unknown message type: \(type)")
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
        
        // Supervisor mode: send via WebSocket
        guard !config.tunnelId.isEmpty else {
            errorMessage = "Not connected. Please scan QR code."
            return
        }
        
        await ensureSupervisorSession()
        
        guard isConnected else {
            errorMessage = "Connection failed. Is laptop app running?"
            return
        }
        
        // Save user's voice message to chat BEFORE sending
        if let userAudioPath = saveUserAudioToFile(audioData) {
            let userVoiceMessage = ChatMessage(
                id: UUID().uuidString,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                type: .tts_audio,
                content: "🎤 Voice message",
                metadata: ChatMessage.Metadata(
                    ttsText: nil, // Will be filled when transcription arrives
                    audioFilePath: userAudioPath
                )
            )
            chatHistory.append(userVoiceMessage)
            pendingUserAudioMessageId = userVoiceMessage.id // Track for updating with transcription
            saveChatHistory()
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
        isAwaitingResponse = true // We're now waiting for response - will auto-play TTS
        IdleTimerManager.shared.beginOperation("supervisor_processing")
        
        try? FileManager.default.removeItem(at: audioURL)
    }

    // MARK: - ChatViewModelProtocol Methods
    
    func sendTextCommand(_ command: String) async {
        await executeCommand(command, sessionId: nil, ttsEnabled: settingsManagerRef?.ttsEnabled ?? true, ttsSpeed: settingsManagerRef?.ttsSpeed ?? 1.0, language: settingsManagerRef?.transcriptionLanguage.whisperCode ?? "en")
    }

    func executeCommand(_ command: String, sessionId: String?, ttsEnabled: Bool = true, ttsSpeed: Double = 1.0, language: String = "en") async {
        guard !command.isEmpty else { return }

        await ensureSupervisorSession()

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
        saveChatHistory() // Persist after user message
        
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
        isAwaitingResponse = true // We're now waiting for response - will auto-play TTS
        IdleTimerManager.shared.beginOperation("supervisor_processing")
    }

    private func sendMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                print("❌ SupervisorViewModel: Send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Audio Playback
    // Using ttsService.audioPlayer for consistent audio management

    private func playAudio(_ audioData: Data, text: String) {
        // ALWAYS stop any existing playback first
        stopAudioPlayback()
        playbackTask?.cancel()
        let playbackToken = UUID()
        currentPlaybackToken = playbackToken
        
        print("🔊 SupervisorViewModel: Starting audio playback (\(audioData.count) bytes)")
        
        // Save for replay
        ttsService.lastAudioData = audioData
        lastTTSOutput = text
        
        IdleTimerManager.shared.beginOperation("tts_playback")
        if let messageId = currentlyPlayingMessageId {
            audioPlaybackState = AudioPlaybackState(messageId: messageId, status: .playing)
        } else {
            audioPlaybackState = .idle
        }
        
        // Use TTSService's audioPlayer for consistent audio management
        playbackTask = Task { [weak self] in
            do {
                try await self?.ttsService.audioPlayer.play(audioData: audioData, title: "Voice Response")
                print("✅ SupervisorViewModel: Audio playback started via TTSService")
                
                EventBus.shared.ttsReadyPublisher.send(
                    EventBus.TTSReadyEvent(
                        audioData: audioData,
                        text: text,
                        operationId: self?.currentOperationId?.uuidString ?? UUID().uuidString,
                        sessionId: nil
                    )
                )
                
                // Wait for playback to finish
                try await self?.waitForPlaybackToFinish(token: playbackToken)
                await MainActor.run {
                    if self?.currentPlaybackToken == playbackToken {
                        self?.playbackTask = nil
                    }
                }
                
            } catch {
                if Task.isCancelled { return }
                print("❌ SupervisorViewModel: Playback error: \(error)")
                await MainActor.run {
                    self?.currentPlaybackToken = nil
                    self?.onAudioPlaybackFinished()
                    self?.playbackTask = nil
                }
            }
        }
    }
    
    /// Wait for TTSService audioPlayer to finish playing
    private func waitForPlaybackToFinish(token: UUID) async throws {
        // Poll until playback finishes
        while ttsService.audioPlayer.isPlaying {
            try Task.checkCancellation()
            if currentPlaybackToken != token { return }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        guard currentPlaybackToken == token else { return }
        
        await MainActor.run {
            currentPlaybackToken = nil
            onAudioPlaybackFinished()
        }
    }
    
    /// Called when audio playback finishes (success, failure, or manual stop)
    private func onAudioPlaybackFinished() {
        print("🔇 SupervisorViewModel: Audio playback finished")
        objectWillChange.send()
        audioPlaybackState = .idle
        // Reset state
        currentlyPlayingMessageId = nil
        isProcessing = false
        IdleTimerManager.shared.endOperation("supervisor_processing")
        IdleTimerManager.shared.endOperation("tts_playback")
    }

    private func stopAudioPlayback() {
        // Stop TTSService's player if playing
        if ttsService.audioPlayer.isPlaying || ttsService.audioPlayer.isPaused {
            print("⏹️ SupervisorViewModel: Stopping current audio playback")
            ttsService.audioPlayer.stop()
            objectWillChange.send()
            audioPlaybackState = .idle
        }
        currentPlaybackToken = nil
        playbackTask?.cancel()
        playbackTask = nil
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
        isAwaitingResponse = false
        if isRecording {
            IdleTimerManager.shared.endOperation("recording")
            audioRecorder.stopRecording()
        }
        IdleTimerManager.shared.endOperation("supervisor_processing")
        IdleTimerManager.shared.endOperation("tts_playback")
        stopAudioPlayback()
        stopPulseAnimation()
    }

    func resetStateForNewCommand() {
        recognizedText = ""
        supervisorResponseText = ""
        lastTTSOutput = ""
        errorMessage = nil
        ttsService.reset()
    }

    func getCurrentState() -> RecordingState {
        if isRecording { return .recording }
        if isProcessing { return .waitingForAgent }
        if ttsService.audioPlayer.isPlaying { return .playingTTS }
            return .idle
    }

    func resetContext() async {
        sendMessage(["type": "reset_context"])
        chatHistory = []
        recognizedText = ""
        supervisorResponseText = ""
        
        // Clear persisted chat history and audio files
        try? FileManager.default.removeItem(at: chatHistoryFileURL)
        try? FileManager.default.removeItem(at: audioDirectory)
        print("🧹 SupervisorViewModel: Chat history and audio files cleared")
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
        guard let data = UserDefaults.standard.data(forKey: "global_supervisor_state"),
              let state = try? JSONDecoder().decode(RecordingStateData.self, from: data) else { return }
        recognizedText = state.recognizedText
        supervisorResponseText = state.supervisorResponseText
        lastTTSOutput = state.lastTTSOutput

        // Load chat history
        loadChatHistory()
    }

    func saveState() {
        let state = RecordingStateData(recognizedText: recognizedText, supervisorResponseText: supervisorResponseText, lastTTSOutput: lastTTSOutput)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "global_supervisor_state")
        }
        saveChatHistory()
    }
    
    // MARK: - Chat History Persistence
    
    private var chatHistoryFileURL: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDir.appendingPathComponent("supervisor_chat_history.json")
    }
    
    private func saveChatHistory() {
        do {
            let data = try JSONEncoder().encode(chatHistory)
            try data.write(to: chatHistoryFileURL)
            print("💾 SupervisorViewModel: Chat history saved (\(chatHistory.count) messages)")
        } catch {
            print("❌ SupervisorViewModel: Failed to save chat history: \(error)")
        }
    }
    
    private func loadChatHistory() {
        do {
            let data = try Data(contentsOf: chatHistoryFileURL)
            chatHistory = try JSONDecoder().decode([ChatMessage].self, from: data)
            print("📂 SupervisorViewModel: Chat history loaded (\(chatHistory.count) messages)")
        } catch {
            print("ℹ️ SupervisorViewModel: No chat history found or failed to load: \(error.localizedDescription)")
            chatHistory = []
        }
    }
    
    // MARK: - Audio File Management
    
    private var audioDirectory: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioDir = documentsDir.appendingPathComponent("supervisor_audio")
        
        // Create directory if needed
        if !FileManager.default.fileExists(atPath: audioDir.path) {
            try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }
        
        return audioDir
    }
    
    /// Save TTS audio data to file and return relative path
    private func saveAudioToFile(_ audioData: Data) -> String? {
        let filename = "tts_\(Int(Date().timeIntervalSince1970 * 1000)).mp3"
        let fileURL = audioDirectory.appendingPathComponent(filename)
        
        do {
            try audioData.write(to: fileURL)
            print("💾 SupervisorViewModel: TTS audio saved to \(filename)")
            return "supervisor_audio/\(filename)"
        } catch {
            print("❌ SupervisorViewModel: Failed to save TTS audio: \(error)")
            return nil
        }
    }
    
    /// Save user's voice recording to file and return relative path
    private func saveUserAudioToFile(_ audioData: Data) -> String? {
        let filename = "user_\(Int(Date().timeIntervalSince1970 * 1000)).m4a"
        let fileURL = audioDirectory.appendingPathComponent(filename)
        
        do {
            try audioData.write(to: fileURL)
            print("💾 SupervisorViewModel: User audio saved to \(filename)")
            return "supervisor_audio/\(filename)"
        } catch {
            print("❌ SupervisorViewModel: Failed to save user audio: \(error)")
            return nil
        }
    }
    
    /// Load audio data from relative path
    func loadAudioFromFile(_ relativePath: String) -> Data? {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDir.appendingPathComponent(relativePath)
        
        return try? Data(contentsOf: fileURL)
    }
    
    /// Play audio from a chat message (or resume if paused)
    func playAudioMessage(_ message: ChatMessage) {
        // If the same audio is paused, resume it
        if ttsService.audioPlayer.isPaused && currentlyPlayingMessageId == message.id {
            print("▶️ SupervisorViewModel: Resuming paused audio")
            ttsService.audioPlayer.resume()
            objectWillChange.send()
            audioPlaybackState = AudioPlaybackState(messageId: message.id, status: .playing)
            return
        }
        
        guard let audioPath = message.metadata?.audioFilePath,
              let audioData = loadAudioFromFile(audioPath) else {
            print("❌ SupervisorViewModel: Cannot play audio - no file path or file not found")
            return
        }
        
        objectWillChange.send()
        currentlyPlayingMessageId = message.id
        let text = message.metadata?.ttsText ?? message.content
        playAudio(audioData, text: text)
    }
    
    /// Pause current audio playback
    func pauseAudio() {
        print("⏸️ SupervisorViewModel: Pausing audio")
        ttsService.audioPlayer.pause()
        objectWillChange.send()
        if let messageId = currentlyPlayingMessageId {
            audioPlaybackState = AudioPlaybackState(messageId: messageId, status: .paused)
        }
    }
    
    /// Stop current audio playback
    func stopAudio() {
        print("⏹️ SupervisorViewModel: Stopping audio")
        stopAudioPlayback()
        currentlyPlayingMessageId = nil
        onAudioPlaybackFinished()
    }
    
    /// Check if a specific message is currently playing
    func isMessagePlaying(_ messageId: String) -> Bool {
        return currentlyPlayingMessageId == messageId && ttsService.audioPlayer.isPlaying
    }
    
    /// Check if a specific message is currently paused
    func isMessagePaused(_ messageId: String) -> Bool {
        return currentlyPlayingMessageId == messageId && ttsService.audioPlayer.isPaused
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
    let supervisorResponseText: String
    let lastTTSOutput: String
}

