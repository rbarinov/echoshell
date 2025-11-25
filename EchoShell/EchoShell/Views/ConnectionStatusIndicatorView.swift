//
//  ConnectionStatusIndicatorView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Connection status indicator that gets state from shared clients
//

import SwiftUI

struct ConnectionStatusIndicatorView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var wsClient = WebSocketClient()
    @State private var connectionState: ConnectionState = .disconnected
    
    var body: some View {
        ConnectionStatusView(connectionState: connectionState)
            .onAppear {
                updateConnectionState()
            }
            .onChange(of: wsClient.connectionState) { _, _ in
                updateConnectionState()
            }
            .onChange(of: settingsManager.selectedSessionId) { _, _ in
                updateConnectionState()
            }
    }
    
    private func updateConnectionState() {
        // For TerminalView, we primarily care about WebSocket connection
        // In a real implementation, you might want to track this differently
        connectionState = wsClient.connectionState
    }
}

