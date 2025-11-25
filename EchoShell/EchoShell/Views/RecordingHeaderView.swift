//
//  RecordingHeaderView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Common header component with mode toggle and connection status
//

import SwiftUI

struct RecordingHeaderView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    
    // Connection state - passed from parent, updates automatically
    let connectionState: ConnectionState
    
    var body: some View {
        HStack(spacing: 12) {
            // Left spacer to push indicator to the right
            Spacer()
            
            // Connection status indicator on the right
            ConnectionStatusIndicator(state: connectionState)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// Connection Status Indicator Component
struct ConnectionStatusIndicator: View {
    let state: ConnectionState
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0
    
    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(statusColor)
            .scaleEffect(pulseScale)
            .opacity(pulseOpacity)
            .shadow(
                color: statusColor.opacity(0.3),
                radius: pulseScale > 1.0 ? 8 : 4,
                x: 0,
                y: 2
            )
            .onAppear {
                startPulsing()
            }
            .onChange(of: state) { oldValue, newValue in
                startPulsing()
            }
    }
    
    private var iconName: String {
        // Use laptopcomputer icon for workstation/server
        return "laptopcomputer"
    }
    
    private func startPulsing() {
        // Determine pulse duration based on state
        // Connected: slow pulse (3x slower), others: normal pulse
        let duration: Double = (state == .connected) ? 1.8 : 0.6 // 0.6 * 3 = 1.8
        
        // Reset animation
        withAnimation(.linear(duration: 0)) {
            pulseScale = 1.0
            pulseOpacity = 1.0
        }
        
        // Start pulsing animation
        withAnimation(
            .easeInOut(duration: duration)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.15
            pulseOpacity = 0.6
        }
    }
    
    private var statusColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected, .dead:
            return .red
        }
    }
}

