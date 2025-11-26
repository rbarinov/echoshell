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
    case terminalDetail(sessionId: String, sessionName: String?, workingDir: String)
    case settings
    
    static func == (lhs: NavigationState, rhs: NavigationState) -> Bool {
        switch (lhs, rhs) {
        case (.agent, .agent), (.terminalsList, .terminalsList), (.settings, .settings):
            return true
        case (.terminalDetail(let id1, let name1, let dir1), .terminalDetail(let id2, let name2, let dir2)):
            return id1 == id2 && name1 == name2 && dir1 == dir2
        default:
            return false
        }
    }
}

struct UnifiedHeaderView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Binding var navigationState: NavigationState
    let connectionState: ConnectionState
    
    var body: some View {
        VStack(spacing: 0) {
            // Main header bar
            HStack(spacing: 12) {
                // Left button (back or create terminal) - only for terminals
                leftButtonView
                
                Spacer()
                
                // Right: Connection status
                ConnectionStatusIndicator(state: connectionState)
                    .frame(width: 44, height: 44, alignment: .center)
            }
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            
            // Nested navigation: Session info for terminal detail
            if case .terminalDetail(_, let sessionName, let workingDir) = navigationState {
                VStack(spacing: 2) {
                    Text(sessionName ?? "Terminal")
                        .font(.system(size: 15, weight: .semibold))
                    Text(workingDir)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
        }
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
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateBack"),
                object: nil
            )
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
                NotificationCenter.default.post(
                    name: NSNotification.Name("CreateTerminal"),
                    object: nil,
                    userInfo: ["terminalType": TerminalType.regular]
                )
            } label: {
                HStack(spacing: 8) {
                    terminalTypeIcon(for: .regular)
                        .frame(width: 20, height: 20)
                    Text("Regular Terminal")
                }
            }
            
            Button {
                NotificationCenter.default.post(
                    name: NSNotification.Name("CreateTerminal"),
                    object: nil,
                    userInfo: ["terminalType": TerminalType.cursorCLI]
                )
            } label: {
                HStack(spacing: 8) {
                    terminalTypeIcon(for: .cursorCLI)
                        .frame(width: 20, height: 20)
                    Text("Cursor")
                }
            }
            
            Button {
                NotificationCenter.default.post(
                    name: NSNotification.Name("CreateTerminal"),
                    object: nil,
                    userInfo: ["terminalType": TerminalType.claudeCLI]
                )
            } label: {
                HStack(spacing: 8) {
                    terminalTypeIcon(for: .claudeCLI)
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
        case .cursorCLI, .cursorAgent:
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
        case .claudeCLI:
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

