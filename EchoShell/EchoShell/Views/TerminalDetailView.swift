//
//  TerminalDetailView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Detailed view for a single terminal session with real-time streaming
//

import SwiftUI
import SwiftTerm

struct TerminalDetailView: View {
    let session: TerminalSession
    let config: TunnelConfig
    
    @StateObject private var wsClient = WebSocketClient()
    @State private var terminalCoordinator: SwiftTermTerminalView.Coordinator?
    @State private var pendingData: [String] = []  // Buffer data until terminal is ready
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal output using SwiftTerm (professional VT100/ANSI emulation)
            SwiftTermTerminalView(onInput: { input in
                // Send user input directly to terminal via WebSocket
                sendInput(input)
            }, onResize: { cols, rows in
                // Send terminal size to laptop
                resizeTerminal(cols: cols, rows: rows)
            }, onReady: { coordinator in
                // Store coordinator reference when terminal is ready
                terminalCoordinator = coordinator
                // Feed any pending data
                for data in pendingData {
                    coordinator.feed(data)
                }
                pendingData.removeAll()
                // Ensure terminal has focus and keyboard is visible
                coordinator.focus()
            })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SwiftUI.Color.black)
                .onTapGesture {
                    // When user taps terminal, ensure it gets focus
                    terminalCoordinator?.focus()
                }
        }
        .navigationTitle(session.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(session.id)
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 6) {
                        Text(session.workingDir)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Circle()
                            .fill(wsClient.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(false)
        .onAppear {
            // Connect WebSocket for streaming
            wsClient.connect(config: config, sessionId: session.id) { text in
                // Filter out zsh's % symbol that appears when prompt doesn't end with newline
                // This matches the web interface behavior (xterm.js handles it differently)
                let cleanedText = self.removeZshPercentSymbol(text)
                
                // Feed data directly to terminal - SwiftTerm handles all control characters
                // SwiftTerm handles \r\n, \r, tabs, and all ANSI sequences properly
                // Callback is dispatched to main thread in WebSocketClient
                if let coordinator = self.terminalCoordinator {
                    // feed() already handles auto-scrolling
                    coordinator.feed(cleanedText)
                } else {
                    // Terminal not ready yet - buffer the data
                    self.pendingData.append(cleanedText)
                }
            }
            
            // Load history after a short delay to ensure terminal is ready
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 second
                await loadHistory()
                // After loading history, ensure terminal has focus
                await MainActor.run {
                    self.terminalCoordinator?.focus()
                }
            }
        }
        .onDisappear {
            wsClient.disconnect()
        }
    }
    
    private func loadHistory() async {
        let apiClient = APIClient(config: config)
        do {
            let history = try await apiClient.getHistory(sessionId: session.id)
            
            // Feed history directly to terminal - SwiftTerm handles all control characters
            await MainActor.run {
                if let coordinator = self.terminalCoordinator {
                    if !history.isEmpty {
                        // Filter out zsh's % symbol from history as well
                        let cleanedHistory = self.removeZshPercentSymbol(history)
                        // Don't reset - just feed history to preserve terminal state
                        // feed() already handles auto-scrolling
                        coordinator.feed(cleanedHistory)
                        print("✅ Loaded terminal history: \(history.count) characters")
                    }
                    // Always ensure terminal has focus to show keyboard and cursor
                    coordinator.focus()
                }
            }
        } catch {
            print("❌ Error loading history: \(error)")
            // Even if history load fails, ensure terminal has focus
            await MainActor.run {
                self.terminalCoordinator?.focus()
            }
        }
    }
    
    /// Remove zsh's % symbol that appears when prompt doesn't end with newline
    /// This matches the web interface behavior where xterm.js handles it differently
    private func removeZshPercentSymbol(_ text: String) -> String {
        var cleaned = text
        
        // Remove debug/UI text that shouldn't appear in terminal
        cleaned = cleaned.replacingOccurrences(of: "History", with: "")
        cleaned = cleaned.replacingOccurrences(of: "Load Full History", with: "")
        
        // Pattern 1: Remove ANSI-encoded % symbol with various formatting sequences
        // This is zsh's way of displaying % with formatting when prompt doesn't end with newline
        // Pattern: ESC[1mESC[7m%ESC[27mESC[1mESC[0m or variations
        // Make it flexible to catch different combinations
        cleaned = cleaned.replacingOccurrences(
            of: "\\u{001B}\\[[0-9;]*m\\u{001B}\\[7m%\\u{001B}\\[27m\\u{001B}\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
        
        // Pattern 2: Simpler ANSI % pattern: [7m%[27m (inverse video) - catch standalone
        cleaned = cleaned.replacingOccurrences(
            of: "\\u{001B}\\[7m%\\u{001B}\\[27m",
            with: "",
            options: .regularExpression
        )
        
        // Pattern 3: Catch % with any ANSI sequences around it (flexible pattern)
        // This catches cases like: ESC[...m%ESC[...m or ESC[...m%ESC[0m
        cleaned = cleaned.replacingOccurrences(
            of: "\\u{001B}\\[[0-9;]*m%\\u{001B}\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
        
        // Pattern 4: Remove " %" (space + percent) - most common case like "→ ~ %"
        cleaned = cleaned.replacingOccurrences(
            of: " %",
            with: " ",
            options: []
        )
        
        // Pattern 5: Remove "% " (percent + space) - handles "→ ~ % "
        cleaned = cleaned.replacingOccurrences(
            of: "% ",
            with: " ",
            options: []
        )
        
        // Pattern 6: Remove "%" at end of line (before newline/carriage return)
        cleaned = cleaned.replacingOccurrences(
            of: "%(?=\\r|\\n)",
            with: "",
            options: .regularExpression
        )
        
        // Pattern 7: Remove standalone "%" at very end of string (before cursor)
        while cleaned.hasSuffix("%") {
            cleaned = String(cleaned.dropLast())
        }
        
        // Pattern 8: Remove "%" that appears directly after common prompt characters (no space)
        cleaned = cleaned.replacingOccurrences(
            of: "([~→])%",
            with: "$1",
            options: .regularExpression
        )
        
        return cleaned
    }
    
    
    private func sendInput(_ input: String) {
        // Send input directly to terminal PTY via WebSocket
        wsClient.sendInput(input)
    }
    
    private func resizeTerminal(cols: Int, rows: Int) {
        // Send resize request to laptop
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

struct TerminalMessageRow: View {
    let message: TerminalMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(message.timestamp, style: .time)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 60, alignment: .leading)
            
            // Message content
            Text(message.data)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(messageColor)
                .textSelection(.enabled)
        }
    }
    
    private var messageColor: SwiftUI.Color {
        switch message.type {
        case .command:
            return .cyan
        case .error:
            return .red
        case .output:
            return .white
        case .status:
            return .yellow
        }
    }
}
