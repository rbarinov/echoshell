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
    @EnvironmentObject var navigationStateManager: NavigationStateManager
    @StateObject private var viewModel = TerminalViewModel()
    @StateObject private var laptopHealthChecker = LaptopHealthChecker()
    
    // Track navigation path to detect if we're on detail page
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                    .navigationDestination(for: TerminalSession.self) { session in
                        TerminalDetailView(session: session, config: settingsManager.laptopConfig!)
                            .environmentObject(settingsManager)
                            .environmentObject(navigationStateManager)
                            .onAppear {
                                navigationStateManager.navigateToTerminalDetail(session: session)
                            }
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
        .onChange(of: navigationPath) { oldValue, newValue in
            // Update navigation state when path changes
            if newValue.isEmpty {
                navigationStateManager.navigateToTerminalsList()
            }
        }
        .onReceive(EventBus.shared.createTerminalPublisher) { terminalType in
            guard let config = settingsManager.laptopConfig else { return }
            
            Task {
                await viewModel.createNewSession(
                    config: config,
                    terminalType: terminalType
                )
                await viewModel.refreshSessions(config: config)
            }
        }
        .onReceive(EventBus.shared.navigateBackPublisher) { _ in
            if !navigationPath.isEmpty {
                navigationPath.removeLast()
            }
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
            case .cursor:
                // Cursor logo - unified style
                if UIImage(named: "CursorLogo") != nil {
                    Image("CursorLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                }
            case .claude:
                // Claude logo - unified style
                if UIImage(named: "ClaudeLogo") != nil {
                    Image("ClaudeLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                        .frame(width: 32, height: 32)
                }
            case .regular:
                // Classic terminal logo - unified style
                if UIImage(named: "TerminalLogo") != nil {
                    Image("TerminalLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "terminal.fill")
                        .foregroundColor(.green)
                        .frame(width: 32, height: 32)
                }
            }
        }
    }
}
