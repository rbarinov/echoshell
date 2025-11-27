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
    
    func play(audioData: Data, title: String = "AI Assistant Response") throws {
        // Stop any existing playback
        stop()
        
        // Cancel any existing fade out
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        // Use .playAndRecord category to allow both recording and playback
        // with .defaultToSpeaker option to play through speaker
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setActive(true)
        
        player = try AVAudioPlayer(data: audioData)
        player?.delegate = self
        player?.volume = 1.0
        player?.prepareToPlay()
        
        let success = player?.play() ?? false
        if !success {
            throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start playback"])
        }
        
        isPlaying = true
        isPaused = false
        
        // Setup Now Playing info for Control Center
        setupNowPlaying(title: title, duration: player?.duration ?? 0)
        
        // Schedule fade out before end of playback for smooth ending
        scheduleFadeOut()
        
        print("🔊 Playing TTS audio (volume: \(player?.volume ?? 0), duration: \(player?.duration ?? 0)s)")
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
            self?.player?.stop()
            self?.isPlaying = false
            self?.isPaused = false
            
            // Clear Now Playing info
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            self?.nowPlayingInfo = [:]
            
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
