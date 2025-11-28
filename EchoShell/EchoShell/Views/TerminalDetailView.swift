//
//  TerminalDetailView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Detailed view for a single terminal session with two modes: PTY and Agent
//

import SwiftUI
import SwiftTerm

struct TerminalDetailView: View {
    let session: TerminalSession
    let config: TunnelConfig
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var navigationStateManager: NavigationStateManager
    @EnvironmentObject var sessionState: SessionStateManager
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var wsClient = WebSocketClient()
    @State private var terminalCoordinator: SwiftTermTerminalView.Coordinator?
    @State private var pendingData: [String] = []
    
    // Determine initial view mode based on terminal type
    private var initialViewMode: TerminalViewMode {
        // For regular terminals, ALWAYS use PTY mode (no agent mode available)
        if session.terminalType == .regular {
            return .pty
        }
        // For AI-powered terminals (cursor/claude/cursorAgent), default to agent mode
        if session.terminalType == .cursor || session.terminalType == .claude || session.terminalType == .cursor {
            return .agent
        }
        // Default to PTY for any other type
        return .pty
    }
    
    // Computed property to get current view mode from SessionStateManager
    private var viewMode: TerminalViewMode {
        // If this is the active session, use activeViewMode
        if session.id == sessionState.activeSessionId {
            return sessionState.activeViewMode
        }
        // Otherwise, get the saved mode for this session
        return sessionState.getViewMode(for: session.id)
    }
    
    @StateObject private var laptopHealthChecker = LaptopHealthChecker()
    
    // Get connection state for header
    private var connectionState: ConnectionState {
        return laptopHealthChecker.connectionState
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
            VStack(spacing: 0) {
                // For headless terminals (cursor/claude), always show agent view (chat interface)
                // For regular terminals, show PTY view
                if session.terminalType == .cursor || session.terminalType == .claude {
                    agentView
                } else {
                    // Regular terminals always use PTY
                    ptyTerminalView
                }
            }
        }
        .onChange(of: sessionState.activeViewMode) { oldValue, newValue in
            // View mode changed via SessionStateManager (single source of truth)
            // Save state before mode switch (but don't disconnect streams)
            // This ensures agent responses continue to work when switching modes
            print("🔄 Terminal view mode changed: \(oldValue == .agent ? "agent" : "pty") -> \(newValue == .agent ? "agent" : "pty")")
            
            // Don't disconnect recording stream on mode switch - keep it connected
            // Don't stop recording - allow continuous operation
            // This ensures agent responses continue to work when switching between agent/terminal modes
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Activate this session in global state (single source of truth)
            // For headless terminals (cursor/claude), always use agent mode (no PTY mode)
            // For regular terminals, always use PTY mode
            if session.terminalType == .regular {
                sessionState.setActiveSession(session.id, name: session.name ?? "", defaultMode: .pty)
                sessionState.setViewMode(.pty, for: session.id)
            } else {
                // For headless terminals, always use agent mode (chat interface)
                // No PTY mode available for cursor/claude terminals
                sessionState.setActiveSession(session.id, name: session.name ?? "", defaultMode: .agent)
                sessionState.setViewMode(.agent, for: session.id)
            }
            
            // Start health checker
            laptopHealthChecker.start(config: config)
        }
        .onDisappear {
            // Save view mode to global state before leaving (already handled by SessionStateManager)
            // Don't deactivate session on disappear - keep state for navigation
            laptopHealthChecker.stop()
        }
        .onReceive(EventBus.shared.toggleTerminalViewModePublisher) { mode in
            // For regular terminals, ignore toggle - always stay in PTY mode
            if session.terminalType == .regular {
                return
            }
            
            // For headless terminals (cursor/claude), ignore toggle - always stay in agent mode
            // No PTY mode available for headless terminals
            if session.terminalType == .cursor || session.terminalType == .claude {
                return
            }
        }
    }
    
    // PTY Terminal View (for regular terminals or PTY mode of AI terminals)
    private var ptyTerminalView: some View {
        VStack(spacing: 0) {
            SwiftTermTerminalView(onInput: { input in
                // Send exactly what user typed - no modifications
                // SwiftTerm sends input character by character, so we pass it through as-is
                self.wsClient.sendInput(input)
            }, onResize: { cols, rows in
                resizeTerminal(cols: cols, rows: rows)
            }, onReady: { coordinator in
                terminalCoordinator = coordinator
                for data in pendingData {
                    coordinator.feed(data)
                }
                pendingData.removeAll()
                coordinator.focus()
            })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SwiftUI.Color.black)
                .onTapGesture {
                    terminalCoordinator?.focus()
                }
        }
        .onAppear {
            // Clear terminal before connecting to avoid duplicate output
            if let coordinator = self.terminalCoordinator {
                coordinator.reset()
            }
            
            // Connect WebSocket for streaming
            wsClient.connect(
                config: config,
                sessionId: session.id,
                onMessage: { text in
                    // Only process non-empty text to avoid feeding empty strings
                    guard !text.isEmpty else { return }

                    // Feed raw output directly to SwiftTerm
                    // SwiftTerm handles ANSI sequences, tabs, formatting, and all terminal artifacts correctly
                    // Auto-scroll is now handled inside feed() method based on user's scroll position
                    if let coordinator = self.terminalCoordinator {
                        coordinator.feed(text)
                    } else {
                        self.pendingData.append(text)
                    }
                }
            )
            
            // Load history after a delay to ensure terminal is ready
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await loadHistory()
            }
            
            // Monitor connection state and reload history on reconnection
            Task {
                var lastState: ConnectionState = .disconnected
                while true {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // Check every second
                    
                    let currentState = wsClient.connectionState
                    // If we just reconnected (was disconnected/reconnecting, now connected)
                    if (lastState == .disconnected || lastState == .reconnecting) && 
                       currentState == .connected {
                        print("✅ Terminal WebSocket reconnected, reloading history...")
                        await loadHistory()
                    }
                    lastState = currentState
                }
            }
        }
        .onDisappear {
            wsClient.disconnect()
        }
    }
    
    // Agent View (for AI-powered terminals in agent mode)
    @ViewBuilder
    private var agentView: some View {
        // For headless terminals, show chat interface
        if session.terminalType == .cursor || session.terminalType == .claude {
            ChatTerminalView(session: session, config: config)
                .environmentObject(settingsManager)
        } else {
            // For regular terminals in agent mode, show chat interface too
            // (Terminal Session Agent View has been removed - using unified chat interface)
            ChatTerminalView(session: session, config: config)
                .environmentObject(settingsManager)
        }
    }
    
    private func loadHistory() async {
        let apiClient = APIClient(config: config)
        do {
            let history = try await apiClient.getHistory(sessionId: session.id)

            await MainActor.run {
                if let coordinator = self.terminalCoordinator {
                    if !history.isEmpty {
                        // Use feedHistory() to load without auto-scrolling
                        // This keeps the terminal at the current scroll position
                        // User can manually scroll to see history or bottom
                        coordinator.feedHistory(history)
                        print("✅ Loaded terminal history: \(history.count) characters")
                    }
                    coordinator.focus()
                }
            }
        } catch {
            print("❌ Error loading history: \(error)")
            await MainActor.run {
                if let coordinator = self.terminalCoordinator {
                    coordinator.focus()
                }
            }
        }
    }
    
    
    private func sendInput(_ input: String) {
        // Send exactly what user typed - no modifications
        // SwiftTerm handles input character by character, so we pass it through as-is
        // The server will normalize \n to \r if needed
        wsClient.sendInput(input)
    }
    
    private func resizeTerminal(cols: Int, rows: Int) {
        Task {
            let apiClient = APIClient(config: config)
            do {
                try await apiClient.resizeTerminal(sessionId: session.id, cols: cols, rows: rows)
                print("✅ Terminal resized: \(cols)x\(rows)")
            } catch {
                print("❌ Error resizing terminal: \(error)")
            }
        }
    }
}
