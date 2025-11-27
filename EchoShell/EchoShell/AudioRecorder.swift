//
//  AudioRecorder.swift
//  EchoShell (iOS)
//
//  Created by Roman Barinov on 2025.11.21.
//

import AVFoundation
import Foundation

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var recognizedText: String = ""
    @Published var lastRecordingDuration: TimeInterval = 0
    @Published var lastTranscriptionCost: Double = 0
    @Published var lastTranscriptionDuration: TimeInterval = 0
    @Published var lastNetworkUsage: (sent: Int64, received: Int64) = (0, 0)
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingStartTime: Date?
    
    // Settings manager and API client for laptop mode
    private var settingsManager: SettingsManager?
    private var apiClient: APIClient?
    
    // Operation cancellation tracking
    @Published var currentOperationId: UUID? = nil
    
    // Flag to control automatic command sending to agent
    // When false, commands are not sent via executeAgentCommand (for terminal detail pages)
    var autoSendCommand: Bool = true
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    // NEW: Initialize with settings manager
    func configure(with settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        
        // Update API client when config changes
        updateAPIClient()
        
        print("📱 AudioRecorder: Configured with operation mode: Laptop Mode (Terminal Control)")
    }
    
    // Update API client when config changes
    private func updateAPIClient() {
        if let config = settingsManager?.laptopConfig {
            self.apiClient = APIClient(config: config)
            print("📱 AudioRecorder: API client updated with new config")
        } else {
            self.apiClient = nil
            print("📱 AudioRecorder: API client cleared (no config)")
        }
    }
    
    deinit {
        // Cleanup if needed
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func startRecording() {
        // If already recording, don't start a new one
        guard !isRecording else {
            print("⚠️ iOS AudioRecorder: Already recording, ignoring start request")
            return
        }
        
        // Cancel any ongoing transcription (we'll ignore its result)
        if isTranscribing {
            print("🛑 iOS AudioRecorder: Cancelling ongoing transcription for new recording")
            isTranscribing = false
        }
        
        // Invalidate current operation ID to mark all callbacks as stale
        let newOperationId = UUID()
        currentOperationId = newOperationId
        print("🛑 iOS AudioRecorder: New operation ID: \(newOperationId)")
        
        // Update API client before recording (in case config changed)
        updateAPIClient()
        
        // Clear previous file if it exists
        if let oldURL = recordingURL {
            try? FileManager.default.removeItem(at: oldURL)
            recordingURL = nil
        }
        
        // Create unique filename with timestamp to avoid conflicts
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording_ios_\(timestamp).m4a")
        recordingURL = audioFilename
        
        // Reset previous text and statistics (on main thread)
        DispatchQueue.main.async {
            self.recognizedText = ""
            self.isTranscribing = false
            self.lastRecordingDuration = 0
            self.lastTranscriptionCost = 0
            self.lastNetworkUsage = (0, 0)
            self.lastTranscriptionDuration = 0
        }
        recordingStartTime = Date()
        
        print("📱 AudioRecorder: Starting new recording, state reset")
        print("   File: \(audioFilename.path)")
        
        // Configure audio session for recording
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // First deactivate to reset state
            try audioSession.setActive(false)
            // Set category for recording
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            // Activate with options to interrupt other audio
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("✅ iOS AudioRecorder: Audio session configured for recording")
        } catch {
            print("⚠️ iOS AudioRecorder: Failed to configure audio session: \(error)")
            DispatchQueue.main.async {
                self.recognizedText = "Audio session error: \(error.localizedDescription)"
                self.isRecording = false
                self.recordingURL = nil
            }
            return
        }
        
        // Optimized settings for speech (same as Watch)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,  // Optimized for speech
            AVNumberOfChannelsKey: 1,  // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.low.rawValue,
            AVEncoderBitRateKey: 32000  // 32 kbps
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            
            // Prepare recorder before starting
            guard audioRecorder?.prepareToRecord() == true else {
                print("❌ iOS AudioRecorder: Failed to prepare recorder")
                DispatchQueue.main.async {
                    self.recognizedText = "Failed to prepare recorder. Please try again."
                    self.isRecording = false
                    self.recordingURL = nil
                }
                return
            }
            
            // Check that recording started successfully
            guard audioRecorder?.record() == true else {
                print("❌ iOS AudioRecorder: Failed to start recording (record() returned false)")
                DispatchQueue.main.async {
                    self.recognizedText = "Failed to start recording. Please check microphone permissions."
                    self.isRecording = false
                    self.recordingURL = nil
                }
                return
            }
            
            DispatchQueue.main.async {
                self.isRecording = true
            }
            print("📱 iOS AudioRecorder: Started recording successfully")
        } catch {
            print("❌ iOS AudioRecorder: Could not start recording: \(error)")
            DispatchQueue.main.async {
                self.recognizedText = "Recording error: \(error.localizedDescription)"
                self.isRecording = false
                self.recordingURL = nil
            }
        }
    }
    
    func stopRecording() {
        guard let recorder = audioRecorder else {
            print("⚠️ iOS AudioRecorder: No recorder to stop")
            DispatchQueue.main.async {
                self.isRecording = false
            }
            return
        }
        
        // Calculate recording duration before stopping
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            
            // Whisper API: $0.006 per minute
            let minutes = duration / 60.0
            let cost = minutes * 0.006
            
            print("📱 iOS AudioRecorder: Recording duration: \(duration)s, estimated cost: $\(cost)")
            
            // Check minimum duration (0.5 seconds)
            if duration < 0.5 {
                print("⚠️ iOS AudioRecorder: Recording too short (\(duration)s), aborting")
                recorder.stop()
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.recognizedText = "Recording too short. Please speak longer."
                    self.isTranscribing = false
                }
                // Clear file
                if let url = recordingURL {
                    try? FileManager.default.removeItem(at: url)
                }
                recordingURL = nil
                return
            }
            
            // Update duration and cost on main thread
            DispatchQueue.main.async {
                self.lastRecordingDuration = duration
                self.lastTranscriptionCost = cost
            }
        }
        
        // Stop recording
        recorder.stop()
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        // Don't clear recordingURL immediately - it's needed for transcription
        // Will clear it after successful transcription
        print("📱 iOS AudioRecorder: Recording stopped, waiting for delegate callback")
    }
}

// MARK: - AVAudioRecorderDelegate
extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        print("📱 iOS AudioRecorder: Delegate callback - success: \(flag)")
        
        guard flag else {
            print("❌ iOS AudioRecorder: Recording failed")
            // Check if file exists
            if let url = recordingURL, FileManager.default.fileExists(atPath: url.path) {
                print("⚠️ iOS AudioRecorder: File exists despite failure flag, attempting transcription anyway")
                // Try to transcribe even if failure flag
                transcribeViaLaptop()
            } else {
                print("❌ iOS AudioRecorder: No valid recording file")
                DispatchQueue.main.async {
                    self.recognizedText = "Recording failed. Please try again."
                    self.isTranscribing = false
                    self.recordingURL = nil
                }
            }
            return
        }
        
        // Check that file actually exists and is not empty
        guard let url = recordingURL else {
            print("❌ iOS AudioRecorder: No recording URL")
            DispatchQueue.main.async {
                self.recognizedText = "Error: No recording file found."
                self.isTranscribing = false
            }
            return
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ iOS AudioRecorder: Recording file does not exist at path: \(url.path)")
            DispatchQueue.main.async {
                self.recognizedText = "Error: Recording file not found."
                self.isTranscribing = false
                self.recordingURL = nil
            }
            return
        }
        
        // Check file size (should be greater than 0)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64, fileSize == 0 {
                print("❌ iOS AudioRecorder: Recording file is empty")
                DispatchQueue.main.async {
                    self.recognizedText = "Recording file is empty. Please try again."
                    self.isTranscribing = false
                    try? FileManager.default.removeItem(at: url)
                    self.recordingURL = nil
                }
                return
            }
            print("📱 iOS AudioRecorder: Recording file size: \(attributes[.size] ?? "unknown") bytes")
        } catch {
            print("⚠️ iOS AudioRecorder: Could not check file attributes: \(error)")
        }
        
        print("📱 iOS AudioRecorder: Recording finished successfully, starting transcription")
        
        // Always use laptop mode transcription
        print("📱 iOS AudioRecorder: Using laptop mode")
        transcribeViaLaptop()
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("❌ iOS AudioRecorder: Encode error - \(error?.localizedDescription ?? "Unknown")")
        if let error = error {
            print("   Error details: \(error)")
        }
        DispatchQueue.main.async {
            self.recognizedText = "Recording encoding error: \(error?.localizedDescription ?? "Unknown error"). Please try again."
            self.isTranscribing = false
            self.isRecording = false
                    // Clear file on error
            if let url = self.recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
            self.recordingURL = nil
        }
    }
}

// MARK: - Transcription
extension AudioRecorder {
    private func sendStatsToWatch(text: String, uploadSize: Int64, downloadSize: Int64) {
        // Post notification for Watch connectivity to pick up
        let _: [String: Any] = [
            "text": text,
            "recordingDuration": lastRecordingDuration,
            "transcriptionCost": lastTranscriptionCost,
            "processingTime": lastTranscriptionDuration,
            "uploadSize": uploadSize,
            "downloadSize": downloadSize
        ]
        
        print("📤 iOS AudioRecorder: Posting stats for potential Watch sync")
        
        // Could send to Watch via WatchConnectivity here if needed
        // For now, just keep it local
    }
    
    // NEW: Laptop mode transcription
    private func transcribeViaLaptop() {
        // Check URL again
        guard let url = recordingURL else {
            print("❌ iOS AudioRecorder: No recording URL for transcription")
            DispatchQueue.main.async {
                self.recognizedText = "Error: No recording URL"
                self.isTranscribing = false
            }
            return
        }
        
        // Check file existence
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ iOS AudioRecorder: Recording file does not exist: \(url.path)")
            DispatchQueue.main.async {
                self.recognizedText = "Error: Recording file not found"
                self.isTranscribing = false
                self.recordingURL = nil
            }
            return
        }

        // Check for laptop connection via settingsManager.laptopConfig (single source of truth)
        guard let laptopConfig = settingsManager?.laptopConfig else {
            print("❌ iOS AudioRecorder: Not connected to laptop (no laptop config)")
            DispatchQueue.main.async {
                self.recognizedText = "Error: Not connected to laptop"
                self.isTranscribing = false
            }
            return
        }

        DispatchQueue.main.async {
            self.isTranscribing = true
            self.recognizedText = ""
        }

        // Notify RecordingView to clear terminal output when transcription starts
        Task { @MainActor in
            EventBus.shared.transcriptionStarted = true
        }

        let transcriptionStartTime = Date()

        print("📱 iOS AudioRecorder: Starting transcription for file: \(url.path)")
        // Build STT endpoint from laptop config (proxy endpoint via tunnel)
        let sttEndpoint = "\(laptopConfig.apiBaseUrl)/proxy/stt/transcribe"
        let service = TranscriptionService(laptopAuthKey: laptopConfig.authKey, endpoint: sttEndpoint)
        let language = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "auto"
        
        // Store the recording URL and operation ID at transcription start to check if it's still valid
        let transcriptionURL = url
        let transcriptionOperationId = currentOperationId
        
        service.transcribe(audioFileURL: url, language: language == "auto" ? nil : language) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else {
                    print("⚠️ iOS AudioRecorder: Self deallocated during transcription")
                    return
                }
                
                // Check if transcription was cancelled (new recording started or operation ID changed)
                if self.recordingURL != transcriptionURL || 
                   self.recordingURL == nil ||
                   self.currentOperationId != transcriptionOperationId {
                    print("⚠️ iOS AudioRecorder: Transcription result ignored - operation cancelled (new recording started)")
                    self.isTranscribing = false
                    return
                }
                
                let transcriptionEndTime = Date()
                self.lastTranscriptionDuration = transcriptionEndTime.timeIntervalSince(transcriptionStartTime)
                self.isTranscribing = false
                
                switch result {
                case .success((let text, let networkUsage)):
                    // Check that text is not empty
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        print("⚠️ iOS AudioRecorder: Transcription returned empty text")
                        self.recognizedText = "No speech detected. Please try again."
                        return
                    }
                    
                    self.recognizedText = text
                    self.lastNetworkUsage = networkUsage
                    
                    print("✅ Transcription via laptop successful")
                    print("   Text: \(text.prefix(50))...")
                    
                    // Clear file after successful transcription
                    if let url = self.recordingURL {
                        try? FileManager.default.removeItem(at: url)
                        self.recordingURL = nil
                    }
                    
                    // Notify that transcription is complete
                    Task { @MainActor in
                        EventBus.shared.transcriptionStarted = false
                        EventBus.shared.transcriptionCompletedPublisher.send(
                            EventBus.TranscriptionResult(
                                text: text,
                                language: language == "auto" ? nil : language,
                                duration: self.lastTranscriptionDuration
                            )
                        )
                    }
                    
                    // Send transcribed text to laptop for command execution
                    // Only send if autoSendCommand is enabled (default: true)
                    // This can be disabled for terminal detail pages where commands are sent directly to terminal
                    if self.autoSendCommand {
                        self.sendCommandToLaptop(text: text)
                    }
                    
                case .failure(let error):
                    let errorDescription = error.localizedDescription
                    print("❌ Transcription error: \(errorDescription)")
                    print("❌ Transcription error details: \(error)")
                    
                    // Check if this is a network error that might be transient
                    let isNetworkError = errorDescription.contains("network") || 
                                        errorDescription.contains("timeout") ||
                                        errorDescription.contains("connection") ||
                                        errorDescription.contains("HTTP 5")
                    
                    // For network errors, don't show error immediately - allow retry
                    if isNetworkError {
                        print("⚠️ Network error detected, will retry transcription")
                        // Reset state to allow retry
                        self.isTranscribing = false
                        // Clear recognizedText to allow retry
                        self.recognizedText = ""
                    } else {
                        // For other errors, show error message
                        self.recognizedText = "Transcription error: \(errorDescription)"
                        
                        // Clear file on error
                        if let url = self.recordingURL {
                            try? FileManager.default.removeItem(at: url)
                            self.recordingURL = nil
                        }
                        
                        // Reset transcription state to allow retry
                        self.isTranscribing = false
                        
                        // Clear recognizedText after a delay to allow user to see the error
                        // This ensures next attempt can start fresh
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            if self.recognizedText == "Transcription error: \(errorDescription)" {
                                self.recognizedText = ""
                            }
                        }
                    }
                }
            }
        }
    }
    
    // NEW: Send transcribed command to laptop
    private func sendCommandToLaptop(text: String) {
        guard let client = apiClient,
              let settings = settingsManager else {
            return
        }
        
        print("📤 Sending command to laptop: \(text)")
        print("   Mode: \(settings.commandMode.displayName)")
        
        // Store operation ID to check if cancelled
        let commandOperationId = currentOperationId
        
        Task {
            // Check cancellation at start
            guard currentOperationId == commandOperationId else {
                print("⚠️ iOS AudioRecorder: Command execution cancelled - operation ID changed")
                return
            }
            
            do {
                let result: String
                
                // Execute based on selected mode
                switch settings.commandMode {
                case .agent:
                    // Agent mode: execute command via AI agent without requiring terminal session
                    // Session will be auto-created if needed for terminal commands
                    print("   Agent mode: executing without terminal session requirement")
                    result = try await client.executeAgentCommand(sessionId: nil, command: text)
                    
                case .direct:
                    // Direct mode: requires terminal session
                    var sessions = try await client.listSessions()
                    var targetSession: TerminalSession?
                    
                    if let selectedId = settings.selectedSessionId,
                       let existing = sessions.first(where: { $0.id == selectedId }) {
                        targetSession = existing
                    } else {
                        print("⚠️ Selected session missing, selecting default")
                        if sessions.isEmpty {
                            let newSession = try await client.createSession()
                            sessions = [newSession]
                        }
                        targetSession = sessions.first
                        if let capturedSession = targetSession {
                            let capturedSessionId = capturedSession.id
                            await MainActor.run {
                                settings.selectedSessionId = capturedSessionId
                            }
                        }
                    }
                    
                    guard let activeSession = targetSession else {
                        throw NSError(domain: "AudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "No terminal session available"])
                    }
                    
                    let sessionId = activeSession.id
                    print("   Session: \(sessionId) [type: \(activeSession.terminalType.rawValue)]")
                    
                    result = ""
                    let capturedSessionId = sessionId
                    
                    if activeSession.terminalType.isHeadless {
                        _ = try await client.executeCommand(sessionId: sessionId, command: text)
                        await MainActor.run {
                            EventBus.shared.commandSentPublisher.send(
                                EventBus.CommandEvent(
                                    command: text,
                                    sessionId: capturedSessionId,
                                    transport: "headless"
                                )
                            )
                        }
                    } else {
                        await MainActor.run {
                            EventBus.shared.commandSentPublisher.send(
                                EventBus.CommandEvent(
                                    command: text,
                                    sessionId: capturedSessionId,
                                    transport: "interactive"
                                )
                            )
                        }
                    }
                }
                
                // Check cancellation before processing result
                guard currentOperationId == commandOperationId else {
                    print("⚠️ iOS AudioRecorder: Command result ignored - operation cancelled")
                    return
                }
                
                let commandMode = settings.commandMode
                await MainActor.run {
                    // Check cancellation again on main thread
                    guard self.currentOperationId == commandOperationId else {
                        print("⚠️ iOS AudioRecorder: Command result ignored on main thread - operation cancelled")
                        return
                    }
                    
                    if commandMode == .direct {
                        // In direct mode, show command text initially
                        // Terminal output will be updated via WebSocket subscription
                        self.recognizedText = text
                    } else {
                        // Agent mode - clean result from ANSI codes and show only the result text
                        let cleanedResult = self.cleanTerminalOutput(result)
                        
                        // Show only the result text, without command text or status messages
                        // This matches what Cursor shows - just the result, no code quoting
                        let finalText = cleanedResult.isEmpty ? "Command executed" : cleanedResult
                        self.recognizedText = finalText
                        
                        // Update lastTerminalOutput in agent mode so state correctly transitions to idle
                        // This ensures we don't show "waiting for agent" after response is received
                        if let settingsManager = self.settingsManager {
                            settingsManager.lastTerminalOutput = finalText
                        }
                    }
                    
                    // TTS the result (or confirmation if empty)
                    // Clean result for TTS to avoid reading ANSI codes
                    let cleanedResult = self.cleanTerminalOutput(result)
                    let ttsText = cleanedResult.isEmpty ? "Command sent to terminal" : cleanedResult
                    self.speakResponse(ttsText)
                }
                
            } catch {
                await MainActor.run {
                    self.recognizedText = "Error executing command: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // Clean terminal output for display (remove ANSI sequences, keep text readable)
    private func cleanTerminalOutput(_ output: String) -> String {
        var cleaned = output
        
        // Remove ANSI escape sequences (needed for clean display)
        cleaned = cleaned.replacingOccurrences(
            of: "\\u{001B}\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
        
        // Remove control characters except newline and tab, but keep all Unicode characters (including Cyrillic)
        cleaned = cleaned.unicodeScalars.filter { scalar in
            let value = scalar.value
            // Keep printable ASCII (32-126), newline (10), tab (9), and all Unicode characters (including Cyrillic)
            if (value >= 32 && value <= 126) || value == 10 || value == 9 {
                return true
            }
            // Keep Unicode characters (including Cyrillic, emoji, etc.)
            if value >= 0x80 && value <= 0x10FFFF {
                // Filter out control characters but keep printable Unicode
                return !CharacterSet.controlCharacters.contains(scalar)
            }
            return false
        }.map { Character($0) }.reduce("") { $0 + String($1) }
        
        // Convert tabs to spaces
        cleaned = cleaned.replacingOccurrences(of: "\t", with: "    ")
        
        // Normalize line endings
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "\n")
        
        // Remove leading/trailing whitespace but keep structure
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    // NEW: TTS for laptop responses
    private func speakResponse(_ text: String, operationId: UUID? = nil) {
        guard let laptopConfig = settingsManager?.laptopConfig else {
            print("⚠️ No laptop config for TTS")
            return
        }
        
        // Use provided operation ID or current one
        let ttsOperationId = operationId ?? currentOperationId
        
        print("🔊 Generating TTS for response... (operation ID: \(ttsOperationId?.uuidString ?? "nil"))")
        
        // Notify that TTS generation has started
        Task { @MainActor in
            EventBus.shared.ttsGenerating = true
        }
        
        Task {
            // Check cancellation at start
            guard currentOperationId == ttsOperationId else {
                print("⚠️ iOS AudioRecorder: TTS generation cancelled - operation ID changed")
                return
            }
            
            do {
                // Build TTS endpoint from laptop config (proxy endpoint via tunnel)
                let ttsEndpoint = "\(laptopConfig.apiBaseUrl)/proxy/tts/synthesize"
                let ttsHandler = LocalTTSHandler(laptopAuthKey: laptopConfig.authKey, endpoint: ttsEndpoint)
                let language = settingsManager?.transcriptionLanguage.rawValue
                let speed = settingsManager?.ttsSpeed ?? 1.0
                // Voice is controlled by server configuration (TTS_VOICE env var), not sent from client
                let audioData = try await ttsHandler.synthesize(text: text, speed: speed, language: language)
                
                // Check cancellation before posting notification
                guard currentOperationId == ttsOperationId else {
                    print("⚠️ iOS AudioRecorder: TTS audio ignored - operation cancelled")
                    return
                }
                
                // Play audio - use EventBus to notify RecordingView
                await MainActor.run {
                    // Check cancellation again on main thread
                    guard self.currentOperationId == ttsOperationId else {
                        print("⚠️ iOS AudioRecorder: TTS audio ignored on main thread - operation cancelled")
                        return
                    }
                    
                    EventBus.shared.ttsGenerating = false
                    EventBus.shared.ttsReadyPublisher.send(
                        EventBus.TTSReadyEvent(
                            audioData: audioData,
                            text: text,
                            operationId: ttsOperationId?.uuidString ?? "",
                            sessionId: nil // Global agent, not terminal-specific
                        )
                    )
                }
                
            } catch {
                // Check cancellation before showing error
                guard currentOperationId == ttsOperationId else {
                    print("⚠️ iOS AudioRecorder: TTS error ignored - operation cancelled")
                    return
                }
                
                print("❌ TTS error: \(error)")
                
                // Reset TTS generation state
                await MainActor.run {
                    EventBus.shared.ttsGenerating = false
                    EventBus.shared.ttsFailedPublisher.send(
                        EventBus.TTSError.synthesisFailed(message: error.localizedDescription)
                    )
                }
            }
        }
    }
    
    // Cancel transcription (mark as cancelled to ignore results)
    func cancelTranscription() {
        print("🛑 iOS AudioRecorder: Cancelling transcription")
        isTranscribing = false
        // Invalidate operation ID to ignore any pending callbacks
        currentOperationId = UUID()
    }
    
    private func selectVoiceForLanguage(_ language: TranscriptionLanguage) -> String {
        switch language {
        case .russian:
            return "nova" // Good for Russian
        case .english:
            return "alloy" // Good for English
        case .georgian:
            return "echo" // Neutral voice
        case .auto:
            return "alloy" // Default neutral voice
        }
    }
}

