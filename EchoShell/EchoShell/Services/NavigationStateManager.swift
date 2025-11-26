//
//  NavigationStateManager.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Manages global navigation state for unified header
//

import SwiftUI
import Combine

class NavigationStateManager: ObservableObject {
    @Published var currentState: NavigationState = .agent
    
    func navigateToTerminalDetail(session: TerminalSession) {
        currentState = .terminalDetail(
            sessionId: session.id,
            sessionName: session.name,
            workingDir: session.workingDir,
            terminalType: session.terminalType
        )
    }
    
    func navigateToTerminalsList() {
        currentState = .terminalsList
    }
    
    func navigateToAgent() {
        currentState = .agent
    }
    
    func navigateToSettings() {
        currentState = .settings
    }
}

