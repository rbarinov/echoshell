//
//  RecordingView.swift
//  EchoShell
//
//  Created by Roman Barinov on 2025.11.21.
//

import SwiftUI
import AVFoundation

struct RecordingView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var terminalViewModel = TerminalViewModel()
    @StateObject private var wsClient = WebSocketClient()
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showSessionPicker = false
    @State private var showModeTooltip: CommandMode? = nil
    @State private var lastTerminalOutput: String = ""
    @State private var accumulatedOutput: String = "" // Accumulate output chunks
    @State private var terminalScreen: TerminalScreenEmulator? = nil // Terminal screen emulator
    @State private var lastSentCommand: String = "" // Track last sent command to filter it from output
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        } else {
            audioRecorder.startRecording()
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Top bar: Mode toggle and connection status
                HStack {
                    if settingsManager.laptopConfig != nil {
                        // Custom Command Mode Toggle (only 2 buttons)
                        HStack(spacing: 4) {
                            // AI Agent button (icon only)
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    settingsManager.commandMode = .agent
                                }
                            }) {
                                Image(systemName: CommandMode.agent.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(settingsManager.commandMode == .agent ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(settingsManager.commandMode == .agent ? Color.blue : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .onLongPressGesture(minimumDuration: 0.5) {
                                showModeTooltip = .agent
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    if showModeTooltip == .agent {
                                        showModeTooltip = nil
                                    }
                                }
                            }
                            
                            // Direct Terminal button (icon only)
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    settingsManager.commandMode = .direct
                                }
                            }) {
                                Image(systemName: CommandMode.direct.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(settingsManager.commandMode == .direct ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(settingsManager.commandMode == .direct ? Color.blue : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .onLongPressGesture(minimumDuration: 0.5) {
                                showModeTooltip = .direct
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    if showModeTooltip == .direct {
                                        showModeTooltip = nil
                                    }
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.15))
                        )
                        .frame(maxWidth: 120)
                        .overlay(
                            // Tooltip overlay
                            Group {
                                if let mode = showModeTooltip {
                                    VStack(spacing: 0) {
                                        Text(mode.description)
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.black.opacity(0.85))
                                            )
                                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                                            .padding(.top, 55)
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                }
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showModeTooltip)
                        )
                    }
                    
                    Spacer()
                    
                    // Connection status indicator (just icon)
                    Image(systemName: settingsManager.laptopConfig != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(settingsManager.laptopConfig != nil ? .green : .red)
                        .font(.system(size: 18))
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                if settingsManager.laptopConfig != nil {
                    
                    // Terminal Session Selector (simplified)
                    HStack {
                        if terminalViewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if terminalViewModel.sessions.isEmpty {
                            Button(action: {
                                Task {
                                    if let config = settingsManager.laptopConfig {
                                        if terminalViewModel.apiClient == nil {
                                            terminalViewModel.apiClient = APIClient(config: config)
                                        }
                                        let _ = try? await terminalViewModel.apiClient?.createSession()
                                        await terminalViewModel.refreshSessions(config: config)
                                    }
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 14))
                                    Text("Create Session")
                                        .font(.subheadline)
                                }
                                .foregroundColor(.blue)
                            }
                        } else {
                            // Filter out invalid sessions and ensure selected session exists
                            let validSessions = terminalViewModel.sessions
                            let selectedId = settingsManager.selectedSessionId ?? validSessions.first?.id
                            let validSelectedId = validSessions.contains(where: { $0.id == selectedId }) ? selectedId : validSessions.first?.id
                            
                            HStack(spacing: 8) {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                Picker("Session", selection: Binding(
                                    get: { validSelectedId ?? "" },
                                    set: { newId in
                                        if validSessions.contains(where: { $0.id == newId }) {
                                            settingsManager.selectedSessionId = newId
                                        }
                                    }
                                )) {
                                    ForEach(validSessions) { session in
                                        Text(session.id)
                                            .tag(session.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .font(.system(size: colorScheme == .dark ? 16 : 14))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Button(action: {
                                    Task {
                                        if let config = settingsManager.laptopConfig {
                                            await terminalViewModel.refreshSessions(config: config)
                                        }
                                    }
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .onChange(of: terminalViewModel.sessions) { oldSessions, newSessions in
                                // Validate selected session when sessions list changes
                                if let currentSelected = settingsManager.selectedSessionId,
                                   !newSessions.contains(where: { $0.id == currentSelected }) {
                                    // Selected session no longer exists, select first available
                                    settingsManager.selectedSessionId = newSessions.first?.id
                                } else if settingsManager.selectedSessionId == nil && !newSessions.isEmpty {
                                    // No session selected, select first available
                                    settingsManager.selectedSessionId = newSessions.first?.id
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
                
                Spacer()
                    .frame(height: 20)
                
                // Main Record Button
                Button(action: {
                    toggleRecording()
                }) {
                    ZStack {
                        // Outer circle with gradient
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: audioRecorder.isRecording 
                                        ? [Color.red, Color.pink] 
                                        : [Color.blue, Color.cyan]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 160, height: 160)
                            .shadow(color: audioRecorder.isRecording 
                                ? Color.red.opacity(0.6) 
                                : Color.blue.opacity(0.5), 
                                radius: 20, x: 0, y: 10)
                        
                        // Inner circle
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 140, height: 140)
                        
                        // Icon
                        Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 55, weight: .medium))
                            .foregroundColor(.white)
                            .symbolEffect(.pulse, isActive: audioRecorder.isRecording)
                    }
                }
                .buttonStyle(.plain)
                .disabled(audioRecorder.isTranscribing || settingsManager.laptopConfig == nil)
                .scaleEffect(audioRecorder.isRecording ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: audioRecorder.isRecording)
                .padding(.horizontal, 30)
                    
                    // Status text
                    if audioRecorder.isRecording {
                        Text("Recording...")
                            .font(.title3)
                            .foregroundColor(.red)
                            .fontWeight(.semibold)
                    } else if settingsManager.laptopConfig == nil {
                        Text("Please connect to laptop in Settings")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    } else {
                        Text("Tap to Record")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                        .frame(height: 20)
                    
                    // Transcription indicator
                    if audioRecorder.isTranscribing {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Transcribing...")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)
                    }
                    
                    // Display last transcription/terminal output and statistics
                    if (!audioRecorder.recognizedText.isEmpty || !lastTerminalOutput.isEmpty) && !audioRecorder.isTranscribing {
                        VStack(alignment: .leading, spacing: 16) {
                            // Header
                            HStack {
                                Image(systemName: settingsManager.commandMode == .direct ? "terminal.fill" : "text.bubble.fill")
                                    .foregroundColor(.blue)
                                Text(settingsManager.commandMode == .direct ? "Command Result" : "Command Result")
                                    .font(.headline)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            
                            // Display text based on mode
                            // In both modes, show the result text (cleaned from ANSI codes)
                            let displayText = settingsManager.commandMode == .direct && !lastTerminalOutput.isEmpty 
                                ? lastTerminalOutput 
                                : audioRecorder.recognizedText
                            
                            Text(displayText)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineLimit(nil)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(12)
                                .padding(.horizontal, 20)
                            
                            // Statistics
                            if audioRecorder.lastRecordingDuration > 0 {
                                VStack(spacing: 12) {
                                    Divider()
                                        .padding(.horizontal, 20)
                                    
                                    // First row: duration, cost, processing time
                                    HStack(spacing: 16) {
                                        // Recording duration
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "mic.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                                Text("Recording")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Text(String(format: "%.1f s", audioRecorder.lastRecordingDuration))
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                        }
                                        
                                        Spacer()
                                        
                                        // Cost
                                        if audioRecorder.lastTranscriptionCost > 0 {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "dollarsign.circle")
                                                        .font(.caption)
                                                        .foregroundColor(.green)
                                                    Text("Cost")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Text(String(format: "$%.4f", audioRecorder.lastTranscriptionCost))
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        // Processing time
                                        if audioRecorder.lastTranscriptionDuration > 0 {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "hourglass")
                                                        .font(.caption)
                                                        .foregroundColor(.orange)
                                                    Text("Processing")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Text(String(format: "%.1f s", audioRecorder.lastTranscriptionDuration))
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    
                                    // Second row: network traffic
                                    if audioRecorder.lastNetworkUsage.sent > 0 || audioRecorder.lastNetworkUsage.received > 0 {
                                        HStack(spacing: 16) {
                                            // Sent
                                            if audioRecorder.lastNetworkUsage.sent > 0 {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "arrow.up.circle")
                                                            .font(.caption)
                                                            .foregroundColor(.purple)
                                                        Text("Upload")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Text(formatBytes(audioRecorder.lastNetworkUsage.sent))
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            // Received
                                            if audioRecorder.lastNetworkUsage.received > 0 {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "arrow.down.circle")
                                                            .font(.caption)
                                                            .foregroundColor(.purple)
                                                        Text("Download")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Text(formatBytes(audioRecorder.lastNetworkUsage.received))
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                }
                                            }
                                            
                                            Spacer()
                                        }
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                    
                Spacer()
                    .frame(height: 30)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .onAppear {
            // Configure AudioRecorder with settings
            audioRecorder.configure(with: settingsManager)
            
            // Load terminal sessions
            if let config = settingsManager.laptopConfig {
                Task {
                    await terminalViewModel.loadSessions(config: config)
                    // Set default session if none selected
                    if settingsManager.selectedSessionId == nil && !terminalViewModel.sessions.isEmpty {
                        settingsManager.selectedSessionId = terminalViewModel.sessions.first?.id
                    }
                    
                    // Connect WebSocket for terminal output tracking in direct mode
                    if let sessionId = settingsManager.selectedSessionId {
                        connectToTerminalStream(config: config, sessionId: sessionId)
                    }
                }
            }
        }
        .onChange(of: settingsManager.laptopConfig) { oldValue, newValue in
            if let config = newValue {
                Task {
                    await terminalViewModel.loadSessions(config: config)
                    // Reconnect WebSocket if session selected
                    if let sessionId = settingsManager.selectedSessionId {
                        connectToTerminalStream(config: config, sessionId: sessionId)
                    }
                }
            } else {
                wsClient.disconnect()
                terminalScreen = nil
            }
        }
        .onChange(of: settingsManager.selectedSessionId) { oldValue, newValue in
            // Reconnect WebSocket when session changes
            if let config = settingsManager.laptopConfig, let sessionId = newValue {
                connectToTerminalStream(config: config, sessionId: sessionId)
            }
        }
        .onChange(of: settingsManager.commandMode) { oldValue, newValue in
            // Reconnect WebSocket when mode changes to track output in direct mode
            if newValue == .direct, let config = settingsManager.laptopConfig, let sessionId = settingsManager.selectedSessionId {
                connectToTerminalStream(config: config, sessionId: sessionId)
            } else if newValue == .agent {
                // Clear terminal output when switching to agent mode
                // Ensure updates happen on main thread
                Task { @MainActor in
                    self.lastTerminalOutput = ""
                    self.accumulatedOutput = "" // Reset accumulated output
                    self.terminalScreen = nil // Reset terminal screen emulator
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CommandSentToTerminal"))) { notification in
            // Clear previous output when new command is sent in direct mode
            if settingsManager.commandMode == .direct {
                // Ensure updates happen on main thread
                Task { @MainActor in
                    self.lastTerminalOutput = ""
                    self.accumulatedOutput = "" // Reset accumulated output
                    self.terminalScreen = nil // Reset terminal screen emulator (new command = new screen state)
                }
                
                // Send command through WebSocket input instead of HTTP API
                // This ensures commands work with cursor-agent and other interactive apps
                if let userInfo = notification.userInfo,
                   let command = userInfo["command"] as? String,
                   let sessionId = userInfo["sessionId"] as? String {
                    
                    // Store command to filter it from output
                    Task { @MainActor in
                        self.lastSentCommand = command
                    }
                    
                    // Ensure WebSocket is connected to the correct session
                    if let config = settingsManager.laptopConfig {
                        // Reconnect if needed or if session changed
                        if !wsClient.isConnected || settingsManager.selectedSessionId != sessionId {
                            connectToTerminalStream(config: config, sessionId: sessionId)
                            // Wait a bit for connection to establish
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                if self.wsClient.isConnected {
                                    // Send command as a single string with \r at the end
                                    // This matches what xterm.js sends when user presses Enter
                                    self.sendCommandToTerminal(command, to: self.wsClient)
                                    print("📤 Sent command via WebSocket input: \(command)")
                                } else {
                                    print("⚠️ WebSocket not connected, command not sent")
                                }
                            }
                        } else {
                            // WebSocket is connected, send command immediately
                            // Send command as a single string with \r at the end
                            // This matches what xterm.js sends when user presses Enter
                            sendCommandToTerminal(command, to: wsClient)
                            print("📤 Sent command via WebSocket input: \(command)")
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TranscriptionStatsUpdated"))) { notification in
            print("📱 iOS RecordingView: Received TranscriptionStatsUpdated notification")
            if let userInfo = notification.userInfo {
                print("   📊 Updating RecordingView with new transcription:")
                print("      Text length: \((userInfo["text"] as? String ?? "").count) chars")
                
                // Update AudioRecorder with stats from Watch
                audioRecorder.recognizedText = userInfo["text"] as? String ?? ""
                audioRecorder.lastRecordingDuration = userInfo["recordingDuration"] as? TimeInterval ?? 0
                audioRecorder.lastTranscriptionCost = userInfo["transcriptionCost"] as? Double ?? 0
                audioRecorder.lastTranscriptionDuration = userInfo["processingTime"] as? TimeInterval ?? 0
                audioRecorder.lastNetworkUsage = (
                    sent: userInfo["uploadSize"] as? Int64 ?? 0,
                    received: userInfo["downloadSize"] as? Int64 ?? 0
                )
                
                print("   ✅ RecordingView updated successfully")
            }
        }
    }
    
    // Format bytes to readable format
    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1.0 {
            return "\(bytes) B"
        } else if kb < 1024.0 {
            return String(format: "%.0f KB", kb)
        } else {
            let mb = kb / 1024.0
            return String(format: "%.2f MB", mb)
        }
    }
    
    // Connect to terminal WebSocket stream for output tracking
    private func connectToTerminalStream(config: TunnelConfig, sessionId: String) {
        wsClient.disconnect() // Disconnect previous connection
        terminalScreen = nil // Reset terminal screen emulator
        
        // Only connect if in direct mode
        guard settingsManager.commandMode == .direct else {
            return
        }
        
        wsClient.connect(config: config, sessionId: sessionId) { text in
            // Process output through terminal screen emulator
            // This properly handles ANSI escape sequences that delete/overwrite text
            // Ensure all @State updates happen on main thread
            Task { @MainActor in
                // Initialize terminal screen emulator if needed
                if self.terminalScreen == nil {
                    self.terminalScreen = TerminalScreenEmulator()
                }
                
                // Process the text through terminal emulator
                // This handles ANSI sequences like [2K (clear line), [1A (move up), [G (move to start)
                self.terminalScreen?.processOutput(text)
                
                // Get current screen state (final rendered output)
                if let screenOutput = self.terminalScreen?.getScreenContent() {
                    // Filter out intermediate "Generating..." messages
                    var filteredOutput = self.filterIntermediateMessages(screenOutput)
                    
                    // Filter out user's command if it appears in output
                    if !self.lastSentCommand.isEmpty {
                        // Remove command text from output (it might appear as echo)
                        let commandLines = self.lastSentCommand.components(separatedBy: .newlines)
                        for commandLine in commandLines {
                            let trimmedCommand = commandLine.trimmingCharacters(in: .whitespaces)
                            if !trimmedCommand.isEmpty {
                                // Remove lines that match the command
                                let lines = filteredOutput.components(separatedBy: .newlines)
                                filteredOutput = lines.filter { line in
                                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                                    // Skip lines that exactly match or contain the command
                                    return !trimmed.contains(trimmedCommand) || trimmed.count > trimmedCommand.count + 50
                                }.joined(separator: "\n")
                            }
                        }
                    }
                    
                    // Extract result from filtered output
                    let result = self.extractCommandResult(from: filteredOutput)
                    
                    if !result.isEmpty {
                        // Update terminal output with extracted result
                        self.lastTerminalOutput = result
                    } else if !filteredOutput.isEmpty {
                        // If extraction returned empty, use filtered text directly
                        let lines = filteredOutput.components(separatedBy: .newlines)
                        let meaningfulLines = lines.filter { line in
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            return trimmed.count > 3 // At least 3 characters
                        }
                        
                        if !meaningfulLines.isEmpty {
                            let meaningfulText = meaningfulLines.joined(separator: "\n")
                            // Take last 1000 characters to avoid memory issues
                            if meaningfulText.count > 1000 {
                                self.lastTerminalOutput = String(meaningfulText.suffix(1000))
                            } else {
                                self.lastTerminalOutput = meaningfulText
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Format command for terminal: handle multiline commands
    // For multiline commands, send each line separately followed by \r
    private func formatCommandForTerminal(_ command: String) -> [String] {
        // Split command by newlines
        let lines = command.components(separatedBy: .newlines)
        
        // Clean each line and return as array
        // We'll send each line separately, then \r after each
        return lines.map { line in
            line.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
        }.filter { !$0.isEmpty }
    }
    
    // Send command to terminal - send command text first, then \r separately
    // This matches what xterm.js does: sends command text, then Enter sends \r separately
    // The \r (13 bytes) must be sent as a separate message for cursor-agent to process it correctly
    private func sendCommandToTerminal(_ command: String, to wsClient: WebSocketClient) {
        // Remove any trailing \r or \n from command
        let cleanedCommand = command.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
        
        // Send command text first (without \r)
        if !cleanedCommand.isEmpty {
            wsClient.sendInput(cleanedCommand)
        }
        
        // Then send \r separately on a new line (as a separate message)
        // This is what xterm.js does when user presses Enter - sends \r (13 bytes) separately
        // Small delay to ensure command text is sent first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            wsClient.sendInput("\r")
        }
    }
    
    // Extract command result from terminal output
    // Removes prompts and keeps only the actual result text (like Cursor shows)
    // Code is identified by being inside boxes (rectangles with ┌─┐, │, └─┘), not by keywords
    // Also extracts results that are NOT in boxes (like "3 + 3 = 6")
    private func extractCommandResult(from output: String) -> String {
        // Split into lines for processing
        let lines = output.components(separatedBy: .newlines)
        
        // Find code boxes - content inside rectangles (┌─┐, │ content │, └─┘)
        var codeBoxes: [String] = []
        var resultLines: [String] = [] // Results not in boxes
        var currentBox: [String] = []
        var inBox = false
        var boxStartIndex = -1
        
        // Box drawing characters
        let boxChars = ["┌", "┐", "└", "┘", "│", "─"]
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check if line starts a box (contains ┌)
            if trimmed.contains("┌") && !inBox {
                inBox = true
                currentBox = []
                boxStartIndex = index
                continue
            }
            
            // Check if line ends a box (contains └)
            if trimmed.contains("└") && inBox {
                inBox = false
                if !currentBox.isEmpty {
                    // Extract content from box lines (remove │ characters and clean)
                    let boxContent = currentBox.map { boxLine in
                        // Remove │ characters from start and end
                        var cleaned = boxLine.trimmingCharacters(in: .whitespaces)
                        // Remove leading │
                        if cleaned.hasPrefix("│") {
                            cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespaces)
                        }
                        // Remove trailing │
                        if cleaned.hasSuffix("│") {
                            cleaned = String(cleaned.dropLast()).trimmingCharacters(in: .whitespaces)
                        }
                        return cleaned
                    }.filter { !$0.isEmpty }
                    
                    if !boxContent.isEmpty {
                        let boxText = boxContent.joined(separator: " ")
                        
                        // Skip boxes with user commands
                        if !lastSentCommand.isEmpty {
                            let normalizedCommand = lastSentCommand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            let normalizedBox = boxText.lowercased()
                            if normalizedBox.contains(normalizedCommand) || normalizedCommand.contains(normalizedBox) {
                                // This is the user's command, skip it
                                currentBox = []
                                continue
                            }
                        }
                        
                        // Skip UI boxes like "→ Add a follow-up"
                        if boxText.contains("Add a follow-up") || boxText.contains("follow-up") {
                            currentBox = []
                            continue
                        }
                        
                        // This is a code/result box, keep it
                        codeBoxes.append(boxContent.joined(separator: "\n"))
                    }
                }
                currentBox = []
                boxStartIndex = -1
                continue
            }
            
            // If we're inside a box, collect content lines
            if inBox {
                // Skip border lines (only ─ characters and box chars)
                if !trimmed.allSatisfy({ boxChars.contains(String($0)) || $0.isWhitespace }) {
                    currentBox.append(line)
                }
            } else {
                // We're not in a box - check if this is a result line
                // Skip empty lines
                if trimmed.isEmpty {
                    continue
                }
                
                // Skip lines that are only box characters or ANSI sequences
                let printableChars = trimmed.unicodeScalars.filter { scalar in
                    let value = scalar.value
                    return (value >= 32 && value <= 126) || (value >= 0x80 && value <= 0x10FFFF)
                }
                if printableChars.count < 3 {
                    continue
                }
                
                // Skip lines with box characters (they're part of boxes we already processed)
                if boxChars.contains(where: { trimmed.contains($0) }) {
                    continue
                }
                
                // Skip status lines
                if trimmed.contains("Auto") && trimmed.contains("·") {
                    continue
                }
                if trimmed.contains("/ commands") || trimmed.contains("@ files") {
                    continue
                }
                if trimmed.contains("review edits") {
                    continue
                }
                
                // Skip lines with ANSI dim codes (semi-transparent UI text)
                if line.contains("\u{001B}[2") || line.contains("\u{001B}[2m") {
                    let textWithoutAnsi = removeAnsiCodes(from: line)
                    let trimmedNoAnsi = textWithoutAnsi.trimmingCharacters(in: .whitespaces)
                    
                    // Skip dim text that looks like UI hints
                    if trimmedNoAnsi.count < 50 {
                        let uiPhrases = ["review edits", "add a follow-up", "follow-up", 
                                        "ctrl+r", "commands", "@ files", "! shell"]
                        for phrase in uiPhrases {
                            if trimmedNoAnsi.lowercased().contains(phrase.lowercased()) {
                                continue
                            }
                        }
                    }
                }
                
                // Skip progress lines
                if trimmed.range(of: "tokens", options: .caseInsensitive) != nil {
                    continue
                }
                if trimmed.range(of: "reading|editing|generating", options: [.regularExpression, .caseInsensitive]) != nil &&
                   (trimmed.contains("⬡") || trimmed.contains("⬢")) {
                    continue
                }
                
                // Skip user commands (not in boxes, but might be echoed)
                if !lastSentCommand.isEmpty {
                    let normalizedCommand = lastSentCommand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let normalizedLine = trimmed.lowercased()
                    if normalizedLine == normalizedCommand || normalizedLine.contains(normalizedCommand) {
                        continue
                    }
                }
                
                // This looks like a result line (not in a box, not a status, not a command)
                // Examples: "3 + 3 = 6", function definitions, etc.
                resultLines.append(trimmed)
            }
        }
        
        // Priority: code boxes first, then result lines
        if !codeBoxes.isEmpty {
            // Return the last (most recent) code box
            return codeBoxes.last!
        } else if !resultLines.isEmpty {
            // Return result lines (like "3 + 3 = 6")
            return resultLines.joined(separator: "\n")
        }
        
        return ""
    }
    
    // Filter out intermediate messages like "Generating..." and status indicators
    private func filterIntermediateMessages(_ output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        
        // Filter out lines that contain intermediate status messages
        let meaningfulLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            if trimmed.isEmpty {
                return false
            }
            
            // Skip lines containing "Generating" (case insensitive)
            if trimmed.range(of: "generating", options: .caseInsensitive) != nil {
                return false
            }
            
            // Skip progress/status lines: "Reading", "Processing", "Analyzing", "Editing", etc.
            // Note: Russian words are NOT filtered - they are part of the result, not system messages
            let progressKeywords = ["reading", "processing", "analyzing", "thinking", "working", 
                                   "loading", "calculating", "computing", "executing", "running",
                                   "preparing", "initializing", "starting", "waiting", "checking",
                                   "editing", "generating", "adding", "creating", "updating"]
            
            // Check for progress keywords in the line
            for keyword in progressKeywords {
                if trimmed.range(of: keyword, options: .caseInsensitive) != nil {
                    // Skip if it's a progress line
                    // Progress lines are usually:
                    // 1. Short lines (< 100 chars) that start with the keyword
                    // 2. Lines that are just status messages (contain symbols like ⬡, ⬢)
                    // 3. Lines with "..." or ".." or "." at the end (indicating progress)
                    let isShortProgress = trimmed.count < 100 && 
                                         (trimmed.hasPrefix(keyword.capitalized) || 
                                          trimmed.hasPrefix(keyword.uppercased()) ||
                                          trimmed.lowercased().hasPrefix(keyword))
                    
                    let hasProgressSymbols = trimmed.contains("⬡") || trimmed.contains("⬢")
                    let endsWithDots = trimmed.hasSuffix("...") || trimmed.hasSuffix("..") || trimmed.hasSuffix(".")
                    
                    if isShortProgress || (hasProgressSymbols && endsWithDots) {
                        return false
                    }
                }
            }
            
            // Skip lines with "file edited", "files edited" - these are status messages
            if trimmed.range(of: "file edited", options: .caseInsensitive) != nil ||
               trimmed.range(of: "files edited", options: .caseInsensitive) != nil {
                return false
            }
            
            // Skip lines with "tokens" (e.g., "Reading    xyz tokens", "Editing     xyz tokens")
            if trimmed.range(of: "tokens", options: .caseInsensitive) != nil {
                return false
            }
            
            // Don't filter Russian words - they are part of the result, not system messages
            // System messages are in English, so Russian text is always part of the actual result
            
            // Skip lines that are just status updates (short lines with action verbs)
            // Pattern: "Verb + object" (e.g., "Adding function", "Created file")
            // Note: Russian words are NOT filtered - they are part of the result
            let actionPatterns = [
                "^\\s*(adding|created|updated|modified|deleted|removed|changed)\\s+"
            ]
            for pattern in actionPatterns {
                if trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    // If it's a short line (< 100 chars) and ends with dots or is just a status, skip it
                    if trimmed.count < 100 || trimmed.hasSuffix("...") || trimmed.hasSuffix("..") {
                        return false
                    }
                }
            }
            
            // Skip status lines with "Auto" and percentage indicators
            if trimmed.range(of: "Auto", options: .caseInsensitive) != nil &&
               (trimmed.contains("·") || trimmed.contains("%") || trimmed.contains("/ commands")) {
                return false
            }
            
            // Skip lines with percentage indicators that indicate progress (e.g., "50%", "3.7%")
            // But keep lines that might contain percentages as part of results (e.g., "Price: $100 (10% discount)")
            if trimmed.range(of: "^\\s*[0-9]+\\.[0-9]+%\\s*$", options: .regularExpression) != nil ||
               (trimmed.contains("%") && trimmed.count < 30 && !trimmed.contains(":") && !trimmed.contains("=")) {
                return false
            }
            
            // Skip lines that contain ANSI dim/faint escape sequences (semi-transparent text)
            // Dim text is usually UI hints like "review edits" that should be filtered
            // ANSI code 2 means dim/faint: \u{001B}[2m or \u{001B}[2;...m
            if line.contains("\u{001B}[2") || line.contains("\u{001B}[2m") {
                // Check if this is dim text (semi-transparent UI element)
                // Extract text without ANSI codes to check content
                let textWithoutAnsi = removeAnsiCodes(from: line)
                let trimmedNoAnsi = textWithoutAnsi.trimmingCharacters(in: .whitespaces)
                
                // Skip dim text that looks like UI hints (short lines with common UI phrases)
                if trimmedNoAnsi.count < 50 {
                    // Common UI phrases in dim text
                    let uiPhrases = ["review edits", "add a follow-up", "follow-up", 
                                    "ctrl+r", "commands", "@ files", "! shell"]
                    for phrase in uiPhrases {
                        if trimmedNoAnsi.lowercased().contains(phrase.lowercased()) {
                            return false
                        }
                    }
                }
            }
            
            // Skip Cursor Agent menu lines: "/ commands · @ files · ! shell"
            if trimmed.contains("/ commands") || 
               (trimmed.contains("·") && trimmed.contains("@ files") && trimmed.contains("! shell")) {
                return false
            }
            
            // Skip "review edits" and similar Cursor Agent UI messages
            if trimmed.range(of: "review edits", options: .caseInsensitive) != nil {
                return false
            }
            
            // Skip Cursor Agent UI boxes (lines with box drawing characters)
            // Check for box drawing characters: ┌ ┐ └ ┘ │ ─
            let boxChars = ["┌", "┐", "└", "┘", "│", "─", "├", "┤", "┬", "┴"]
            let hasBoxChars = boxChars.contains { trimmed.contains($0) }
            if hasBoxChars {
                // Count box characters in the line
                let boxCharCount = boxChars.reduce(0) { count, char in
                    count + trimmed.components(separatedBy: char).count - 1
                }
                // If more than 1 box character, it's likely a UI box (including user command boxes)
                // This will filter out:
                // - Box borders (┌─┐, └─┘)
                // - Box content lines (│ command text │)
                // - All UI elements with boxes
                if boxCharCount > 1 {
                    return false
                }
                // Also skip lines with "→ Add a follow-up" or similar UI prompts
                if trimmed.contains("→") && (trimmed.contains("Add a follow-up") || 
                                             trimmed.contains("follow-up") ||
                                             trimmed.range(of: "→.*", options: .regularExpression) != nil) {
                    return false
                }
            }
            
            // Skip lines that are mostly symbols (⬡, ⬢) and formatting
            if trimmed.contains("⬡") || trimmed.contains("⬢") {
                // Check if line has meaningful content beyond the symbol
                let withoutSymbols = trimmed.replacingOccurrences(of: "⬡", with: "")
                let withoutSymbols2 = withoutSymbols.replacingOccurrences(of: "⬢", with: "")
                let cleaned = withoutSymbols2.trimmingCharacters(in: .whitespaces)
                
                // If after removing symbols there's nothing meaningful, skip it
                if cleaned.isEmpty || cleaned.count < 3 {
                    return false
                }
                
                // If the remaining text is just "Generating" variations, skip it
                if cleaned.range(of: "generating", options: .caseInsensitive) != nil {
                    return false
                }
            }
            
            // Skip lines that are mostly formatting characters and symbols
            let printableChars = trimmed.unicodeScalars.filter { scalar in
                let value = scalar.value
                // Count printable ASCII and Unicode characters
                return (value >= 32 && value <= 126) || (value >= 0x80 && value <= 0x10FFFF)
            }
            
            // Skip lines with too few printable characters (likely just formatting)
            if printableChars.count < 3 {
                return false
            }
            
            // Keep lines with meaningful content
            return true
        }
        
        return meaningfulLines.joined(separator: "\n")
    }
    
    // Helper function to remove ANSI escape sequences from text
    private func removeAnsiCodes(from text: String) -> String {
        // Pattern for ANSI escape sequences: ESC[ followed by numbers/semicolons and a letter
        let pattern = #"\x1b\[[0-9;]*[a-zA-Z]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
    
    // Clean terminal output for TTS (remove ANSI sequences, keep text readable)
    private func cleanTerminalOutput(_ output: String) -> String {
        var cleaned = output
        
        // Remove ANSI escape sequences more aggressively
        // Pattern: ESC[ followed by numbers/semicolons and a letter
        cleaned = cleaned.replacingOccurrences(
            of: "\\u{001B}\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
        
        // Also remove common ANSI sequences like [2K, [1A, [G, etc.
        cleaned = cleaned.replacingOccurrences(
            of: "\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
        
        // Remove control characters except newline and tab
        // Keep printable ASCII, newline, tab, and Unicode characters (including Cyrillic, etc.)
        cleaned = cleaned.unicodeScalars.filter { scalar in
            let value = scalar.value
            // Keep printable ASCII (32-126), newline (10), tab (9)
            if (value >= 32 && value <= 126) || value == 10 || value == 9 {
                return true
            }
            // Keep Unicode characters (including Cyrillic, emoji, etc.)
            if value >= 0x80 && value <= 0x10FFFF {
                // Filter out control characters but keep printable Unicode
                return !CharacterSet.controlCharacters.contains(scalar)
            }
            return false
        }.map { Character($0) }.reduce("") { $0 + String($1) }
        
        // Convert tabs to spaces
        cleaned = cleaned.replacingOccurrences(of: "\t", with: "    ")
        
        // Normalize line endings
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "\n")
        
        return cleaned
    }
    
}

#Preview {
    RecordingView()
        .environmentObject(SettingsManager())
}

