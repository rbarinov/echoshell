//
//  AudioRecorder.swift
//  EchoShell Watch App
//
//  Created by Roman Barinov on 2025.11.20.
//

import AVFoundation
import Foundation

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var hasRecording = false
    @Published var recognizedText: String = ""
    @Published var isTranscribing = false
    @Published var lastRecordingDuration: TimeInterval = 0
    @Published var lastTranscriptionCost: Double = 0
    @Published var lastNetworkUsage: (sent: Int64, received: Int64) = (0, 0)
    @Published var lastTranscriptionDuration: TimeInterval = 0
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?
    private var transcriptionService: TranscriptionService?
    private var recordingStartTime: Date?
    
    private let watchConnectivity = WatchConnectivityManager.shared
    
    override init() {
        super.init()
        setupAudioSession()
        
        // Initialize transcription service with saved API key
        if !watchConnectivity.apiKey.isEmpty {
            self.transcriptionService = TranscriptionService(apiKey: watchConnectivity.apiKey)
        }
        
        // Listen for settings updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsUpdated),
            name: NSNotification.Name("SettingsUpdated"),
            object: nil
        )
    }
    
    @objc private func settingsUpdated() {
        updateTranscriptionService()
        print("AudioRecorder: Settings updated from iPhone")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func updateTranscriptionService() {
        if !watchConnectivity.apiKey.isEmpty {
            self.transcriptionService = TranscriptionService(apiKey: watchConnectivity.apiKey)
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
        let audioFilename = documentsPath.appendingPathComponent("recording.m4a")
        recordingURL = audioFilename
        
        // Delete previous recording if it exists
        if FileManager.default.fileExists(atPath: audioFilename.path) {
            try? FileManager.default.removeItem(at: audioFilename)
        }
        
        // Reset previous text and statistics
        recognizedText = ""
        isTranscribing = false
        lastRecordingDuration = 0
        lastTranscriptionCost = 0
        lastNetworkUsage = (0, 0)
        lastTranscriptionDuration = 0
        recordingStartTime = Date()
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,  // Reduced from 44100 to 16000 Hz (sufficient for speech)
            AVNumberOfChannelsKey: 1,  // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.low.rawValue,  // Reduced quality from high to low
            AVEncoderBitRateKey: 32000  // 32 kbps (instead of standard 128 kbps)
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            isRecording = true
            hasRecording = false // Reset until recording is complete
        } catch {
            print("Could not start recording: \(error)")
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        
        // Calculate recording duration
        if let startTime = recordingStartTime {
            lastRecordingDuration = Date().timeIntervalSince(startTime)
            
            // Whisper API: $0.006 per minute
            let minutes = lastRecordingDuration / 60.0
            lastTranscriptionCost = minutes * 0.006
            
            print("Recording duration: \(lastRecordingDuration)s, estimated cost: $\(lastTranscriptionCost)")
        }
    }
    
    func playRecording() {
        guard let url = recordingURL, FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("Could not play recording: \(error)")
        }
    }
    
    func stopPlaying() {
        audioPlayer?.stop()
        isPlaying = false
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            hasRecording = true
            // Start transcription via OpenAI Whisper
            transcribeWithAPI()
        }
    }
    
    private func transcribeWithAPI() {
        guard let url = recordingURL else {
            return
        }
        
        guard let service = transcriptionService else {
            recognizedText = "Error: No API key configured. Please set it in the iPhone app."
            return
        }
        
        isTranscribing = true
        recognizedText = ""
        
        let transcriptionStartTime = Date()
        
        // Get language from WatchConnectivityManager
        let language = watchConnectivity.transcriptionLanguage
        
        service.transcribe(audioFileURL: url, language: language) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                let transcriptionEndTime = Date()
                self.lastTranscriptionDuration = transcriptionEndTime.timeIntervalSince(transcriptionStartTime)
                self.isTranscribing = false
                
                switch result {
                case .success((let text, let networkUsage)):
                    self.recognizedText = text
                    self.lastNetworkUsage = networkUsage
                    print("Transcription successful: \(text)")
                    print("Network usage - Sent: \(networkUsage.sent) bytes, Received: \(networkUsage.received) bytes")
                    print("Transcription time: \(self.lastTranscriptionDuration)s")
                    
                    // Send statistics to iPhone
                    WatchConnectivityManager.shared.sendTranscriptionStats(
                        text: text,
                        recordingDuration: self.lastRecordingDuration,
                        transcriptionCost: self.lastTranscriptionCost,
                        processingTime: self.lastTranscriptionDuration,
                        uploadSize: networkUsage.sent,
                        downloadSize: networkUsage.received
                    )
                case .failure(let error):
                    print("Transcription error: \(error.localizedDescription)")
                    self.recognizedText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // Function to set recognized text (will be called from ContentView for manual dictation)
    func setRecognizedText(_ text: String) {
        recognizedText = text
        isTranscribing = false
    }
}

extension AudioRecorder: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}

