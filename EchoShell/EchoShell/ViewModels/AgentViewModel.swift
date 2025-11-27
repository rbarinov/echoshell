//
//  AgentViewModel.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  ViewModel for agent-based voice command execution
//  Manages recording, transcription, command execution, and TTS playback
//

import Foundation
import Combine
import SwiftUI

/// ViewModel for agent-based voice command interface
/// Separates business logic from UI (RecordingView)
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

    // MARK: - Dependencies

    private let audioRecorder: AudioRecorder
    let ttsService: TTSService // Public for UI access (e.g., replay button, audio controls)
    private var apiClient: APIClient
    private let recordingStreamClient: RecordingStreamClient
    private var config: TunnelConfig

    // MARK: - Private State

    private var currentOperationTask: Task<Void, Never>?
    private var ttsTimer: Timer?
    private var lastOutputSnapshot: String = ""

    // MARK: - Initialization

    init(
        audioRecorder: AudioRecorder,
        ttsService: TTSService,
        apiClient: APIClient,
        recordingStreamClient: RecordingStreamClient,
        config: TunnelConfig
    ) {
        self.audioRecorder = audioRecorder
        self.ttsService = ttsService
        self.apiClient = apiClient
        self.recordingStreamClient = recordingStreamClient
        self.config = config

        setupBindings()
    }

    // MARK: - Public Methods

    /// Configure audio recorder with settings manager
    func configure(with settingsManager: SettingsManager) {
        audioRecorder.configure(with: settingsManager)
        // In Agent mode, disable autoSendCommand so commands are sent via executeCommand()
        // This ensures proper state management and TTS handling
        audioRecorder.autoSendCommand = false
        print("✅ AgentViewModel: AudioRecorder configured with settingsManager (autoSendCommand disabled)")
    }

    /// Update configuration (for example, when laptop config changes)
    func updateConfig(_ newConfig: TunnelConfig) {
        self.config = newConfig
        self.apiClient = APIClient(config: newConfig)
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
        // isRecording will be updated automatically via binding from audioRecorder.$isRecording
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
        // isRecording will be updated automatically via binding from audioRecorder.$isRecording
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

    /// Execute a text command (after transcription or manual input)
    func executeCommand(_ command: String, sessionId: String?) async {
        guard !command.isEmpty else {
            print("⚠️ AgentViewModel: Empty command, skipping execution")
            return
        }

        // Prevent screen sleep during command processing
        IdleTimerManager.shared.beginOperation("agent_processing")

        isProcessing = true
        let operationId = UUID()
        currentOperationId = operationId

        print("📤 AgentViewModel: Executing command: \(command)")

        defer {
            // Always end operation, even if error occurs
            IdleTimerManager.shared.endOperation("agent_processing")
        }

        do {
            // Execute command via API and get response
            let result = try await apiClient.executeAgentCommand(
                sessionId: sessionId,
                command: command
            )

            print("✅ AgentViewModel: Command executed successfully, result: \(result.prefix(100))...")

            // Update agent response text with the result
            agentResponseText = result
            isProcessing = false

            // Generate and play TTS for the response
            Task {
                await generateAndPlayTTS(text: result)
            }

        } catch {
            print("❌ AgentViewModel: Command execution failed: \(error)")
            agentResponseText = "Error: \(error.localizedDescription)"
            isProcessing = false
        }
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
            // End recording operation to allow screen sleep
            IdleTimerManager.shared.endOperation("recording")
            audioRecorder.stopRecording()
            // isRecording will be updated automatically via binding
        }

        // End any active operations
        IdleTimerManager.shared.endOperation("agent_processing")
        IdleTimerManager.shared.endOperation("tts_playback")

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
        // Priority order: recording > transcribing > playing > generating > waiting > idle
        if isRecording {
            return .recording
        } else if isTranscribing {
            return .transcribing
        } else if ttsService.audioPlayer.isPlaying {
            return .playingTTS
        } else if ttsService.isGenerating {
            return .generatingTTS
        } else if isProcessing {
            return .waitingForAgent
        } else if !recognizedText.isEmpty && agentResponseText.isEmpty {
            // We have a question but no answer yet
            return .waitingForAgent
        } else if !agentResponseText.isEmpty {
            // We have an answer - check if TTS is done
            if ttsService.lastAudioData != nil {
                // TTS was generated, we're done (idle)
                return .idle
            } else if ttsService.isGenerating {
                // TTS is generating
                return .generatingTTS
            } else {
                // Answer received but TTS not generated yet - waiting
                return .waitingForAgent
            }
        } else {
            return .idle
        }
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Observe audio recorder state changes
        audioRecorder.$isRecording
            .assign(to: &$isRecording)

        audioRecorder.$isTranscribing
            .assign(to: &$isTranscribing)

        audioRecorder.$recognizedText
            .assign(to: &$recognizedText)
    }

    private func handleRecordingStreamMessage(_ message: RecordingStreamMessage) {
        // Update accumulated text
        accumulatedForTTS = message.text

        // If complete, trigger TTS
        if message.isComplete == true {
            print("✅ AgentViewModel: Received complete response, triggering TTS")
            agentResponseText = message.text
            isProcessing = false

            // Generate and play TTS
            Task {
                await generateAndPlayTTS(text: message.text)
            }
        } else {
            // Still accumulating
            print("📝 AgentViewModel: Accumulating response (\(message.text.count) chars)")
        }
    }

    private func generateAndPlayTTS(text: String) async {
        guard !text.isEmpty else { return }

        // Check if we already spoke this text
        if lastTTSOutput == text.trimmingCharacters(in: .whitespacesAndNewlines) {
            print("⚠️ AgentViewModel: Already spoke this text, skipping")
            return
        }

        // Prevent screen sleep during TTS playback
        IdleTimerManager.shared.beginOperation("tts_playback")

        defer {
            // Always end operation, even if error occurs
            IdleTimerManager.shared.endOperation("tts_playback")
        }

        do {
            // Use TTSService to synthesize and play
            let audioData = try await ttsService.synthesizeAndPlay(
                text: text,
                config: config,
                speed: 1.0, // TODO: Get from settings
                language: "en" // TODO: Get from settings
            )

            // Update last spoken text
            lastTTSOutput = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Send TTS ready event to EventBus for RecordingView to handle playback
            // This ensures UI updates correctly and replay button works
            let operationId = currentOperationId?.uuidString ?? UUID().uuidString
            EventBus.shared.ttsReadyPublisher.send(
                EventBus.TTSReadyEvent(
                    audioData: audioData,
                    text: text,
                    operationId: operationId,
                    sessionId: nil // Global agent, not terminal-specific
                )
            )

            print("✅ AgentViewModel: TTS completed and event sent to EventBus")

        } catch {
            print("❌ AgentViewModel: TTS failed: \(error)")
            // Send TTS failed event
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
    
    // MARK: - Direct Mode TTS Scheduling
    
    /// Schedule auto TTS for direct mode terminal output
    /// - Parameters:
    ///   - lastTerminalOutput: Current terminal output from settings
    ///   - isHeadlessTerminal: Whether current session is headless terminal
    ///   - ttsSpeed: TTS playback speed
    ///   - language: TTS language
    func scheduleAutoTTS(
        lastTerminalOutput: String,
        isHeadlessTerminal: Bool,
        ttsSpeed: Double,
        language: String
    ) {
        let fullOutput = lastTerminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if fullOutput.isEmpty {
            print("🔇 AgentViewModel: scheduleAutoTTS - Skipped, no output")
            return
        }
        
        guard isHeadlessTerminal else {
            print("⚠️ AgentViewModel: scheduleAutoTTS - Not in headless terminal")
            return
        }
        
        print("🔊 AgentViewModel: scheduleAutoTTS - Scheduling TTS for output (\(fullOutput.count) chars)")
        
        // Cancel previous timer
        ttsTimer?.invalidate()
        ttsTimer = nil
        
        // Update accumulated TTS text
        accumulatedForTTS = fullOutput
        lastOutputSnapshot = fullOutput
        
        let threshold: TimeInterval = 5.0
        
        ttsTimer = Timer.scheduledTimer(withTimeInterval: threshold, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                let currentOutput = lastTerminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                print("🔊 AgentViewModel: scheduleAutoTTS - Timer fired (current: \(currentOutput.count), snapshot: \(self.lastOutputSnapshot.count))")
                
                if currentOutput == self.lastOutputSnapshot && !currentOutput.isEmpty {
                    print("🔊 AgentViewModel: scheduleAutoTTS - Output stable, starting TTS")
                    
                    let audioPlayer = self.ttsService.audioPlayer
                    if audioPlayer.isPlaying {
                        // Playing - extract new content and add to queue
                        let newContent = self.extractNewContent(from: currentOutput, after: self.lastTTSOutput)
                        if !newContent.isEmpty {
                            if !newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                if !self.ttsQueue.contains(newContent) {
                                    self.ttsQueue.append(newContent)
                                    print("🔊 AgentViewModel: Added to TTS queue (length: \(newContent.count))")
                                }
                            }
                        }
                    } else {
                        // Not playing - start playback
                        guard isHeadlessTerminal else {
                            print("⚠️ AgentViewModel: scheduleAutoTTS - No longer in headless terminal")
                            return
                        }
                        
                        print("🔊 AgentViewModel: scheduleAutoTTS - Starting playback")
                        await self.playAccumulatedTTS(
                            isHeadlessTerminal: isHeadlessTerminal,
                            ttsSpeed: ttsSpeed,
                            language: language
                        )
                    }
                } else {
                    print("🔊 AgentViewModel: scheduleAutoTTS - Output changed, rescheduling")
                }
            }
        }
    }
    
    /// Play accumulated TTS for direct mode
    func playAccumulatedTTS(
        isHeadlessTerminal: Bool,
        ttsSpeed: Double,
        language: String
    ) async {
        let accumulated = accumulatedForTTS.trimmingCharacters(in: .whitespacesAndNewlines)
        if accumulated.isEmpty {
            print("🔇 AgentViewModel: playAccumulatedTTS - Skipped, no accumulated text")
            return
        }
        
        guard isHeadlessTerminal else {
            print("⚠️ AgentViewModel: playAccumulatedTTS - Not in headless terminal")
            return
        }
        
        let audioPlayer = ttsService.audioPlayer
        if audioPlayer.isPlaying {
            return
        }
        
        guard !config.tunnelId.isEmpty else {
            print("⚠️ AgentViewModel: playAccumulatedTTS - No config")
            return
        }
        
        // Prevent screen sleep during TTS playback
        IdleTimerManager.shared.beginOperation("tts_playback")
        
        defer {
            IdleTimerManager.shared.endOperation("tts_playback")
        }
        
        do {
            _ = try await ttsService.synthesizeAndPlay(
                text: accumulated,
                config: config,
                speed: ttsSpeed,
                language: language,
                cleaningFunction: nil
            )
            
            lastTTSOutput = accumulated
            print("✅ AgentViewModel: playAccumulatedTTS - Completed")
            
        } catch {
            print("❌ AgentViewModel: playAccumulatedTTS - Error: \(error)")
        }
    }
    
    /// Process TTS queue after playback finishes
    func processQueueAfterPlayback(
        isHeadlessTerminal: Bool,
        lastTerminalOutput: String,
        ttsSpeed: Double,
        language: String
    ) async {
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        let audioPlayer = ttsService.audioPlayer
        while !ttsQueue.isEmpty {
            guard isHeadlessTerminal else {
                print("🔇 AgentViewModel: processQueueAfterPlayback - No longer in headless terminal")
                // Already on MainActor, no need for await MainActor.run
                ttsQueue = []
                if audioPlayer.isPlaying {
                    audioPlayer.stop()
                }
                return
            }
            
            let queuedText = ttsQueue.removeFirst()
            await generateAndPlayTTS(
                for: queuedText,
                isFromQueue: true,
                isHeadlessTerminal: isHeadlessTerminal,
                ttsSpeed: ttsSpeed,
                language: language
            )
            
            while audioPlayer.isPlaying {
                if !isHeadlessTerminal {
                    print("🔇 AgentViewModel: processQueueAfterPlayback - No longer in headless terminal during playback")
                    // Already on MainActor, no need for await MainActor.run
                    ttsQueue = []
                    if audioPlayer.isPlaying {
                        audioPlayer.stop()
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        
        // Check for more new content
        let currentOutput = lastTerminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let newContent = extractNewContent(from: currentOutput, after: lastTTSOutput)
        if !newContent.isEmpty {
            print("🔊 AgentViewModel: processQueueAfterPlayback - New content detected (\(newContent.count) chars)")
            accumulatedForTTS = currentOutput
            lastOutputSnapshot = currentOutput
            
            let threshold: TimeInterval = 5.0
            ttsTimer = Timer.scheduledTimer(withTimeInterval: threshold, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                
                Task { @MainActor in
                    let finalOutput = lastTerminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if finalOutput == self.lastOutputSnapshot && !finalOutput.isEmpty {
                        let finalNewContent = self.extractNewContent(from: finalOutput, after: self.lastTTSOutput)
                        if !finalNewContent.isEmpty {
                            if !finalNewContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                await self.generateAndPlayTTS(
                                    for: finalNewContent,
                                    isFromQueue: false,
                                    isHeadlessTerminal: isHeadlessTerminal,
                                    ttsSpeed: ttsSpeed,
                                    language: language
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Generate and play TTS for direct mode
    func generateAndPlayTTS(
        for text: String,
        isFromQueue: Bool = false,
        isHeadlessTerminal: Bool,
        ttsSpeed: Double,
        language: String
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            print("🔇 AgentViewModel: generateAndPlayTTS - Skipped, empty text")
            return
        }
        
        if !isFromQueue && !isHeadlessTerminal {
            print("⚠️ AgentViewModel: generateAndPlayTTS - Not in headless terminal")
            return
        }
        
        let audioPlayer = ttsService.audioPlayer
        if audioPlayer.isPlaying && !isFromQueue {
            return
        }
        
        if trimmed == lastTTSOutput {
            return
        }
        
        guard !config.tunnelId.isEmpty else {
            print("⚠️ AgentViewModel: generateAndPlayTTS - No config")
            return
        }
        
        // Prevent screen sleep during TTS playback
        IdleTimerManager.shared.beginOperation("tts_playback")
        
        defer {
            IdleTimerManager.shared.endOperation("tts_playback")
        }
        
        do {
            _ = try await ttsService.synthesizeAndPlay(
                text: trimmed,
                config: config,
                speed: ttsSpeed,
                language: language,
                cleaningFunction: nil
            )
            
            if isFromQueue && !lastTTSOutput.isEmpty {
                let separator = lastTTSOutput.hasSuffix(".") || lastTTSOutput.hasSuffix("!") || lastTTSOutput.hasSuffix("?")
                    ? " "
                    : "\n\n"
                lastTTSOutput = lastTTSOutput + separator + trimmed
            } else {
                lastTTSOutput = accumulatedForTTS.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            print("✅ AgentViewModel: generateAndPlayTTS - Completed")
            
        } catch {
            print("❌ AgentViewModel: generateAndPlayTTS - Error: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Extract new content that hasn't been spoken yet
    private func extractNewContent(from fullOutput: String, after spokenOutput: String) -> String {
        if spokenOutput.isEmpty {
            return fullOutput
        }
        
        if let range = fullOutput.range(of: spokenOutput) {
            let newStart = range.upperBound
            return String(fullOutput[newStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return fullOutput
    }
    
    
    // MARK: - State Persistence
    
    /// Load state from UserDefaults
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
    
    /// Save state to UserDefaults
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
    
    /// Connect to recording stream (public for external use)
    func connectToRecordingStream(sessionId: String?) {
        guard let sessionId = sessionId else {
            print("⚠️ AgentViewModel: No session ID for recording stream")
            return
        }
        
        recordingStreamClient.connect(config: config, sessionId: sessionId) { [weak self] message in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.handleRecordingStreamMessage(message)
            }
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Cleanup: Cancel any ongoing operations
        currentOperationTask?.cancel()
        currentOperationTask = nil
        
        // Cleanup: Invalidate timer (must be on main thread)
        // Note: Timer is already on main thread since ViewModel is @MainActor
        ttsTimer?.invalidate()
        ttsTimer = nil
        
        // Cleanup: End all idle timer operations (must be called on main thread)
        Task { @MainActor in
            IdleTimerManager.shared.endAllOperations()
        }
        
        // Cleanup: Disconnect recording stream
        recordingStreamClient.disconnect()
        
        print("🧹 AgentViewModel: Deinitialized")
    }
}

// MARK: - State Persistence Data

private struct RecordingStateData: Codable {
    let recognizedText: String
    let agentResponseText: String
    let lastTTSOutput: String
}
