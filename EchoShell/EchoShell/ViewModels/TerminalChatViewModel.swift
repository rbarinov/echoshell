//
//  TerminalChatViewModel.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  ViewModel wrapper for terminal chat that adds audio playback capabilities
//

import Foundation
import Combine
import AVFoundation

@MainActor
class TerminalChatViewModel: ObservableObject, ChatViewModelProtocol {
    // MARK: - Published State
    
    var chatHistory: [ChatMessage] {
        baseViewModel.chatHistory
    }
    
    @Published var isProcessing: Bool = false {
        didSet {
            objectWillChange.send()
        }
    }
    
    @Published private(set) var audioPlaybackState: AudioPlaybackState = .idle
    
    // MARK: - Dependencies
    
    private let baseViewModel: ChatViewModel
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Audio Playback State
    
    private var currentlyPlayingMessageId: String?
    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerDelegate: AudioPlayerDelegateWrapper?
    
    // MARK: - Callbacks (set by view)
    
    var onSendTextCommand: ((String) async -> Void)?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var isRecordingCallback: (() -> Bool)?
    
    // MARK: - Initialization
    
    init(baseViewModel: ChatViewModel) {
        self.baseViewModel = baseViewModel
        
        // Forward chat history changes from base view model
        baseViewModel.$chatHistory
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - ChatViewModelProtocol
    
    func playAudioMessage(_ message: ChatMessage) {
        // If the same audio is paused, resume it
        if audioPlayer?.isPlaying == false && currentlyPlayingMessageId == message.id {
            audioPlayer?.play()
            objectWillChange.send()
            audioPlaybackState = AudioPlaybackState(messageId: message.id, status: .playing)
            return
        }
        
        guard let audioPath = message.metadata?.audioFilePath else {
            print("❌ TerminalChatViewModel: Cannot play audio - no file path")
            return
        }
        
        // Load audio file
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDir.appendingPathComponent(audioPath)
        
        guard let audioData = try? Data(contentsOf: fileURL) else {
            print("❌ TerminalChatViewModel: Cannot load audio file: \(audioPath)")
            return
        }
        
        // Stop any current playback
        stopAudio()
        
        // Create and play audio
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            let delegate = AudioPlayerDelegateWrapper {
                Task { @MainActor in
                    self.objectWillChange.send()
                    self.currentlyPlayingMessageId = nil
                    self.audioPlayer = nil
                    self.audioPlayerDelegate = nil
                    self.audioPlaybackState = .idle
                }
            }
            audioPlayerDelegate = delegate
            
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = delegate
            player.play()
            audioPlayer = player
            objectWillChange.send()
            currentlyPlayingMessageId = message.id
            audioPlaybackState = AudioPlaybackState(messageId: message.id, status: .playing)
            
            print("▶️ TerminalChatViewModel: Started playing audio for message \(message.id)")
        } catch {
            print("❌ TerminalChatViewModel: Error playing audio: \(error)")
            currentlyPlayingMessageId = nil
        }
    }
    
    func pauseAudio() {
        audioPlayer?.pause()
        objectWillChange.send()
        if let messageId = currentlyPlayingMessageId {
            audioPlaybackState = AudioPlaybackState(messageId: messageId, status: .paused)
        }
        print("⏸️ TerminalChatViewModel: Paused audio")
    }
    
    func stopAudio() {
        audioPlayer?.stop()
        objectWillChange.send()
        currentlyPlayingMessageId = nil
        audioPlayer = nil
        audioPlayerDelegate = nil
        audioPlaybackState = .idle
        print("⏹️ TerminalChatViewModel: Stopped audio")
    }
    
    func isMessagePlaying(_ messageId: String) -> Bool {
        return currentlyPlayingMessageId == messageId && (audioPlayer?.isPlaying ?? false)
    }
    
    func isMessagePaused(_ messageId: String) -> Bool {
        return currentlyPlayingMessageId == messageId && (audioPlayer?.isPlaying == false && audioPlayer != nil)
    }
    
    var isRecording: Bool {
        return isRecordingCallback?() ?? false
    }
    
    func sendTextCommand(_ command: String) async {
        await onSendTextCommand?(command)
    }
    
    func startRecording() {
        onStartRecording?()
    }
    
    func stopRecording() {
        onStopRecording?()
    }
}

// MARK: - Audio Player Delegate Wrapper

private class AudioPlayerDelegateWrapper: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        super.init()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("❌ AVAudioPlayer decode error: \(error?.localizedDescription ?? "unknown")")
        onFinish()
    }
}

