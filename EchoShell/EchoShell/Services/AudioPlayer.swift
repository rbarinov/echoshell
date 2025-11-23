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
    }
}
