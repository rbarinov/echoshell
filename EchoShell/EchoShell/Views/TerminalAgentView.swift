//
//  TerminalAgentView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Terminal Agent (Direct) mode view wrapper
//

import SwiftUI

struct TerminalAgentView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        RecordingView()
            .environmentObject(settingsManager)
            .onAppear {
                // Set to direct mode when this view appears
                settingsManager.commandMode = .direct
            }
    }
}

