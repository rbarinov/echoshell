//
//  ConnectionStatusView.swift
//  EchoShell Watch App
//
//  Created for Voice-Controlled Terminal Management System
//  Connection status indicator component with colored dot
//

import SwiftUI

enum ConnectionState: String {
    case connecting = "connecting"
    case connected = "connected"
    case disconnected = "disconnected"
    case reconnecting = "reconnecting"
    case dead = "dead"
}

struct ConnectionStatusView: View {
    let connectionState: ConnectionState
    let showLabel: Bool
    
    init(connectionState: ConnectionState, showLabel: Bool = false) {
        self.connectionState = connectionState
        self.showLabel = showLabel
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6) // Slightly smaller for Watch
            
            if showLabel {
                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var statusColor: Color {
        switch connectionState {
        case .connecting:
            return .blue
        case .connected:
            return .green
        case .reconnecting:
            return .orange
        case .disconnected, .dead:
            return .red
        }
    }
    
    private var statusText: String {
        switch connectionState {
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .disconnected:
            return "Disconnected"
        case .dead:
            return "Connection Lost"
        }
    }
}

