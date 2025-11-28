//
//  AudioPlaybackState.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Shared audio playback state for chat views
//

import Foundation

enum AudioPlaybackStatus: Equatable {
    case stopped
    case playing
    case paused
}

struct AudioPlaybackState: Equatable {
    var messageId: String?
    var status: AudioPlaybackStatus
    
    static var idle: AudioPlaybackState {
        AudioPlaybackState(messageId: nil, status: .stopped)
    }
    
    func isPlaying(_ id: String) -> Bool {
        messageId == id && status == .playing
    }
    
    func isPaused(_ id: String) -> Bool {
        messageId == id && status == .paused
    }
}

