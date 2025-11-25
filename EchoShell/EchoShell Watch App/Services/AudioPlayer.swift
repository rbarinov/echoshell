//
//  AudioPlayer.swift
//  EchoShell Watch App
//
//  Created for Voice-Controlled Terminal Management System
//  Handles audio playback for TTS responses
//

import AVFoundation

class AudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    
    private var player: AVAudioPlayer?
    
    func play(audioData: Data) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default)
        try audioSession.setActive(true)
        
        player = try AVAudioPlayer(data: audioData)
        player?.delegate = self
        player?.prepareToPlay()
        player?.play()
        
        isPlaying = true
        
        print("🔊 Playing TTS audio...")
    }
    
    func stop() {
        player?.stop()
        isPlaying = false
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
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

