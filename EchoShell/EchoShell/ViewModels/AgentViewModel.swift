//
//  AgentViewModel.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  ViewModel for agent-based voice command execution
//  Uses WebSocket for unified communication (commands + TTS audio)
//

import Foundation
import Combine
import SwiftUI
import AVFoundation

/// ViewModel for agent-based voice command interface
/// Separates business logic from UI (RecordingView)
/// Now uses WebSocket for all communication (unified protocol)
@MainActor
class AgentViewModel: ObservableObject {

    // MARK: - Published State

    /// Text recognized from voice input
    @Published var recognizedText: String = ""

    /// Agent's response text
    @Published var agentResponseText: String = ""

    /// Whether voice recording is in progress
    @Published var isRecording: Bool = false

    /// Whether transcription is in progress
    @Published var isTranscribing: Bool = false

    /// Whether command is being processed by agent
    @Published var isProcessing: Bool = false

    /// Current operation ID for cancellation tracking
    @Published var currentOperationId: UUID?

    /// Accumulated output for TTS
    @Published var accumulatedForTTS: String = ""

    /// Last text that was spoken via TTS
    @Published var lastTTSOutput: String = ""

    /// Queue of TTS messages
    @Published var ttsQueue: [String] = []

    /// Pulse animation state for visual feedback
    @Published var pulseAnimation: Bool = false

    /// WebSocket connection state
    @Published var isWebSocketConnected: Bool = false

    // MARK: - Dependencies

    private let audioRecorder: AudioRecorder
    let ttsService: TTSService // Public for UI access (e.g., replay button, audio controls)
    private var apiClient: APIClient
    private var config: TunnelConfig

    // MARK: - WebSocket

    private let wsClient = WebSocketClient()
    private var agentSessionId: String?

    // MARK: - Audio Playback (Server-side TTS)

    private var avAudioPlayer: AVAudioPlayer?
    private var audioPlayerDelegate: AudioPlayerDelegateWrapper?

    // MARK: - Private State

    private var currentOperationTask: Task<Void, Never>?
    private var ttsTimer: Timer?
    private var lastOutputSnapshot: String = ""
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        audioRecorder: AudioRecorder,
        ttsService: TTSService,
        apiClient: APIClient,
        recordingStreamClient: RecordingStreamClient, // Kept for backward compatibility but not used
        config: TunnelConfig
    ) {
        self.audioRecorder = audioRecorder
        self.ttsService = ttsService
        self.apiClient = apiClient
        self.config = config

        setupBindings()
        setupWebSocketBindings()
    }

    // MARK: - Public Methods

    /// Configure audio recorder with settings manager
    func configure(with settingsManager: SettingsManager) {
        audioRecorder.configure(with: settingsManager)
        // In Agent mode, disable autoSendCommand so commands are sent via executeCommand()
        audioRecorder.autoSendCommand = false
        print("✅ AgentViewModel: AudioRecorder configured with settingsManager (autoSendCommand disabled)")
    }

    /// Update configuration (for example, when laptop config changes)
    func updateConfig(_ newConfig: TunnelConfig) {
        self.config = newConfig
        self.apiClient = APIClient(config: newConfig)
        
        // Reconnect WebSocket with new config
        Task {
            await ensureAgentSession()
        }
    }

    /// Ensure agent session exists and WebSocket is connected
    func ensureAgentSession() async {
        guard !config.tunnelId.isEmpty else {
            print("⚠️ AgentViewModel: No tunnel config, cannot create agent session")
            return
        }

        // If we already have a session and WebSocket is connected, do nothing
        if let sessionId = agentSessionId, wsClient.isConnected {
            print("✅ AgentViewModel: Agent session already active: \(sessionId)")
            return
        }

        // Create or get existing agent session
        do {
            let session = try await apiClient.createSession(terminalType: .agent)
            agentSessionId = session.id
            print("✅ AgentViewModel: Created/got agent session: \(session.id)")

            // Connect WebSocket
            connectWebSocket()
        } catch {
            print("❌ AgentViewModel: Failed to create agent session: \(error)")
        }
    }

    /// Start voice recording
    func startRecording() {
        guard !isRecording else {
            print("⚠️ AgentViewModel: Already recording")
            return
        }

        // Cancel any ongoing operation
        cancelCurrentOperation()

        // Reset state for new command
        resetStateForNewCommand()

        // Prevent screen sleep during recording
        IdleTimerManager.shared.beginOperation("recording")

        // Start recording
        audioRecorder.startRecording()
        startPulseAnimation()

        print("🎤 AgentViewModel: Started recording")
    }

    /// Stop voice recording
    func stopRecording() {
        guard isRecording else {
            print("⚠️ AgentViewModel: Not recording")
            return
        }

        // Allow screen sleep after recording stops
        IdleTimerManager.shared.endOperation("recording")

        // Stop recording
        audioRecorder.stopRecording()
        stopPulseAnimation()

        print("🛑 AgentViewModel: Stopped recording")
    }

    /// Toggle recording on/off
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Execute a text command via WebSocket
    /// - Parameters:
    ///   - command: The command text to execute
    ///   - sessionId: Optional terminal session ID (nil for global agent)
    ///   - ttsEnabled: Whether to generate TTS audio on server
    ///   - ttsSpeed: TTS playback speed
    func executeCommand(_ command: String, sessionId: String?, ttsEnabled: Bool = true, ttsSpeed: Double = 1.0, language: String = "en") async {
        guard !command.isEmpty else {
            print("⚠️ AgentViewModel: Empty command, skipping execution")
            return
        }

        // Ensure WebSocket is connected
        await ensureAgentSession()

        guard agentSessionId != nil, wsClient.isConnected else {
            print("❌ AgentViewModel: WebSocket not connected, cannot execute command")
            // Fallback to HTTP API
            await executeCommandViaHTTP(command, sessionId: sessionId)
            return
        }

        // Prevent screen sleep during command processing
        IdleTimerManager.shared.beginOperation("agent_processing")

        isProcessing = true
        let operationId = UUID()
        currentOperationId = operationId

        print("📤 AgentViewModel: Executing command via WebSocket: \(command)")

        // Send command via WebSocket
        wsClient.executeCommand(command, ttsEnabled: ttsEnabled, ttsSpeed: ttsSpeed, language: language)

        // Response will come via WebSocket callbacks (onChatMessage, onTTSAudio)
    }

    /// Replay last TTS audio
    func replayLastTTS() {
        Task {
            await ttsService.replay()
        }
    }

    /// Stop all TTS and clear output
    func stopAllTTSAndClearOutput() {
        print("🛑 AgentViewModel: Stopping all TTS and clearing output")

        ttsService.stop()
        stopAudioPlayback()
        ttsTimer?.invalidate()
        ttsTimer = nil
        ttsQueue = []
        accumulatedForTTS = ""
        lastTTSOutput = ""
        lastOutputSnapshot = ""

        print("🛑 AgentViewModel: All TTS stopped and output cleared")
    }

    /// Cancel current operation
    func cancelCurrentOperation() {
        currentOperationTask?.cancel()
        currentOperationTask = nil
        currentOperationId = nil

        if isRecording {
            IdleTimerManager.shared.endOperation("recording")
            audioRecorder.stopRecording()
        }

        IdleTimerManager.shared.endOperation("agent_processing")
        IdleTimerManager.shared.endOperation("tts_playback")

        stopAudioPlayback()
        stopPulseAnimation()

        print("🛑 AgentViewModel: Cancelled current operation")
    }

    /// Reset state for new command
    func resetStateForNewCommand() {
        recognizedText = ""
        agentResponseText = ""
        accumulatedForTTS = ""
        lastTTSOutput = ""
        ttsQueue = []
        lastOutputSnapshot = ""
        ttsService.reset()

        print("🔄 AgentViewModel: State reset for new command")
    }

    /// Get current recording state
    func getCurrentState() -> RecordingState {
        if isRecording {
            return .recording
        } else if isTranscribing {
            return .transcribing
        } else if avAudioPlayer?.isPlaying == true || ttsService.audioPlayer.isPlaying {
            return .playingTTS
        } else if ttsService.isGenerating {
            return .generatingTTS
        } else if isProcessing {
            return .waitingForAgent
        } else if !recognizedText.isEmpty && agentResponseText.isEmpty {
            return .waitingForAgent
        } else if !agentResponseText.isEmpty {
            if ttsService.lastAudioData != nil {
                return .idle
            } else if ttsService.isGenerating {
                return .generatingTTS
            } else {
                return .waitingForAgent
            }
        } else {
            return .idle
        }
    }

    /// Disconnect WebSocket on cleanup
    func disconnect() {
        wsClient.disconnect()
        agentSessionId = nil
        print("🔌 AgentViewModel: Disconnected WebSocket")
    }

    // MARK: - Private Methods

    private func setupBindings() {
        audioRecorder.$isRecording
            .assign(to: &$isRecording)

        audioRecorder.$isTranscribing
            .assign(to: &$isTranscribing)

        audioRecorder.$recognizedText
            .assign(to: &$recognizedText)
    }

    private func setupWebSocketBindings() {
        // Observe WebSocket connection state
        wsClient.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isWebSocketConnected)
    }

    private func connectWebSocket() {
        guard let sessionId = agentSessionId else {
            print("⚠️ AgentViewModel: No agent session ID for WebSocket")
            return
        }

        wsClient.connect(
            config: config,
            sessionId: sessionId,
            onMessage: nil,
            onChatMessage: { [weak self] message in
                Task { @MainActor in
                    self?.handleChatMessage(message)
                }
            },
            onTTSAudio: { [weak self] event in
                Task { @MainActor in
                    self?.handleTTSAudio(event)
                }
            },
            onTranscription: { [weak self] text in
                Task { @MainActor in
                    print("🎤 AgentViewModel: Received server transcription: \(text)")
                    self?.recognizedText = text
                }
            }
        )

        print("🔌 AgentViewModel: WebSocket connecting to session \(sessionId)")
    }

    private func handleChatMessage(_ message: ChatMessage) {
        print("💬 AgentViewModel: Chat message: \(message.type.rawValue) - \(message.content.prefix(50))...")

        switch message.type {
        case .user:
            // User message - already shown from recognizedText
            break

        case .assistant:
            // Assistant response
            agentResponseText = message.content

        case .system:
            // Check for completion
            if message.metadata?.completion == true {
                isProcessing = false
                IdleTimerManager.shared.endOperation("agent_processing")
                print("✅ AgentViewModel: Command completed")
            }

        case .error:
            // Error message
            agentResponseText = message.content
            isProcessing = false
            IdleTimerManager.shared.endOperation("agent_processing")
            print("❌ AgentViewModel: Error: \(message.content)")

        case .tool, .tts_audio:
            // Tool calls or TTS audio handled separately
            break
        }
    }

    private func handleTTSAudio(_ event: TTSAudioEvent) {
        print("🔊 AgentViewModel: Received TTS audio: \(event.audio.count) bytes")

        // Stop any previous playback
        stopAudioPlayback()

        // Play the received audio
        playServerTTSAudio(event.audio, text: event.text)
    }

    private func playServerTTSAudio(_ audioData: Data, text: String) {
        do {
            // Configure audio session for playback
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            // Create delegate wrapper
            let delegate = AudioPlayerDelegateWrapper { [weak self] in
                Task { @MainActor in
                    self?.isProcessing = false
                    self?.audioPlayerDelegate = nil
                    self?.avAudioPlayer = nil
                    IdleTimerManager.shared.endOperation("tts_playback")
                    print("🔇 AgentViewModel: TTS playback finished")
                    
                    // Send TTS finished event
                    EventBus.shared.ttsPlaybackFinishedPublisher.send()
                }
            }
            audioPlayerDelegate = delegate

            // Prevent screen sleep during playback
            IdleTimerManager.shared.beginOperation("tts_playback")

            // Create and play audio
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = delegate
            player.play()
            avAudioPlayer = player

            // Store audio data for replay
            ttsService.lastAudioData = audioData
            lastTTSOutput = text

            print("▶️ AgentViewModel: Started playing server TTS audio")

            // Send TTS ready event
            let operationId = currentOperationId?.uuidString ?? UUID().uuidString
            EventBus.shared.ttsReadyPublisher.send(
                EventBus.TTSReadyEvent(
                    audioData: audioData,
                    text: text,
                    operationId: operationId,
                    sessionId: nil
                )
            )

        } catch {
            print("❌ AgentViewModel: Error playing TTS audio: \(error)")
            isProcessing = false
            IdleTimerManager.shared.endOperation("tts_playback")
        }
    }

    private func stopAudioPlayback() {
        avAudioPlayer?.stop()
        avAudioPlayer = nil
        audioPlayerDelegate = nil
    }

    /// Fallback: Execute command via HTTP API (when WebSocket not available)
    private func executeCommandViaHTTP(_ command: String, sessionId: String?) async {
        print("📤 AgentViewModel: Fallback - executing command via HTTP API")

        do {
            let result = try await apiClient.executeAgentCommand(
                sessionId: sessionId,
                command: command
            )

            print("✅ AgentViewModel: HTTP command executed successfully")

            agentResponseText = result
            isProcessing = false
            IdleTimerManager.shared.endOperation("agent_processing")

            // Generate and play TTS locally (fallback)
            Task {
                await generateAndPlayTTSLocally(text: result)
            }

        } catch {
            print("❌ AgentViewModel: HTTP command execution failed: \(error)")
            agentResponseText = "Error: \(error.localizedDescription)"
            isProcessing = false
            IdleTimerManager.shared.endOperation("agent_processing")
        }
    }

    /// Fallback: Generate TTS locally
    private func generateAndPlayTTSLocally(text: String) async {
        guard !text.isEmpty else { return }

        if lastTTSOutput == text.trimmingCharacters(in: .whitespacesAndNewlines) {
            print("⚠️ AgentViewModel: Already spoke this text, skipping")
            return
        }

        IdleTimerManager.shared.beginOperation("tts_playback")

        defer {
            IdleTimerManager.shared.endOperation("tts_playback")
        }

        do {
            let audioData = try await ttsService.synthesizeAndPlay(
                text: text,
                config: config,
                speed: 1.0,
                language: "en"
            )

            lastTTSOutput = text.trimmingCharacters(in: .whitespacesAndNewlines)

            let operationId = currentOperationId?.uuidString ?? UUID().uuidString
            EventBus.shared.ttsReadyPublisher.send(
                EventBus.TTSReadyEvent(
                    audioData: audioData,
                    text: text,
                    operationId: operationId,
                    sessionId: nil
                )
            )

            print("✅ AgentViewModel: Local TTS completed")

        } catch {
            print("❌ AgentViewModel: Local TTS failed: \(error)")
            EventBus.shared.ttsFailedPublisher.send(.synthesisFailed(message: error.localizedDescription))
        }
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
    
    // MARK: - Direct Mode TTS Scheduling (for compatibility with RecordingView)
    
    func scheduleAutoTTS(
        lastTerminalOutput: String,
        isHeadlessTerminal: Bool,
        ttsSpeed: Double,
        language: String
    ) {
        // This method is kept for compatibility but now TTS comes via WebSocket
        // For headless terminals, TTS is handled via WebSocket tts_audio events
        print("🔊 AgentViewModel: scheduleAutoTTS called (TTS now comes via WebSocket)")
    }

    // MARK: - State Persistence

    func loadState() {
        let key = "global_agent_state"
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(RecordingStateData.self, from: data) else {
            return
        }

        recognizedText = state.recognizedText
        agentResponseText = state.agentResponseText
        lastTTSOutput = state.lastTTSOutput

        print("📂 AgentViewModel: State loaded")
    }

    func saveState() {
        let key = "global_agent_state"
        let state = RecordingStateData(
            recognizedText: recognizedText,
            agentResponseText: agentResponseText,
            lastTTSOutput: lastTTSOutput
        )

        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key)
            print("💾 AgentViewModel: State saved")
        }
    }

    /// Connect to recording stream (kept for backward compatibility)
    func connectToRecordingStream(sessionId: String?) {
        // Now uses WebSocket instead
        print("ℹ️ AgentViewModel: connectToRecordingStream called - now using WebSocket")
    }

    // MARK: - Cleanup

    deinit {
        currentOperationTask?.cancel()
        currentOperationTask = nil
        ttsTimer?.invalidate()
        ttsTimer = nil

        Task { @MainActor in
            IdleTimerManager.shared.endAllOperations()
        }

        print("🧹 AgentViewModel: Deinitialized")
    }
}

// MARK: - State Persistence Data

private struct RecordingStateData: Codable {
    let recognizedText: String
    let agentResponseText: String
    let lastTTSOutput: String
}

// MARK: - Audio Player Delegate Wrapper

private class AudioPlayerDelegateWrapper: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        super.init()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("❌ AVAudioPlayer decode error: \(error?.localizedDescription ?? "unknown")")
        onFinish()
    }
}
