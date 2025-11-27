//
//  AudioPlayer.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Handles audio playback for TTS responses
//

import AVFoundation
import MediaPlayer

class AudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var isPaused = false
    
    private var player: AVAudioPlayer?
    private var nowPlayingInfo: [String: Any] = [:]
    private var fadeOutTimer: Timer?
    private let fadeOutDuration: TimeInterval = 0.2 // 200ms fade out
    private var tempAudioFile: URL? // Temporary file path for MP3 playback cleanup
    
    func play(audioData: Data, title: String = "AI Assistant Response") async throws {
        // Stop any existing playback
        stop()
        
        // Cancel any existing fade out
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
        
        // Configure audio session for playback
        // IMPORTANT: Deactivate first to reset any recording state, then configure for playback
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Log current audio session state
            print("🔊 AudioPlayer: Current audio session state:")
            print("   Category: \(audioSession.category.rawValue)")
            print("   Mode: \(audioSession.mode.rawValue)")
            print("   Is active: \(audioSession.isOtherAudioPlaying ? "other playing" : "available")")
            
            // First, deactivate to reset state (especially if coming from recording)
            // Use .notifyOthersOnDeactivation to properly release recording resources
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            print("🔊 AudioPlayer: Deactivated audio session to reset state")
            
            // Small delay to allow audio hardware to fully release recording resources
            // This is critical for proper transition from recording to playback
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
            // Set category for playback with speaker output
            // Use .playAndRecord with .defaultToSpeaker to ensure audio plays through speaker
            // This is necessary because .defaultToSpeaker option only works with .playAndRecord category
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            print("🔊 AudioPlayer: Set audio category to .playAndRecord with .defaultToSpeaker")
            
            // Activate audio session for playback
            // Don't use .notifyOthersOnDeactivation here - we want to take control
            try audioSession.setActive(true)
            print("🔊 AudioPlayer: Activated audio session for playback")
            
            // Verify audio session is configured correctly
            print("🔊 AudioPlayer: Audio session configured:")
            print("   Category: \(audioSession.category.rawValue)")
            print("   Mode: \(audioSession.mode.rawValue)")
            print("   Output volume: \(audioSession.outputVolume)")
            print("   Current route: \(audioSession.currentRoute.description)")
            
        } catch {
            print("❌ AudioPlayer: Failed to configure audio session: \(error)")
            throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to configure audio session: \(error.localizedDescription)"])
        }
        
        print("🔊 AudioPlayer: Creating AVAudioPlayer with \(audioData.count) bytes of audio data")
        
        do {
            // Try to create player from data directly first
            // If that fails, save to temporary file and play from file (for MP3 support)
            var playerCreated = false
            
            // First attempt: try direct data initialization
            if let directPlayer = try? AVAudioPlayer(data: audioData) {
                // Check if player is valid by checking duration
                if directPlayer.duration > 0 {
                    player = directPlayer
                    playerCreated = true
                    print("🔊 AudioPlayer: Created player from data directly (duration: \(directPlayer.duration)s)")
                } else {
                    print("⚠️ AudioPlayer: Direct data player has zero duration, will try file method")
                }
            }
            
            // Second attempt: if direct method failed, save to temp file and play from file
            // This is more reliable for MP3 and other formats
            if !playerCreated {
                // Create temporary file
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp3")
                
                do {
                    try audioData.write(to: tempFile)
                    print("🔊 AudioPlayer: Saved audio to temp file: \(tempFile.path)")
                    
                    // Create player from file
                    player = try AVAudioPlayer(contentsOf: tempFile)
                    playerCreated = true
                    print("🔊 AudioPlayer: Created player from file (duration: \(player?.duration ?? 0)s)")
                    
                    // Clean up temp file after playback completes (handled in delegate)
                    // Store temp file path for cleanup
                    tempAudioFile = tempFile
                } catch {
                    print("❌ AudioPlayer: Failed to create player from file: \(error)")
                    // Clean up temp file if it was created
                    try? FileManager.default.removeItem(at: tempFile)
                    throw error
                }
            }
            
            guard playerCreated, let audioPlayer = player else {
                throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio player"])
            }
            
            audioPlayer.delegate = self
            
            // Set volume to maximum and enable playback
            audioPlayer.volume = 1.0
            audioPlayer.enableRate = false // Disable rate control for normal playback
            
            // Verify audio session is still active
            let audioSession = AVAudioSession.sharedInstance()
            if !audioSession.isOtherAudioPlaying {
                // Ensure audio session is active before playing
                try? audioSession.setActive(true)
            }
            
            print("🔊 AudioPlayer: Preparing to play (format: \(audioPlayer.format.description), duration: \(audioPlayer.duration)s, volume: \(audioPlayer.volume))")
            let prepared = audioPlayer.prepareToPlay()
            print("🔊 AudioPlayer: prepareToPlay() returned: \(prepared)")
            
            if !prepared {
                print("❌ AudioPlayer: prepareToPlay() failed - audio format may not be supported")
                throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare audio for playback"])
            }
            
            // Verify player is ready
            if audioPlayer.duration <= 0 {
                print("❌ AudioPlayer: Invalid audio duration (\(audioPlayer.duration)s)")
                throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio duration"])
            }
            
            // Play audio
            let success = audioPlayer.play()
            print("🔊 AudioPlayer: play() returned: \(success)")
            
            if !success {
                print("❌ AudioPlayer: play() failed - check audio session and player state")
                // Try to reactivate audio session and retry
                do {
                    try audioSession.setActive(false)
                    try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                    try audioSession.setActive(true)
                    let retrySuccess = audioPlayer.play()
                    print("🔊 AudioPlayer: Retry play() returned: \(retrySuccess)")
                    if !retrySuccess {
                        throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start playback after retry"])
                    }
                } catch {
                    throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start playback: \(error.localizedDescription)"])
                }
            }
            
            // Verify playback actually started
            // Give it a moment to start (sometimes there's a small delay)
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            
            if !audioPlayer.isPlaying {
                print("❌ AudioPlayer: Player is not playing after play() call")
                print("   Player state: duration=\(audioPlayer.duration)s, volume=\(audioPlayer.volume)")
                print("   Audio session active: \(audioSession.isOtherAudioPlaying ? "other playing" : "available")")
                throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player failed to start playback"])
            }
            
            isPlaying = true
            isPaused = false
            
            print("✅ AudioPlayer: Playback started successfully")
            print("   isPlaying: \(audioPlayer.isPlaying)")
            print("   duration: \(audioPlayer.duration)s")
            print("   volume: \(audioPlayer.volume)")
            print("   format: \(audioPlayer.format.description)")
            print("   audio session route: \(audioSession.currentRoute.description)")
            
            // Setup Now Playing info for Control Center
            setupNowPlaying(title: title, duration: audioPlayer.duration)
            
            // Schedule fade out before end of playback for smooth ending
            scheduleFadeOut()
            
            print("🔊 Playing TTS audio (volume: \(audioPlayer.volume), duration: \(audioPlayer.duration)s, format: \(audioPlayer.format.description))")
        } catch {
            print("❌ AudioPlayer: Error creating or playing audio: \(error)")
            // Clean up temp file if it exists
            if let tempFile = tempAudioFile {
                try? FileManager.default.removeItem(at: tempFile)
                tempAudioFile = nil
            }
            throw error
        }
    }
    
    private func scheduleFadeOut() {
        guard let player = player, isPlaying else { return }
        
        let duration = player.duration
        let fadeOutStartTime = duration - fadeOutDuration
        
        // Only schedule fade out if there's enough time (more than fade out duration)
        guard fadeOutStartTime > 0 else { return }
        
        fadeOutTimer = Timer.scheduledTimer(withTimeInterval: fadeOutStartTime, repeats: false) { [weak self] _ in
            self?.performFadeOut()
        }
    }
    
    private func performFadeOut() {
        guard let player = player, isPlaying else { return }
        
        let startVolume = Double(player.volume) // Convert Float to Double
        let steps = 20 // Number of volume reduction steps
        let stepDuration = fadeOutDuration / Double(steps)
        let volumeStep = startVolume / Double(steps)
        
        var currentStep = 0
        
        Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self, let player = self.player, self.isPlaying else {
                timer.invalidate()
                return
            }
            
            currentStep += 1
            let newVolume = max(0.0, startVolume - (volumeStep * Double(currentStep)))
            player.volume = Float(newVolume) // Convert Double back to Float
            
            if currentStep >= steps || newVolume <= 0 {
                timer.invalidate()
            }
        }
    }
    
    private func setupNowPlaying(title: String, duration: TimeInterval) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = "EchoShell"
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        self.nowPlayingInfo = nowPlayingInfo
        
        // Setup remote command center for playback controls
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        // Stop command
        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }
        
        print("📱 Now Playing info set: \(title)")
    }
    
    private func updateNowPlayingElapsedTime(_ time: TimeInterval) {
        var info = nowPlayingInfo
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    func pause() {
        // Cancel fade out timer when pausing
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
        
        player?.pause()
        isPlaying = false
        isPaused = true
        
        // Update Now Playing info
        var info = nowPlayingInfo
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime ?? 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        
        print("⏸️ TTS audio paused")
    }
    
    func resume() {
        guard let player = player, isPaused else { return }
        let success = player.play()
        if success {
            isPlaying = true
            isPaused = false
            
            // Restore volume and reschedule fade out
            player.volume = 1.0
            scheduleFadeOut()
            
            // Update Now Playing info
            var info = nowPlayingInfo
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
            info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            
            print("▶️ TTS audio resumed")
        }
    }
    
    func stop() {
        // Cancel fade out timer
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
        
        // Reset volume before stopping to prevent clicks
        player?.volume = 0.0
        
        // Small delay before stopping to allow volume to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            self.player?.stop()
            self.isPlaying = false
            self.isPaused = false
            
            // Clean up temporary file if it exists
            if let tempFile = self.tempAudioFile {
                try? FileManager.default.removeItem(at: tempFile)
                self.tempAudioFile = nil
                print("🗑️ AudioPlayer: Cleaned up temporary audio file")
            }
            
            // Clear Now Playing info
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            self.nowPlayingInfo = [:]
            
            print("🛑 TTS audio stopped, Now Playing cleared")
        }
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Cancel fade out timer if still running
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
        
        isPlaying = false
        isPaused = false
        
        // Clean up temporary file if it exists
        if let tempFile = tempAudioFile {
            try? FileManager.default.removeItem(at: tempFile)
            tempAudioFile = nil
            print("🗑️ AudioPlayer: Cleaned up temporary audio file after playback")
        }
        
        // Clear Now Playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        nowPlayingInfo = [:]
        
        print("🔊 TTS audio playback finished")
        
        // Notify that playback finished
        Task { @MainActor in
            EventBus.shared.ttsPlaybackFinishedPublisher.send()
        }
        
        // Deactivate audio session with delay to prevent audio click/pop
        // Small delay allows audio hardware to settle before deactivation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                // Use .notifyOthersOnDeactivation to allow other apps to use audio
                // But don't force deactivation immediately - let it happen gracefully
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                print("🔊 Audio session deactivated gracefully, ready for recording")
            } catch {
                print("⚠️ Failed to deactivate audio session: \(error)")
            }
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaying = false
        print("❌ Audio playback decode error: \(error?.localizedDescription ?? "Unknown")")
        
        // Deactivate audio session on error
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error)")
        }
    }
}
