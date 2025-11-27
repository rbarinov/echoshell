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

    /// Synthesize TTS and play audio
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - config: Laptop tunnel configuration
    ///   - speed: TTS playback speed (0.7-1.2)
    ///   - language: Language code (ru, en, ka, etc.)
    ///   - cleaningFunction: Optional function to clean text before synthesis
    /// - Returns: Audio data on success
    @discardableResult
    func synthesizeAndPlay(
        text: String,
        config: TunnelConfig,
        speed: Double,
        language: String,
        cleaningFunction: ((String) -> String)? = nil
    ) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate text
        guard !trimmed.isEmpty else {
            print("🔇 synthesizeAndPlay: Empty text, aborting")
            throw TTSError.emptyText
        }

        // Check if we already have audio for this exact text
        if lastGeneratedText == trimmed, let existingAudio = lastAudioData {
            print("🔊 synthesizeAndPlay: Using existing TTS audio for same text")

            // Play existing audio if not already playing
            // Note: We're already on MainActor, but audioPlayer.play might need main thread
            if !audioPlayer.isPlaying {
                do {
                    try audioPlayer.play(audioData: existingAudio, title: "AI Assistant Response")
                    print("🔊 synthesizeAndPlay: Playing existing audio")
                } catch {
                    print("❌ synthesizeAndPlay: Failed to play existing audio: \(error)")
                }
            }

            return existingAudio
        }

        // Set generating state (already on MainActor)
        isGenerating = true

        do {
            // Clean text if cleaning function provided
            let cleanedText = cleaningFunction?(trimmed) ?? trimmed

            // Validate cleaned text
            guard !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("⚠️ synthesizeAndPlay: Cleaned text is empty, skipping TTS")
                isGenerating = false
                throw TTSError.emptyText
            }

            print("🔊 synthesizeAndPlay: Generating TTS (length: \(cleanedText.count)) at \(speed)x speed")

            // Build TTS endpoint from laptop config (proxy endpoint via tunnel)
            let ttsEndpoint = "\(config.apiBaseUrl)/proxy/tts/synthesize"
            let ttsHandler = LocalTTSHandler(laptopAuthKey: config.authKey, endpoint: ttsEndpoint)

            // Synthesize audio (this can run off MainActor)
            let audioData = try await ttsHandler.synthesize(
                text: cleanedText,
                speed: speed,
                language: language
            )

            print("✅ synthesizeAndPlay: TTS synthesis completed, audio data size: \(audioData.count) bytes")

            // Update state with new audio (back on MainActor)
            isGenerating = false
            lastGeneratedText = trimmed
            lastAudioData = audioData

            // Play audio (already on MainActor)
            try audioPlayer.play(audioData: audioData, title: "AI Assistant Response")
            print("🔊 synthesizeAndPlay: TTS playback started at \(speed)x speed")

            return audioData

        } catch {
            print("❌ synthesizeAndPlay: TTS error: \(error)")
            isGenerating = false
            throw error
        }
    }

    /// Replay the last generated audio
    func replay() {
        guard let audioData = lastAudioData else {
            print("⚠️ replay: No audio data available")
            return
        }

        guard !audioPlayer.isPlaying else {
            print("⚠️ replay: Audio already playing")
            return
        }

        do {
            try audioPlayer.play(audioData: audioData, title: "AI Assistant Response")
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

// MARK: - Error Types

extension TTSError {
    static let emptyText = TTSError.requestFailed
}
