//
//  SessionStateManager.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Global state manager for active terminal session and view mode
//  Single source of truth for terminal view mode state
//

import Foundation
import SwiftUI

/// Terminal view mode enum (shared across the app)
enum TerminalViewMode {
    case pty
    case agent
}

/// Centralized session and view state management
/// Single source of truth for terminal sessions and modes
@MainActor
class SessionStateManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SessionStateManager()
    
    // MARK: - Published State (Single Source of Truth)
    
    /// Active terminal session ID (nil if no active session)
    @Published private(set) var activeSessionId: String?
    
    /// View mode for active session (agent or pty)
    @Published private(set) var activeViewMode: TerminalViewMode = .pty
    
    // MARK: - Per-Session State
    
    /// Store view mode for each session
    private var sessionModes: [String: TerminalViewMode] = [:]
    
    /// Store session names for display
    private var sessionNames: [String: String] = [:]
    
    // MARK: - Persistence Keys
    
    private let activeSessionKey: String
    private let sessionModesKey: String
    private let sessionNamesKey: String
    
    // MARK: - Initialization
    
    private init() {
        activeSessionKey = "session_state_active_session"
        sessionModesKey = "session_state_modes"
        sessionNamesKey = "session_state_names"
        loadFromUserDefaults()
    }
    
    /// Test initializer (for dependency injection in tests)
    /// - Parameter testPrefix: Prefix for UserDefaults keys to isolate test state
    init(testPrefix: String = "test_") {
        activeSessionKey = "\(testPrefix)session_state_active_session"
        sessionModesKey = "\(testPrefix)session_state_modes"
        sessionNamesKey = "\(testPrefix)session_state_names"
        // Don't load from UserDefaults in test mode
    }
    
    // MARK: - Public API
    
    /// Set the active terminal session
    /// - Parameters:
    ///   - sessionId: Session identifier
    ///   - name: Optional session name for display
    ///   - defaultMode: Default view mode if no saved mode exists
    func setActiveSession(_ sessionId: String, name: String = "", defaultMode: TerminalViewMode = .pty) {
        print("📌 SessionStateManager: Setting active session: \(sessionId)")
        
        activeSessionId = sessionId
        if !name.isEmpty {
            sessionNames[sessionId] = name
        }
        
        // Load saved mode or use default
        activeViewMode = sessionModes[sessionId] ?? defaultMode
        
        saveToUserDefaults()
    }
    
    /// Clear active session
    func clearActiveSession() {
        print("📌 SessionStateManager: Clearing active session")
        activeSessionId = nil
        activeViewMode = .pty
        saveToUserDefaults()
    }
    
    /// Force reload state from UserDefaults (useful for testing)
    func reloadFromUserDefaults() {
        print("🔄 SessionStateManager: Reloading state from UserDefaults")
        loadFromUserDefaults()
    }
    
    /// Clear all session state (useful for testing)
    func clearAllState() {
        print("🗑️ SessionStateManager: Clearing all state")
        activeSessionId = nil
        activeViewMode = .pty
        sessionModes.removeAll()
        sessionNames.removeAll()
        saveToUserDefaults()
    }
    
    /// Toggle view mode for active session
    func toggleViewMode() {
        guard let sessionId = activeSessionId else {
            print("⚠️ SessionStateManager: No active session to toggle")
            return
        }
        
        let newMode: TerminalViewMode = (activeViewMode == .agent) ? .pty : .agent
        setViewMode(newMode, for: sessionId)
    }
    
    /// Set view mode for specific session
    /// - Parameters:
    ///   - mode: View mode to set
    ///   - sessionId: Session identifier
    func setViewMode(_ mode: TerminalViewMode, for sessionId: String) {
        print("📌 SessionStateManager: Setting mode \(mode == .agent ? "agent" : "pty") for session \(sessionId)")
        
        sessionModes[sessionId] = mode
        
        // Update active mode if this is the active session
        if sessionId == activeSessionId {
            activeViewMode = mode
        }
        
        saveToUserDefaults()
    }
    
    /// Get view mode for specific session
    /// - Parameter sessionId: Session identifier
    /// - Returns: View mode for the session, or .pty as default
    func getViewMode(for sessionId: String) -> TerminalViewMode {
        return sessionModes[sessionId] ?? .pty
    }
    
    /// Check if terminal supports agent mode
    /// - Parameter terminalType: Terminal type
    /// - Returns: true if agent mode is supported
    func supportsAgentMode(terminalType: TerminalType) -> Bool {
        switch terminalType {
        case .cursor, .claude, .agent:
            return true
        case .regular:
            return false
        }
    }
    
    /// Check if terminal is headless (cursor/claude/agent)
    /// - Parameter terminalType: Terminal type
    /// - Returns: true if terminal is headless
    func isHeadlessTerminal(terminalType: TerminalType) -> Bool {
        switch terminalType {
        case .cursor, .claude, .agent:
            return true
        case .regular:
            return false
        }
    }
    
    /// Activate a session (legacy method for compatibility)
    /// - Parameter sessionId: Session identifier
    func activateSession(_ sessionId: String) {
        setActiveSession(sessionId)
    }
    
    /// Deactivate current session (legacy method for compatibility)
    func deactivateSession() {
        clearActiveSession()
    }
    
    // MARK: - Persistence
    
    private func saveToUserDefaults() {
        UserDefaults.standard.set(activeSessionId, forKey: activeSessionKey)
        
        // Save session modes as dictionary
        let modesData = sessionModes.mapValues { mode in
            mode == .agent ? "agent" : "pty"
        }
        UserDefaults.standard.set(modesData, forKey: sessionModesKey)
        
        // Save session names
        UserDefaults.standard.set(sessionNames, forKey: sessionNamesKey)
        
        print("💾 SessionStateManager: State saved")
    }
    
    private func loadFromUserDefaults() {
        activeSessionId = UserDefaults.standard.string(forKey: activeSessionKey)
        
        // Load session modes
        if let modesData = UserDefaults.standard.dictionary(forKey: sessionModesKey) as? [String: String] {
            sessionModes = modesData.compactMapValues { modeString in
                modeString == "agent" ? .agent : .pty
            }
        }
        
        // Load session names
        if let names = UserDefaults.standard.dictionary(forKey: sessionNamesKey) as? [String: String] {
            sessionNames = names
        }
        
        // Restore active mode if we have active session
        if let sessionId = activeSessionId {
            activeViewMode = sessionModes[sessionId] ?? .pty
        }
        
        print("📂 SessionStateManager: State loaded (session: \(activeSessionId ?? "none"), mode: \(activeViewMode == .agent ? "agent" : "pty"))")
    }
}

