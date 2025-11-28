//
//  RecordingHeaderView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Global header component with connection status and optional left button
//

import SwiftUI

enum HeaderLeftButtonType {
    case none
    case createTerminal(menuActions: [TerminalCreationAction])
    case back(action: () -> Void)
}

struct TerminalCreationAction {
    let title: String
    let icon: String
    let terminalType: TerminalType
    let action: () -> Void
}

struct RecordingHeaderView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    
    // Connection state - passed from parent, updates automatically
    let connectionState: ConnectionState
    
    // Left button type
    let leftButtonType: HeaderLeftButtonType
    
    var body: some View {
        HStack(spacing: 12) {
            // Left button (if any)
            switch leftButtonType {
            case .none:
                Spacer()
            case .createTerminal(let menuActions):
                Menu {
                    ForEach(menuActions, id: \.title) { action in
                        Button {
                            action.action()
                        } label: {
                            HStack(spacing: 8) {
                                terminalTypeIcon(for: action.terminalType)
                                    .frame(width: 20, height: 20)
                                Text(action.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                Spacer()
            case .back(let action):
                Button {
                    print("🔙 RecordingHeaderView: Back button pressed")
                    action()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                }
                .onAppear {
                    print("🔙 RecordingHeaderView: Back button appeared in UI")
                }
                Spacer()
            }
            
            // Connection status indicator on the right
            ConnectionStatusIndicator(state: connectionState)
        }
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .fixedSize(horizontal: false, vertical: true)
    }
    
    // Helper to get terminal type icon matching the list style
    @ViewBuilder
    private func terminalTypeIcon(for type: TerminalType) -> some View {
        switch type {
        case .cursor:
            if UIImage(named: "CursorLogo") != nil {
                Image("CursorLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.blue)
                    .frame(width: 20, height: 20)
            }
        case .claude:
            if UIImage(named: "ClaudeLogo") != nil {
                Image("ClaudeLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                    .frame(width: 20, height: 20)
            }
        case .regular:
            if UIImage(named: "TerminalLogo") != nil {
                Image("TerminalLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.green)
                    .frame(width: 20, height: 20)
            }
        case .agent:
            Image(systemName: "waveform.circle.fill")
                .foregroundColor(.orange)
                .frame(width: 20, height: 20)
        }
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

