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
    private var transcriptionService: TranscriptionService?
    
    // NEW: Add settingsManager reference
    private var settingsManager: SettingsManager?
    private var apiClient: APIClient?
    
    override init() {
        super.init()
        setupAudioSession()
        
        // Listen for API key changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChange),
            name: NSNotification.Name("APIKeyChanged"),
            object: nil
        )
        
        // Initialize with current API key
        updateTranscriptionService()
    }
    
    // NEW: Initialize with settings manager
    func configure(with settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        
        if let config = settingsManager.laptopConfig {
            self.apiClient = APIClient(config: config)
        }
        
        print("📱 AudioRecorder: Configured with operation mode: \(settingsManager.operationMode.displayName)")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAPIKeyChange() {
        updateTranscriptionService()
    }
    
    private func updateTranscriptionService() {
        let apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        if !apiKey.isEmpty {
            self.transcriptionService = TranscriptionService(apiKey: apiKey)
        } else {
            self.transcriptionService = nil
        }
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
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording_ios.m4a")
        recordingURL = audioFilename
        
        // Delete previous recording if it exists
        if FileManager.default.fileExists(atPath: audioFilename.path) {
            try? FileManager.default.removeItem(at: audioFilename)
        }
        
        // Сбрасываем предыдущий текст и статистику
        recognizedText = ""
        isTranscribing = false
        lastRecordingDuration = 0
        lastTranscriptionCost = 0
        lastNetworkUsage = (0, 0)
        lastTranscriptionDuration = 0
        recordingStartTime = Date()
        
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
            audioRecorder?.record()
            isRecording = true
            print("📱 iOS AudioRecorder: Started recording")
        } catch {
            print("Could not start recording: \(error)")
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        
        // Вычисляем длительность записи
        if let startTime = recordingStartTime {
            lastRecordingDuration = Date().timeIntervalSince(startTime)
            
            // Whisper API: $0.006 за минуту
            let minutes = lastRecordingDuration / 60.0
            lastTranscriptionCost = minutes * 0.006
            
            print("📱 iOS AudioRecorder: Recording duration: \(lastRecordingDuration)s, estimated cost: $\(lastTranscriptionCost)")
        }
    }
}

// MARK: - AVAudioRecorderDelegate
extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            print("📱 iOS AudioRecorder: Recording finished successfully")
            
            // Check operation mode
            if let settings = settingsManager, settings.isLaptopMode {
                // Laptop mode: Send transcription request to laptop
                print("📱 iOS AudioRecorder: Using laptop mode")
                transcribeViaLaptop()
            } else {
                // Standalone mode: Direct OpenAI transcription (existing behavior)
                print("📱 iOS AudioRecorder: Using standalone mode")
                transcribeWithAPI()
            }
        } else {
            print("❌ iOS AudioRecorder: Recording failed")
        }
    }
}

// MARK: - Transcription
extension AudioRecorder {
    private func transcribeWithAPI() {
        guard let url = recordingURL else {
            print("❌ iOS AudioRecorder: No recording URL")
            return
        }
        
        guard let service = transcriptionService else {
            recognizedText = "Error: No API key configured. Please set it in Settings."
            print("❌ iOS AudioRecorder: No transcription service available")
            return
        }
        
        isTranscribing = true
        recognizedText = ""
        
        let transcriptionStartTime = Date()
        
        // Get language from UserDefaults
        let languageCode = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "auto"
        print("📱 iOS AudioRecorder: Starting transcription with language: \(languageCode)...")
        
        service.transcribe(audioFileURL: url, language: languageCode == "auto" ? nil : languageCode) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                let transcriptionEndTime = Date()
                self.lastTranscriptionDuration = transcriptionEndTime.timeIntervalSince(transcriptionStartTime)
                self.isTranscribing = false
                
                switch result {
                case .success((let text, let networkUsage)):
                    self.recognizedText = text
                    self.lastNetworkUsage = networkUsage
                    print("✅ iOS AudioRecorder: Transcription successful")
                    print("   Text: \(text.prefix(50))...")
                    print("   Network usage - Sent: \(networkUsage.sent) bytes, Received: \(networkUsage.received) bytes")
                    print("   Transcription time: \(self.lastTranscriptionDuration)s")
                    
                    // Also send stats to Watch if connected
                    self.sendStatsToWatch(text: text, uploadSize: networkUsage.sent, downloadSize: networkUsage.received)
                    
                case .failure(let error):
                    print("❌ iOS AudioRecorder: Transcription error: \(error.localizedDescription)")
                    self.recognizedText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
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
        guard let url = recordingURL else {
            recognizedText = "Error: No recording URL"
            return
        }
        
        guard apiClient != nil else {
            recognizedText = "Error: Not connected to laptop"
            return
        }
        
        isTranscribing = true
        recognizedText = ""
        
        let transcriptionStartTime = Date()
        
        // Get ephemeral key for transcription
        guard let keys = settingsManager?.ephemeralKeys else {
            recognizedText = "Error: No ephemeral keys. Please reconnect to laptop."
            isTranscribing = false
            return
        }
        
        // Use ephemeral key with transcription service
        let service = TranscriptionService(apiKey: keys.openai)
        let language = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "auto"
        
        service.transcribe(audioFileURL: url, language: language == "auto" ? nil : language) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                let transcriptionEndTime = Date()
                self.lastTranscriptionDuration = transcriptionEndTime.timeIntervalSince(transcriptionStartTime)
                self.isTranscribing = false
                
                switch result {
                case .success((let text, let networkUsage)):
                    self.recognizedText = text
                    self.lastNetworkUsage = networkUsage
                    
                    print("✅ Transcription via laptop successful")
                    print("   Text: \(text.prefix(50))...")
                    
                    // Send transcribed text to laptop for command execution
                    self.sendCommandToLaptop(text: text)
                    
                case .failure(let error):
                    print("❌ Transcription error: \(error.localizedDescription)")
                    self.recognizedText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // NEW: Send transcribed command to laptop
    private func sendCommandToLaptop(text: String) {
        guard let client = apiClient,
              settingsManager != nil else {
            return
        }
        
        print("📤 Sending command to laptop: \(text)")
        
        Task {
            do {
                // Get or create default session
                var sessions = try await client.listSessions()
                if sessions.isEmpty {
                    let newSession = try await client.createSession()
                    sessions = [newSession]
                }
                
                let sessionId = sessions.first!.id
                
                // Execute command via AI agent
                let result = try await client.executeAgentCommand(sessionId: sessionId, command: text)
                
                DispatchQueue.main.async {
                    self.recognizedText = "✅ Command executed:\n\n\(result)"
                    
                    // TTS the result
                    self.speakResponse(result)
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.recognizedText = "Error executing command: \(error.localizedDescription)"
                }
            }
        }
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

