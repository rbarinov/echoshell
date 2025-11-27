//
//  TerminalAgentViewModel.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  ViewModel for terminal-specific agent voice command execution
//  Manages recording, transcription, command execution, and TTS playback per terminal
//

import Foundation
import Combine
import SwiftUI

/// ViewModel for terminal-specific agent interface
/// Separates business logic from UI (TerminalSessionAgentView)
/// Each terminal session has its own isolated ViewModel with persistent state
@MainActor
class TerminalAgentViewModel: ObservableObject {

    // MARK: - Published State

    /// Text recognized from voice input
    @Published var recognizedText: String = ""

    /// Agent's response text (local to this terminal)
    @Published var agentResponseText: String = ""

    /// Whether voice recording is in progress
    @Published var isRecording: Bool = false

    /// Whether transcription is in progress
    @Published var isTranscribing: Bool = false

    /// Pulse animation state for visual feedback
    @Published var pulseAnimation: Bool = false

    // MARK: - Session Info

    let sessionId: String
    let sessionName: String
    let config: TunnelConfig

    // MARK: - Dependencies

    private let audioRecorder: AudioRecorder
    private let ttsService: TTSService
    private let apiClient: APIClient
    private let recordingStreamClient: RecordingStreamClient

    // MARK: - Private State

    private var currentOperationId: UUID?
    private var accumulatedText: String = ""
    private var lastTTSedText: String = ""
    private var ttsTriggeredForCurrentResponse: Bool = false
    private var lastCompletionText: String = ""
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Persistence

    private var persistenceKey: String {
        return "terminal_state_\(sessionId)"
    }

    // MARK: - Initialization

    init(
        sessionId: String,
        sessionName: String,
        config: TunnelConfig,
        audioRecorder: AudioRecorder,
        ttsService: TTSService,
        apiClient: APIClient,
        recordingStreamClient: RecordingStreamClient
    ) {
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.config = config
        self.audioRecorder = audioRecorder
        self.ttsService = ttsService
        self.apiClient = apiClient
        self.recordingStreamClient = recordingStreamClient

        setupBindings()
        loadState()
    }

    // MARK: - Public Methods

    /// Start voice recording
    func startRecording() {
        guard !isRecording else {
            print("⚠️ TerminalAgentViewModel[\(sessionId)]: Already recording")
            return
        }

        // Reset state for new command
        resetStateForNewCommand()

        // Prevent screen sleep during recording
        IdleTimerManager.shared.beginOperation("recording_\(sessionId)")

        // Start recording
        // isRecording will be updated automatically via binding from audioRecorder.$isRecording
        audioRecorder.startRecording()
        startPulseAnimation()

        print("🎤 TerminalAgentViewModel[\(sessionId)]: Started recording")
    }

    /// Stop voice recording
    func stopRecording() {
        guard isRecording else {
            print("⚠️ TerminalAgentViewModel[\(sessionId)]: Not recording")
            return
        }

        // Allow screen sleep after recording stops
        IdleTimerManager.shared.endOperation("recording_\(sessionId)")

        // Stop recording
        // isRecording will be updated automatically via binding from audioRecorder.$isRecording
        audioRecorder.stopRecording()
        stopPulseAnimation()

        print("🛑 TerminalAgentViewModel[\(sessionId)]: Stopped recording")
    }

    /// Toggle recording on/off
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Execute a text command to this terminal
    func executeCommand(_ command: String) async {
        guard !command.isEmpty else {
            print("⚠️ TerminalAgentViewModel[\(sessionId)]: Empty command, skipping")
            return
        }

        currentOperationId = UUID()

        print("📤 TerminalAgentViewModel[\(sessionId)]: Executing command: \(command)")

        // Connect to recording stream to receive agent response
        connectToRecordingStream()

        do {
            // Execute command via API for this specific terminal session
            _ = try await apiClient.executeCommand(
                sessionId: sessionId,
                command: command
            )

            print("✅ TerminalAgentViewModel[\(sessionId)]: Command sent successfully")

        } catch {
            print("❌ TerminalAgentViewModel[\(sessionId)]: Command execution failed: \(error)")
            agentResponseText = "Error: \(error.localizedDescription)"
            saveState()
        }
    }

    /// Replay last TTS audio
    func replayLastTTS() {
        Task {
            await ttsService.replay()
        }
    }

    /// Cancel current operation
    func cancelCurrentOperation() {
        currentOperationId = nil

        if isRecording {
            audioRecorder.stopRecording()
            isRecording = false
        }

        if ttsService.audioPlayer.isPlaying {
            ttsService.audioPlayer.stop()
        }

        stopPulseAnimation()

        print("🛑 TerminalAgentViewModel[\(sessionId)]: Cancelled current operation")
    }

    /// Reset state for new command
    func resetStateForNewCommand() {
        recognizedText = ""
        agentResponseText = ""
        accumulatedText = ""
        lastTTSedText = ""
        lastCompletionText = ""
        ttsService.reset()
        ttsTriggeredForCurrentResponse = false

        saveState()

        print("🔄 TerminalAgentViewModel[\(sessionId)]: State reset for new command")
    }

    /// Get current recording state
    func getCurrentState() -> RecordingState {
        if isRecording {
            return .recording
        } else if isTranscribing {
            return .transcribing
        } else if ttsService.audioPlayer.isPlaying {
            return .playingTTS
        } else if ttsService.isGenerating {
            return .generatingTTS
        } else if !recognizedText.isEmpty && agentResponseText.isEmpty {
            return .waitingForAgent
        } else if !agentResponseText.isEmpty {
            // Check if TTS is done
            if ttsService.lastAudioData != nil {
                return .idle
            } else if ttsTriggeredForCurrentResponse {
                return .generatingTTS
            } else {
                return .waitingForAgent
            }
        } else {
            return .idle
        }
    }

    // MARK: - Persistence

    /// Save state to UserDefaults (per terminal)
    func saveState() {
        let state: [String: Any] = [
            "recognizedText": recognizedText,
            "agentResponseText": agentResponseText,
            "accumulatedText": accumulatedText,
            "lastTTSedText": lastTTSedText,
            "lastTTSAudioData": ttsService.lastAudioData?.base64EncodedString() ?? ""
        ]
        UserDefaults.standard.set(state, forKey: persistenceKey)
        print("💾 TerminalAgentViewModel[\(sessionId)]: State saved")
    }

    /// Load state from UserDefaults (per terminal)
    func loadState() {
        guard let state = UserDefaults.standard.dictionary(forKey: persistenceKey) else {
            print("📂 TerminalAgentViewModel[\(sessionId)]: No saved state found")
            return
        }

        recognizedText = state["recognizedText"] as? String ?? ""
        agentResponseText = state["agentResponseText"] as? String ?? ""
        accumulatedText = state["accumulatedText"] as? String ?? ""
        lastTTSedText = state["lastTTSedText"] as? String ?? ""

        if let audioDataString = state["lastTTSAudioData"] as? String,
           !audioDataString.isEmpty,
           let audioData = Data(base64Encoded: audioDataString) {
            ttsService.lastAudioData = audioData
        }

        print("📂 TerminalAgentViewModel[\(sessionId)]: State loaded")
    }

    /// Clear state from UserDefaults (when terminal is closed)
    func clearState() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        resetStateForNewCommand()
        print("🗑️ TerminalAgentViewModel[\(sessionId)]: State cleared")
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Observe audio recorder state changes
        audioRecorder.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)

        audioRecorder.$isTranscribing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isTranscribing)

        audioRecorder.$recognizedText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.recognizedText = text
                self?.saveState()
            }
            .store(in: &cancellables)
    }

    private func connectToRecordingStream() {
        recordingStreamClient.connect(config: config, sessionId: sessionId) { [weak self] message in
            guard let self = self else { return }

            Task { @MainActor in
                self.handleRecordingStreamMessage(message)
            }
        }
    }

    private func handleRecordingStreamMessage(_ message: RecordingStreamMessage) {
        print("📨 TerminalAgentViewModel[\(sessionId)]: Received message, complete=\(message.isComplete ?? false)")

        // Update accumulated text
        accumulatedText = message.text

        // Check for completion
        if message.isComplete == true {
            let trimmedText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Strict duplicate check
            if lastCompletionText == trimmedText {
                print("⚠️ TerminalAgentViewModel[\(sessionId)]: Duplicate completion, ignoring")
                return
            }

            // Check if TTS already in progress
            if ttsService.isGenerating || ttsService.audioPlayer.isPlaying {
                print("⚠️ TerminalAgentViewModel[\(sessionId)]: TTS already in progress, ignoring")
                agentResponseText = message.text
                lastCompletionText = trimmedText
                saveState()
                return
            }

            // Check if we already have TTS for this exact text
            if lastTTSedText == trimmedText && ttsService.lastAudioData != nil {
                print("🔊 TerminalAgentViewModel[\(sessionId)]: Already have TTS, playing existing")
                agentResponseText = message.text
                lastCompletionText = trimmedText
                Task {
                    await ttsService.replay()
                }
                saveState()
                return
            }

            // All checks passed - process new completion
            print("✅ TerminalAgentViewModel[\(sessionId)]: New completion, generating TTS")
            agentResponseText = message.text
            lastCompletionText = trimmedText
            lastTTSedText = trimmedText
            ttsTriggeredForCurrentResponse = true

            // Generate TTS
            Task {
                await generateTTS(for: message.text)
            }

        } else {
            // Still accumulating
            print("📝 TerminalAgentViewModel[\(sessionId)]: Accumulating (\(message.text.count) chars)")
        }
    }

    private func generateTTS(for text: String) async {
        guard !text.isEmpty else { return }

        // Prevent screen sleep during TTS playback
        IdleTimerManager.shared.beginOperation("tts_playback_\(sessionId)")

        defer {
            // Always end operation, even if error occurs
            IdleTimerManager.shared.endOperation("tts_playback_\(sessionId)")
        }

        do {
            // Use TTSService to synthesize and play
            _ = try await ttsService.synthesizeAndPlay(
                text: text,
                config: config,
                speed: 1.0, // TODO: Get from settings
                language: "en" // TODO: Get from settings
            )

            print("✅ TerminalAgentViewModel[\(sessionId)]: TTS completed")
            saveState()

        } catch {
            print("❌ TerminalAgentViewModel[\(sessionId)]: TTS failed: \(error)")
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
    
    // MARK: - Cleanup
    
    deinit {
        // Cleanup: Cancel all Combine subscriptions
        cancellables.removeAll()
        
        // Cleanup: Disconnect recording stream
        recordingStreamClient.disconnect()
        
        // Cleanup: End all idle timer operations (must be called on main thread)
        Task { @MainActor in
            IdleTimerManager.shared.endAllOperations()
        }
        
        print("🧹 TerminalAgentViewModel[\(sessionId)]: Deinitialized")
    }
}
