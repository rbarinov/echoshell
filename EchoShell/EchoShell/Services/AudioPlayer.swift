//
//  AudioPlayer.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Handles audio playback for TTS responses
//

import AVFoundation

class AudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var isPaused = false
    
    private var player: AVAudioPlayer?
    
    func play(audioData: Data) throws {
        // Stop any existing playback
        stop()
        
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
        
        print("🔊 Playing TTS audio (volume: \(player?.volume ?? 0), duration: \(player?.duration ?? 0)s)")
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        isPaused = true
        print("⏸️ TTS audio paused")
    }
    
    func resume() {
        guard let player = player, isPaused else { return }
        let success = player.play()
        if success {
            isPlaying = true
            isPaused = false
            print("▶️ TTS audio resumed")
        }
    }
    
    func stop() {
        player?.stop()
        isPlaying = false
        isPaused = false
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        isPaused = false
        print("🔊 TTS audio playback finished")
        
        // Notify that playback finished
        NotificationCenter.default.post(name: NSNotification.Name("TTSPlaybackFinished"), object: nil)
        
        // Deactivate audio session to allow recording to start again
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            print("🔊 Audio session deactivated, ready for recording")
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error)")
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
