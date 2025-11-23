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
        
        // If transcription is in progress, wait for it to complete
        if isTranscribing {
            print("⚠️ iOS AudioRecorder: Transcription in progress, waiting...")
            return
        }
        
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
        
        guard apiClient != nil else {
            print("❌ iOS AudioRecorder: No API client (not connected to laptop)")
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
        
        let transcriptionStartTime = Date()
        
        // Get ephemeral key for transcription
        guard let keys = settingsManager?.ephemeralKeys else {
            print("❌ iOS AudioRecorder: No ephemeral keys")
            DispatchQueue.main.async {
                self.recognizedText = "Error: No ephemeral keys. Please reconnect to laptop."
                self.isTranscribing = false
            }
            return
        }
        
        print("📱 iOS AudioRecorder: Starting transcription for file: \(url.path)")
        
        // Use ephemeral key with transcription service
        let service = TranscriptionService(apiKey: keys.openai)
        let language = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "auto"
        
        service.transcribe(audioFileURL: url, language: language == "auto" ? nil : language) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else {
                    print("⚠️ iOS AudioRecorder: Self deallocated during transcription")
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
                    
                    // Send transcribed text to laptop for command execution
                    self.sendCommandToLaptop(text: text)
                    
                case .failure(let error):
                    print("❌ Transcription error: \(error.localizedDescription)")
                    self.recognizedText = "Transcription error: \(error.localizedDescription)"
                    
                    // Clear file on error
                    if let url = self.recordingURL {
                        try? FileManager.default.removeItem(at: url)
                        self.recordingURL = nil
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
        
        Task {
            do {
                // Get or select session
                var sessionId: String
                
                if let selectedId = settings.selectedSessionId {
                    // Verify session still exists
                    let sessions = try await client.listSessions()
                    if sessions.contains(where: { $0.id == selectedId }) {
                        sessionId = selectedId
                    } else {
                        // Session no longer exists, get or create default
                        print("⚠️ Selected session no longer exists, getting default session")
                        var sessions = try await client.listSessions()
                        if sessions.isEmpty {
                            let newSession = try await client.createSession()
                            sessions = [newSession]
                        }
                        sessionId = sessions.first!.id
                        // Update on main thread - capture value before async call
                        let capturedSessionId = sessionId
                        await MainActor.run {
                            settings.selectedSessionId = capturedSessionId
                        }
                    }
                } else {
                    // No session selected, get or create default
                    var sessions = try await client.listSessions()
                    if sessions.isEmpty {
                        let newSession = try await client.createSession()
                        sessions = [newSession]
                    }
                    sessionId = sessions.first!.id
                    // Update on main thread - capture value before async call
                    let capturedSessionId = sessionId
                    await MainActor.run {
                        settings.selectedSessionId = capturedSessionId
                    }
                }
                
                print("   Session: \(sessionId)")
                
                let result: String
                
                // Execute based on selected mode
                switch settings.commandMode {
                case .agent:
                    // Execute command via AI agent
                    result = try await client.executeAgentCommand(sessionId: sessionId, command: text)
                    
                case .direct:
                    // Send command directly to terminal via WebSocket input (not HTTP API)
                    // This ensures commands work with cursor-agent and other interactive apps
                    // The command will be sent through WebSocket in RecordingView's notification handler
                    result = ""
                    
                    // Notify that command should be sent (will be sent via WebSocket in RecordingView)
                    // This allows RecordingView to send the command through WebSocket input
                    // which works better with interactive apps like cursor-agent
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CommandSentToTerminal"),
                        object: nil,
                        userInfo: ["command": text, "sessionId": sessionId]
                    )
                }
                
                let commandMode = settings.commandMode
                DispatchQueue.main.async {
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
                    }
                    
                    // TTS the result (or confirmation if empty)
                    // Clean result for TTS to avoid reading ANSI codes
                    let cleanedResult = self.cleanTerminalOutput(result)
                    let ttsText = cleanedResult.isEmpty ? "Command sent to terminal" : cleanedResult
                    self.speakResponse(ttsText)
                }
                
            } catch {
                DispatchQueue.main.async {
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
        
        // Remove control characters except newline and tab
        cleaned = cleaned.unicodeScalars.filter { scalar in
            let value = scalar.value
            // Keep printable ASCII (32-126), newline (10), and tab (9)
            return (value >= 32 && value <= 126) || value == 10 || value == 9
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
    private func speakResponse(_ text: String) {
        guard let keys = settingsManager?.ephemeralKeys else {
            return
        }
        
        print("🔊 Generating TTS for response...")
        
        Task {
            do {
                let ttsHandler = LocalTTSHandler(apiKey: keys.openai)
                let audioData = try await ttsHandler.synthesize(text: text)
                
                // Play audio
                DispatchQueue.main.async {
                    let player = AudioPlayer()
                    try? player.play(audioData: audioData)
                }
                
            } catch {
                print("❌ TTS error: \(error)")
            }
        }
    }
}

