//
//  SupervisorView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Supervisor mode view wrapper - main voice command interface
//

import SwiftUI

struct SupervisorView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        RecordingView()
            .environmentObject(settingsManager)
            .onAppear {
                // Set to supervisor mode when this view appears
                settingsManager.commandMode = .supervisor
            }
    }
}

