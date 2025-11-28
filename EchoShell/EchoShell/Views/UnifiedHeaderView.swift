//
//  UnifiedHeaderView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Unified static header with nested navigation for all pages
//

import SwiftUI

// Navigation state for unified header
enum NavigationState: Equatable {
    case agent
    case terminalsList
    case terminalDetail(sessionId: String, sessionName: String?, workingDir: String, terminalType: TerminalType)
    case settings
    
    static func == (lhs: NavigationState, rhs: NavigationState) -> Bool {
        switch (lhs, rhs) {
        case (.agent, .agent), (.terminalsList, .terminalsList), (.settings, .settings):
            return true
        case (.terminalDetail(let id1, let name1, let dir1, let type1), .terminalDetail(let id2, let name2, let dir2, let type2)):
            return id1 == id2 && name1 == name2 && dir1 == dir2 && type1 == type2
        default:
            return false
        }
    }
}

struct UnifiedHeaderView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var sessionState: SessionStateManager
    @Binding var navigationState: NavigationState
    let connectionState: ConnectionState
    
    var body: some View {
        // Main header bar
        HStack(spacing: 12) {
            // Left button (back or create terminal) - only for terminals
            leftButtonView
            
            // Center: Session info for terminal detail (icon + name + path)
            if case .terminalDetail(_, let sessionName, let workingDir, let terminalType) = navigationState {
                HStack(spacing: 8) {
                    // Terminal type icon
                    terminalTypeIcon(for: terminalType)
                    
                    // Session name and working directory
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionName ?? "Terminal")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(workingDir)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Right: Connection status
            ConnectionStatusIndicator(state: connectionState)
                .frame(width: 44, height: 44, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private var leftButtonView: some View {
        switch navigationState {
        case .agent, .settings:
            // No buttons for agent or settings - only status indicator
            // Use fixed frame to maintain consistent spacing
            Color.clear
                .frame(width: 44, height: 44)
        case .terminalsList:
            if settingsManager.laptopConfig != nil {
                createTerminalMenu
            } else {
                // Use fixed frame to maintain consistent spacing
                Color.clear
                    .frame(width: 44, height: 44)
            }
        case .terminalDetail:
            backButton
        }
    }
    
    private var backButton: some View {
        Button {
            Task { @MainActor in
                EventBus.shared.navigateBackPublisher.send()
            }
            navigationState = .terminalsList
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 44, height: 44, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var createTerminalMenu: some View {
        Menu {
            Button {
                Task { @MainActor in
                    EventBus.shared.createTerminalPublisher.send(.regular)
                }
            } label: {
                HStack(spacing: 8) {
                    terminalTypeIcon(for: .regular)
                        .frame(width: 20, height: 20)
                    Text("Regular Terminal")
                }
            }
            
            Button {
                Task { @MainActor in
                    EventBus.shared.createTerminalPublisher.send(.cursor)
                }
            } label: {
                HStack(spacing: 8) {
                    terminalTypeIcon(for: .cursor)
                        .frame(width: 20, height: 20)
                    Text("Cursor")
                }
            }
            
            Button {
                Task { @MainActor in
                    EventBus.shared.createTerminalPublisher.send(.claude)
                }
            } label: {
                HStack(spacing: 8) {
                    terminalTypeIcon(for: .claude)
                        .frame(width: 20, height: 20)
                    Text("Claude Code")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 44, height: 44, alignment: .center)
                .contentShape(Rectangle())
        }
    }
    
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
        }
    }
}

