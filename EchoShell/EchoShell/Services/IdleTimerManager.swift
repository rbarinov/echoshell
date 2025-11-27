//
//  IdleTimerManager.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Manages device idle timer to prevent screen sleep during active operations
//

import UIKit

/// Manages device idle timer to prevent screen sleep during active operations
/// Follows Apple's best practices for managing screen sleep during user interactions
@MainActor
class IdleTimerManager {
    
    // MARK: - Singleton
    
    static let shared = IdleTimerManager()
    private init() {}
    
    // MARK: - State
    
    private var activeOperations: Set<String> = []
    private var isIdleTimerDisabled = false
    
    // MARK: - Public API
    
    /// Begin an operation that requires screen to stay on
    /// - Parameter identifier: Unique identifier for the operation (e.g., "recording", "tts_playback")
    func beginOperation(_ identifier: String) {
        print("⏰ IdleTimerManager: Begin operation '\(identifier)'")
        
        activeOperations.insert(identifier)
        updateIdleTimer()
    }
    
    /// End an operation
    /// - Parameter identifier: Unique identifier for the operation
    func endOperation(_ identifier: String) {
        print("⏰ IdleTimerManager: End operation '\(identifier)'")
        
        activeOperations.remove(identifier)
        updateIdleTimer()
    }
    
    /// End all operations (for cleanup)
    func endAllOperations() {
        print("⏰ IdleTimerManager: Ending all operations")
        
        activeOperations.removeAll()
        updateIdleTimer()
    }
    
    // MARK: - Private Methods
    
    private func updateIdleTimer() {
        let shouldDisable = !activeOperations.isEmpty
        
        if shouldDisable != isIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = shouldDisable
            isIdleTimerDisabled = shouldDisable
            
            print("⏰ IdleTimerManager: Idle timer \(shouldDisable ? "DISABLED" : "ENABLED") (operations: \(activeOperations.count))")
        }
    }
}

