//
//  ChatViewModelProtocol.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Protocol for chat view models to enable generic chat interface
//

import Foundation
import Combine

/// Protocol that chat view models must conform to for use with GenericChatView
@MainActor
protocol ChatViewModelProtocol: ObservableObject {
    /// Full chat history (all messages)
    var chatHistory: [ChatMessage] { get }
    
    /// Whether the chat is currently processing a request
    var isProcessing: Bool { get }
    
    /// Whether audio is currently being recorded
    var isRecording: Bool { get }
    
    /// Play audio from a chat message
    func playAudioMessage(_ message: ChatMessage)
    
    /// Pause current audio playback
    func pauseAudio()
    
    /// Stop current audio playback
    func stopAudio()
    
    /// Check if a specific message is currently playing
    func isMessagePlaying(_ messageId: String) -> Bool
    
    /// Check if a specific message is currently paused
    func isMessagePaused(_ messageId: String) -> Bool
    
    /// Current audio playback state for UI binding
    var audioPlaybackState: AudioPlaybackState { get }
    
    /// Send a text command
    func sendTextCommand(_ command: String) async
    
    /// Start audio recording
    func startRecording()
    
    /// Stop audio recording
    func stopRecording()
}

