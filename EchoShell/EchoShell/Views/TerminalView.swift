//
//  TerminalView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Main view for listing terminal sessions
//

import SwiftUI

struct TerminalView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var viewModel = TerminalViewModel()
    @State private var selectedSession: TerminalSession?
    @State private var showingNewSession = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if settingsManager.laptopConfig != nil {
                    if viewModel.sessions.isEmpty && !viewModel.isLoading {
                        // Empty state
                        VStack(spacing: 20) {
                            Image(systemName: "terminal")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            
                            Text("No Terminal Sessions")
                                .font(.headline)
                            
                            Text("Create a new session to get started")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Button {
                                showingNewSession = true
                            } label: {
                                Label("Create Session", systemImage: "plus.circle.fill")
                                    .font(.headline)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        // Session list
                        List {
                            ForEach(viewModel.sessions) { session in
                                Button {
                                    selectedSession = session
                                } label: {
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
                    }
                } else {
                    // Not connected
                    VStack(spacing: 20) {
                        Image(systemName: "laptopcomputer.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("Not Connected")
                            .font(.headline)
                        
                        Text("Connect to laptop in Settings to use terminal")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .navigationTitle("Terminal Sessions")
            .toolbar {
                if settingsManager.laptopConfig != nil && !viewModel.sessions.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingNewSession = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if let config = settingsManager.laptopConfig {
                            Task {
                                await viewModel.refreshSessions(config: config)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(settingsManager.laptopConfig == nil)
                }
                
                // Connection status indicator in toolbar
                if settingsManager.laptopConfig != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ConnectionStatusIndicatorView()
                            .environmentObject(settingsManager)
                    }
                }
            }
            .sheet(isPresented: $showingNewSession) {
                NewSessionView { terminalType, workingDir, name in
                    if let config = settingsManager.laptopConfig {
                        Task {
                            await viewModel.createNewSession(
                                config: config,
                                terminalType: terminalType,
                                workingDir: workingDir,
                                name: name
                            )
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedSession) { session in
                TerminalDetailView(session: session, config: settingsManager.laptopConfig!)
            }
            .task {
                if let config = settingsManager.laptopConfig {
                    await viewModel.loadSessions(config: config)
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: TerminalSession
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.name ?? session.id)
                        .font(.headline)
                    if session.terminalType == .cursorAgent {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                Text(session.workingDir)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if session.isActive {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.green)
                }
                
                Text(session.lastUpdate, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct NewSessionView: View {
    @Environment(\.dismiss) var dismiss
    @State private var workingDir: String = ""
    @State private var terminalType: TerminalType = .regular
    @State private var name: String = ""
    
    let onCreate: (TerminalType, String?, String?) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Terminal Type")) {
                    Picker("Type", selection: $terminalType) {
                        Label("Regular Terminal", systemImage: "terminal")
                            .tag(TerminalType.regular)
                        Label("Cursor Agent", systemImage: "brain.head.profile")
                            .tag(TerminalType.cursorAgent)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(header: Text("Name (Optional)")) {
                    TextField("Terminal name", text: $name)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                Section(header: Text("Working Directory")) {
                    TextField("Optional: /path/to/dir", text: $workingDir)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                Section {
                    if terminalType == .cursorAgent {
                        Text("Cursor Agent terminal will automatically start the cursor-agent command")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Leave empty to use the default directory")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let dir = workingDir.isEmpty ? nil : workingDir
                        let sessionName = name.isEmpty ? nil : name
                        onCreate(terminalType, dir, sessionName)
                        dismiss()
                    }
                }
            }
        }
    }
}
