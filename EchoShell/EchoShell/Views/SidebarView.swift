//
//  SidebarView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Sidebar menu for navigation (Supervisor, Terminals, Settings)
//

import SwiftUI
import UIKit

struct SidebarView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var navigationStateManager: NavigationStateManager
    @ObservedObject var terminalViewModel: TerminalViewModel
    @Binding var isPresented: Bool
    
    let onSelectSupervisor: () -> Void
    let onSelectTerminal: (TerminalSession) -> Void
    let onSelectSettings: () -> Void
    let onCreateTerminal: (TerminalType) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                // Home section
                Section {
                    Button(action: {
                        onSelectSupervisor()
                        isPresented = false
                    }) {
                        HStack(spacing: 12) {
                            supervisorIconView()
                            Text("Supervisor")
                                .foregroundColor(.primary)
                        }
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    Text("Home")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }
                
                // Terminals section
                Section {
                    // Show ALL terminals (not just headless)
                    let allSessions = terminalViewModel.sessions
                    
                    if allSessions.isEmpty {
                        // Show create menu when no terminals
                        Menu {
                            Button(action: {
                                onCreateTerminal(.regular)
                                isPresented = false
                            }) {
                                HStack(spacing: 8) {
                                    terminalTypeIconView(for: .regular)
                                    Text("Regular Terminal")
                                }
                            }
                            
                            Button(action: {
                                onCreateTerminal(.cursor)
                                isPresented = false
                            }) {
                                HStack(spacing: 8) {
                                    terminalTypeIconView(for: .cursor)
                                    Text("Cursor")
                                }
                            }
                            
                            Button(action: {
                                onCreateTerminal(.claude)
                                isPresented = false
                            }) {
                                HStack(spacing: 8) {
                                    terminalTypeIconView(for: .claude)
                                    Text("Claude Code")
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 20, height: 20)
                                Text("Create Terminal")
                                    .foregroundColor(.primary)
                            }
                        }
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(allSessions) { session in
                            Button(action: {
                                onSelectTerminal(session)
                                isPresented = false
                            }) {
                                HStack(spacing: 12) {
                                    terminalTypeIconView(for: session.terminalType)
                                    Text(session.name ?? session.id)
                                        .foregroundColor(.primary)
                                }
                            }
                            .listRowSeparator(.hidden)
                        }
                        
                        // Add button at the end
                        Menu {
                            Button(action: {
                                onCreateTerminal(.regular)
                                isPresented = false
                            }) {
                                HStack(spacing: 8) {
                                    terminalTypeIconView(for: .regular)
                                    Text("Regular Terminal")
                                }
                            }
                            
                            Button(action: {
                                onCreateTerminal(.cursor)
                                isPresented = false
                            }) {
                                HStack(spacing: 8) {
                                    terminalTypeIconView(for: .cursor)
                                    Text("Cursor")
                                }
                            }
                            
                            Button(action: {
                                onCreateTerminal(.claude)
                                isPresented = false
                            }) {
                                HStack(spacing: 8) {
                                    terminalTypeIconView(for: .claude)
                                    Text("Claude Code")
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                    .frame(width: 20, height: 20)
                                Text("Create Terminal")
                                    .foregroundColor(.blue)
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Terminals")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }
                
                // Settings section
                Section {
                    Button(action: {
                        onSelectSettings()
                        isPresented = false
                    }) {
                        HStack(spacing: 12) {
                            settingsIconView()
                            Text("Settings")
                                .foregroundColor(.primary)
                        }
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    Text("Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
        }
    }
    
    @ViewBuilder
    private func supervisorIconView() -> some View {
        // Supervisor icon matching terminal style
        Image(systemName: "person.wave.2.fill")
            .foregroundColor(.blue)
            .frame(width: 20, height: 20)
    }
    
    @ViewBuilder
    private func settingsIconView() -> some View {
        // Settings icon matching terminal style
        Image(systemName: "gearshape.fill")
            .foregroundColor(.gray)
            .frame(width: 20, height: 20)
    }
    
    @ViewBuilder
    private func terminalTypeIconView(for type: TerminalType) -> some View {
        // Use same icons as UnifiedHeaderView
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

#Preview {
    SidebarView(
        terminalViewModel: TerminalViewModel(),
        isPresented: .constant(true),
        onSelectSupervisor: {},
        onSelectTerminal: { _ in },
        onSelectSettings: {},
        onCreateTerminal: { _ in }
    )
    .environmentObject(SettingsManager())
}

