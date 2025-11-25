//
//  TerminalView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Main view for listing terminal sessions
//

import SwiftUI
import UIKit

struct TerminalView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var viewModel = TerminalViewModel()
    @StateObject private var laptopHealthChecker = LaptopHealthChecker()
    
    // Get connection state for header
    private var connectionState: ConnectionState {
        if settingsManager.laptopConfig != nil {
            // Use health checker state if available, otherwise check WebSocket
            return laptopHealthChecker.connectionState
        }
        return .disconnected
    }
    
    var body: some View {
        NavigationStack {
            // Terminal sessions list
            if settingsManager.laptopConfig != nil {
                if viewModel.sessions.isEmpty && !viewModel.isLoading {
                    // Empty state
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "terminal")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Terminal Sessions")
                            .font(.headline)
                        
                        Text("Tap the + button to create a new session")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Session list
                    List {
                        ForEach(viewModel.sessions) { session in
                            NavigationLink(value: session) {
                                SessionRow(session: session)
                            }
                        }
                        .onDelete { indexSet in
                            // Handle swipe to delete
                            for index in indexSet {
                                let session = viewModel.sessions[index]
                                if let config = settingsManager.laptopConfig {
                                    Task {
                                        await viewModel.deleteSession(session, config: config)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .padding(.top, 60)
                    .navigationDestination(for: TerminalSession.self) { session in
                        TerminalDetailView(session: session, config: settingsManager.laptopConfig!)
                            .environmentObject(settingsManager)
                    }
                }
            } else {
                // Not connected
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "laptopcomputer.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("Not Connected")
                        .font(.headline)
                    
                    Text("Connect to laptop in Settings to use terminals")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            RecordingHeaderView(
                connectionState: connectionState,
                leftButtonType: settingsManager.laptopConfig != nil 
                    ? .createTerminal(menuActions: [
                        TerminalCreationAction(
                            title: "Regular Terminal",
                            icon: "terminal.fill",
                            terminalType: .regular,
                            action: {
                                if let config = settingsManager.laptopConfig {
                                    Task {
                                        await viewModel.createNewSession(
                                            config: config,
                                            terminalType: .regular
                                        )
                                        await viewModel.refreshSessions(config: config)
                                    }
                                }
                            }
                        ),
                        TerminalCreationAction(
                            title: "Cursor",
                            icon: "brain.head.profile",
                            terminalType: .cursorCLI,
                            action: {
                                if let config = settingsManager.laptopConfig {
                                    Task {
                                        await viewModel.createNewSession(
                                            config: config,
                                            terminalType: .cursorCLI
                                        )
                                        await viewModel.refreshSessions(config: config)
                                    }
                                }
                            }
                        ),
                        TerminalCreationAction(
                            title: "Claude Code",
                            icon: "sparkles",
                            terminalType: .claudeCLI,
                            action: {
                                if let config = settingsManager.laptopConfig {
                                    Task {
                                        await viewModel.createNewSession(
                                            config: config,
                                            terminalType: .claudeCLI
                                        )
                                        await viewModel.refreshSessions(config: config)
                                    }
                                }
                            }
                        )
                    ])
                    : .none
            )
            .background(Color(.systemBackground))
        }
        .task {
            if let config = settingsManager.laptopConfig {
                // Start health checker
                laptopHealthChecker.start(config: config)
                // Load sessions
                await viewModel.loadSessions(config: config)
            }
        }
        .onChange(of: settingsManager.laptopConfig) { oldValue, newValue in
            if let config = newValue {
                laptopHealthChecker.start(config: config)
                Task {
                    await viewModel.loadSessions(config: config)
                }
            } else {
                laptopHealthChecker.stop()
            }
        }
        .onDisappear {
            laptopHealthChecker.stop()
        }
        // Auto-refresh sessions periodically
        .onReceive(Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()) { _ in
            if let config = settingsManager.laptopConfig, !viewModel.isLoading {
                Task {
                    await viewModel.refreshSessions(config: config)
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: TerminalSession
    
    var body: some View {
        HStack(spacing: 12) {
            // Terminal type icon
            terminalTypeIcon
                .font(.system(size: 24))
                .frame(width: 32, height: 32)
            
            // Session info
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name ?? session.id)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(session.workingDir)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    private var terminalTypeIcon: some View {
        Group {
            switch session.terminalType {
            case .cursorCLI, .cursorAgent:
                // Cursor logo - try to load from assets, fallback to system icon
                if UIImage(named: "CursorLogo") != nil {
                    Image("CursorLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.blue)
                }
            case .claudeCLI:
                // Claude logo - try to load from assets, fallback to system icon
                if UIImage(named: "ClaudeLogo") != nil {
                    Image("ClaudeLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                }
            case .regular:
                // Shell icon - using terminal.fill for ZSH/BASH
                Image(systemName: "terminal.fill")
                    .foregroundColor(.green)
            }
        }
    }
}
