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
    
    // Connection state - can be passed from parent or computed
    // Using @State to ensure view updates when state changes
    @State private var connectionState: ConnectionState?
    
    init(connectionState: ConnectionState? = nil) {
        _connectionState = State(initialValue: connectionState)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Left spacer to push indicator to the right
            Spacer()
            
            // Connection status indicator on the right
            ConnectionStatusIndicator(state: effectiveConnectionState)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onChange(of: settingsManager.laptopConfig) { _, _ in
            // Update connection state when laptop config changes
            updateConnectionState()
        }
    }
    
    // Compute effective connection state
    private var effectiveConnectionState: ConnectionState {
        // If connection state is provided, use it
        if let state = connectionState {
            return state
        }
        
        // Otherwise, determine based on laptop config
        if settingsManager.laptopConfig == nil {
            return .disconnected
        }
        
        // If we have laptop config, we're at least connected to backend
        // For more detailed state, parent should pass connectionState
        return .connected
    }
    
    // Update connection state (can be called from parent)
    func updateConnectionState(_ newState: ConnectionState?) {
        connectionState = newState
    }
    
    private func updateConnectionState() {
        // Internal method to update state based on laptop config
        if settingsManager.laptopConfig == nil {
            connectionState = .disconnected
        } else if connectionState == nil {
            connectionState = .connected
        }
    }
}

// Connection Status Indicator Component
struct ConnectionStatusIndicator: View {
    let state: ConnectionState
    @State private var isPulsing = false
    
    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(statusColor)
            .symbolEffect(.pulse, isActive: isPulsing)
            .shadow(
                color: statusColor.opacity(0.3),
                radius: isPulsing ? 8 : 4,
                x: 0,
                y: 2
            )
            .onAppear {
                updatePulsing()
            }
            .onChange(of: state) { oldValue, newValue in
                updatePulsing()
            }
    }
    
    private var iconName: String {
        // Use laptopcomputer icon for workstation/server
        return "laptopcomputer"
    }
    
    private func updatePulsing() {
        // Start pulsing for connecting/reconnecting states
        if state == .connecting || state == .reconnecting {
            isPulsing = true
        } else {
            isPulsing = false
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

