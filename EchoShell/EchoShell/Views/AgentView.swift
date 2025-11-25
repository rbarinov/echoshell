//
//  AgentView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Agent mode view wrapper
//

import SwiftUI

struct AgentView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        RecordingView()
            .environmentObject(settingsManager)
            .onAppear {
                // Set to agent mode when this view appears
                settingsManager.commandMode = .agent
            }
    }
}

