//
//  TTSService.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Unified TTS generation and playback service
//  Eliminates code duplication between RecordingView and TerminalDetailView
//

import Foundation
import AVFoundation
import Combine

/// Unified service for TTS synthesis and playback
/// Handles duplicate prevention, audio generation, and playback coordination
/// Thread-safe: All state updates happen on MainActor
@MainActor
class TTSService: ObservableObject {

    // MARK: - Published State

    @Published var isGenerating: Bool = false
    @Published var lastGeneratedText: String = ""
    @Published var lastAudioData: Data?

    // MARK: - Dependencies

    let audioPlayer: AudioPlayer // Public for external access

    // MARK: - Initialization

    init(audioPlayer: AudioPlayer) {
        self.audioPlayer = audioPlayer
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Cleanup: Stop any ongoing playback
        audioPlayer.stop()
        print("🧹 TTSService: Deinitialized")
    }

    // MARK: - Public Methods

    /// Check if TTS should be generated for new text
    /// - Parameters:
    ///   - newText: New text to synthesize
    ///   - lastText: Previously synthesized text
    ///   - isPlaying: Whether audio is currently playing
    /// - Returns: True if TTS should be generated
    func shouldGenerateTTS(
        newText: String,
        lastText: String,
        isPlaying: Bool
    ) -> Bool {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty text check
        if trimmed.isEmpty {
            print("🔇 shouldGenerateTTS: Empty text, skipping")
            return false
        }

        // Already generating check
        if isGenerating {
            print("⚠️ shouldGenerateTTS: Already generating, skipping duplicate")
            return false
        }

        // Already playing check
        if isPlaying {
            print("⚠️ shouldGenerateTTS: Audio already playing, skipping duplicate")
            return false
        }

        // Duplicate text check
        if trimmed == lastText {
            print("⚠️ shouldGenerateTTS: Same text as last, skipping duplicate")
            return false
        }

        return true
    }

    /// Play TTS audio (server-side synthesis only)
    /// TTS audio is now synthesized on the server and received via WebSocket
    /// This method is kept for backward compatibility but should not be used for new code
    /// - Parameters:
    ///   - text: Text that was synthesized (for logging)
    ///   - config: Laptop tunnel configuration (unused, kept for compatibility)
    ///   - speed: TTS playback speed (unused, kept for compatibility)
    ///   - language: Language code (unused, kept for compatibility)
    ///   - cleaningFunction: Optional function (unused, kept for compatibility)
    /// - Returns: Audio data if available
    @discardableResult
    func synthesizeAndPlay(
        text: String,
        config: TunnelConfig,
        speed: Double,
        language: String,
        cleaningFunction: ((String) -> String)? = nil
    ) async throws -> Data {
        // TTS is now server-side only - audio comes via WebSocket tts_audio events
        // This method is kept for backward compatibility but should not synthesize
        print("⚠️ TTSService: synthesizeAndPlay called - TTS is now server-side only")
        
        // Check if we already have audio for this text
        if lastGeneratedText == text.trimmingCharacters(in: .whitespacesAndNewlines), let existingAudio = lastAudioData {
            if !audioPlayer.isPlaying {
                try await audioPlayer.play(audioData: existingAudio, title: "AI Assistant Response")
            }
            return existingAudio
        }
        
        // No audio available - throw error
        throw EventBus.TTSError.synthesisFailed(message: "TTS is server-side only, no cached audio available")
    }

    /// Replay the last generated audio
    func replay() async {
        guard let audioData = lastAudioData else {
            print("⚠️ replay: No audio data available")
            return
        }

        guard !audioPlayer.isPlaying else {
            print("⚠️ replay: Audio already playing")
            return
        }

        do {
            try await audioPlayer.play(audioData: audioData, title: "AI Assistant Response")
            print("🔊 replay: Playing last TTS audio")
        } catch {
            print("❌ replay: Failed to play audio: \(error)")
        }
    }

    /// Stop current playback
    func stop() {
        audioPlayer.stop()
        print("🛑 TTSService: Playback stopped")
    }

    /// Reset service state (clears last text and audio)
    func reset() {
        lastGeneratedText = ""
        lastAudioData = nil
        audioPlayer.stop()
        print("🔄 TTSService: State reset")
    }
}

