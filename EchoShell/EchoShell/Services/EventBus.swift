//
//  EventBus.swift
//  EchoShell
//
//  Centralized event bus using Combine publishers
//  Replaces string-based NotificationCenter with type-safe events
//

import Foundation
import Combine

/// Centralized event bus using Combine publishers
/// Replaces string-based NotificationCenter with type-safe events
@MainActor
class EventBus: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = EventBus()
    private init() {}
    
    // MARK: - Transcription Events
    
    @Published var transcriptionStarted: Bool = false
    
    var transcriptionCompletedPublisher = PassthroughSubject<TranscriptionResult, Never>()
    
    struct TranscriptionResult {
        let text: String
        let language: String?
        let duration: TimeInterval?
    }
    
    var transcriptionStatsUpdatedPublisher = PassthroughSubject<TranscriptionStats, Never>()
    
    struct TranscriptionStats {
        let text: String?
        let duration: TimeInterval?
        let language: String?
        let isFromWatch: Bool
    }
    
    // MARK: - TTS Events
    
    @Published var ttsGenerating: Bool = false
    
    var ttsPlaybackFinishedPublisher = PassthroughSubject<Void, Never>()
    var ttsReadyPublisher = PassthroughSubject<TTSReadyEvent, Never>()
    var ttsFailedPublisher = PassthroughSubject<TTSError, Never>()
    
    struct TTSReadyEvent {
        let audioData: Data
        let text: String
        let operationId: String
        let sessionId: String? // Optional: nil for global agent, sessionId for terminal-specific
    }
    
    enum TTSError: Error {
        case synthesisFailed(message: String)
        case playbackFailed(Error)
    }
    
    // MARK: - Command Events
    
    var commandSentPublisher = PassthroughSubject<CommandEvent, Never>()
    
    struct CommandEvent {
        let command: String
        let sessionId: String?
        let transport: String // "headless" or "interactive"
    }
    
    // MARK: - Navigation Events
    
    var navigateBackPublisher = PassthroughSubject<Void, Never>()
    var createTerminalPublisher = PassthroughSubject<TerminalType, Never>()
    
    // MARK: - Terminal View Mode Events
    
    var toggleTerminalViewModePublisher = PassthroughSubject<TerminalViewMode, Never>()
    var terminalViewModeChangedPublisher = PassthroughSubject<TerminalViewMode, Never>()
    
    enum TerminalViewMode: String {
        case pty
        case agent
    }
    
    // MARK: - Settings Events
    
    var apiKeyChangedPublisher = PassthroughSubject<Void, Never>()
    var languageChangedPublisher = PassthroughSubject<Void, Never>()
}
