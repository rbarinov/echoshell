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
    @State private var lastTerminalOutput: String = "" // Accumulated output (not replaced, but appended)
    @State private var accumulatedOutput: String = "" // Accumulate output chunks
    @State private var terminalScreen: TerminalScreenEmulator? = nil // Terminal screen emulator
    @State private var lastSentCommand: String = "" // Track last sent command to filter it from output
    @State private var ttsTimer: Timer? = nil // Timer for auto TTS after 5 seconds of silence
    @State private var lastTTSOutput: String = "" // Track what was last spoken to avoid duplicates
    @State private var accumulatedForTTS: String = "" // Accumulated text for TTS (all messages)
    @StateObject private var audioPlayer = AudioPlayer() // Audio player for TTS
    @State private var ttsQueue: [String] = [] // Queue for TTS messages
    @State private var lastOutputSnapshot: String = "" // Snapshot of output when timer started
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        } else {
            // Clear previous output when starting new recording
            Task { @MainActor in
                self.lastTerminalOutput = ""
                self.accumulatedOutput = ""
                self.terminalScreen = nil
                self.lastSentCommand = ""
                self.lastTTSOutput = ""
                self.accumulatedForTTS = ""
                self.lastOutputSnapshot = ""
                self.ttsQueue = []
                self.ttsTimer?.invalidate()
                self.ttsTimer = nil
            }
            audioRecorder.startRecording()
        }
    }
    
    var body: some View {
        viewModifiers
    }
    
    private var mainContentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                topBarView
                
                if settingsManager.laptopConfig != nil {
                    sessionSelectorView
                }
                
                Spacer()
                    .frame(height: 20)
                
                recordButtonView
                
                statusTextView
                
                Spacer()
                    .frame(height: 20)
                
                transcriptionIndicatorView
                
                resultDisplayView
            }
        }
    }
    
    private var topBarView: some View {
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
    }
    
    private var sessionSelectorView: some View {
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
    
    private var recordButtonView: some View {
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
    }
    
    private var statusTextView: some View {
        // Status text
        Group {
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
        }
    }
    
    private var transcriptionIndicatorView: some View {
        // Transcription indicator
        Group {
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
        }
    }
    
    private var resultDisplayView: some View {
        // Display last transcription/terminal output and statistics
        Group {
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
                    // In direct mode, show terminal output (result), not the command
                    // In agent mode, show the result from audioRecorder
                    Text(settingsManager.commandMode == .direct 
                        ? (lastTerminalOutput.isEmpty ? "" : lastTerminalOutput)
                        : audioRecorder.recognizedText)
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
                
                Spacer()
                    .frame(height: 30)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }
    
    // MARK: - View Modifiers
    private var viewModifiers: some View {
        mainContentView
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
                    // Cancel any pending TTS
                    self.ttsTimer?.invalidate()
                    self.ttsTimer = nil
                    self.lastTTSOutput = "" // Reset last spoken text
                    self.accumulatedForTTS = "" // Reset accumulated TTS text
                    self.lastOutputSnapshot = "" // Reset output snapshot
                    self.ttsQueue = [] // Clear TTS queue
                    
                    // Clear terminal output when switching to agent mode
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
                    // Cancel any pending TTS
                    self.ttsTimer?.invalidate()
                    self.ttsTimer = nil
                    self.lastTTSOutput = "" // Reset last spoken text
                    self.accumulatedForTTS = "" // Reset accumulated TTS text
                    self.lastOutputSnapshot = "" // Reset output snapshot
                    self.ttsQueue = [] // Clear TTS queue
                    
                    // Don't clear lastTerminalOutput - keep accumulated output between commands
                    // Only clear accumulated output and screen emulator
                    self.accumulatedOutput = "" // Reset accumulated output
                    self.terminalScreen = nil // Reset terminal screen emulator (new command = new screen state)
                    self.lastSentCommand = notification.userInfo?["command"] as? String ?? "" // Store the command
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TranscriptionStarted"))) { _ in
            // Clear all terminal output when transcription starts
            Task { @MainActor in
                self.lastTerminalOutput = ""
                self.accumulatedOutput = ""
                self.terminalScreen = nil
                self.lastSentCommand = ""
                self.lastTTSOutput = ""
                self.accumulatedForTTS = ""
                self.lastOutputSnapshot = ""
                self.ttsQueue = []
                self.ttsTimer?.invalidate()
                self.ttsTimer = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TranscriptionStatsUpdated"))) { notification in
            print("📱 iOS RecordingView: Received TranscriptionStatsUpdated notification")
            if let userInfo = notification.userInfo {
                print("   📊 Updating RecordingView with new transcription:")
                print("      Text length: \((userInfo["text"] as? String ?? "").count) chars")
                
                // Update AudioRecorder with stats from Watch (ensure main thread)
                Task { @MainActor in
                    self.audioRecorder.recognizedText = userInfo["text"] as? String ?? ""
                    self.audioRecorder.lastRecordingDuration = userInfo["recordingDuration"] as? TimeInterval ?? 0
                    self.audioRecorder.lastTranscriptionCost = userInfo["transcriptionCost"] as? Double ?? 0
                    self.audioRecorder.lastTranscriptionDuration = userInfo["processingTime"] as? TimeInterval ?? 0
                    self.audioRecorder.lastNetworkUsage = (
                        sent: userInfo["uploadSize"] as? Int64 ?? 0,
                        received: userInfo["downloadSize"] as? Int64 ?? 0
                    )
                    
                    print("   ✅ RecordingView updated successfully")
                }
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
                    // Debug: log raw screen output
                    if !screenOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        print("📺 Raw screen output (\(screenOutput.count) chars): \(screenOutput.prefix(300))")
                    }
                    
                    // Filter out only specific UI elements:
                    // 1. Lines starting with vertical pipe (│) - box borders
                    // 2. Lines with ANSI dim codes (semi-transparent UI text)
                    // 3. Lines starting with hexagon symbols (⬢, ⬡) - status indicators
                    // All other lines should be kept and appended
                    var filteredOutput = self.filterIntermediateMessages(screenOutput)
                    
                    // Debug: log filtered output
                    if !filteredOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        print("🔍 Filtered output (\(filteredOutput.count) chars): \(filteredOutput.prefix(300))")
                    }
                    
                    // Filter out user's command if it appears in output
                    // But be careful - only remove exact matches or very short lines that are just the command
                    if !self.lastSentCommand.isEmpty {
                        // Remove command text from output (it might appear as echo)
                        let commandLines = self.lastSentCommand.components(separatedBy: .newlines)
                        for commandLine in commandLines {
                            let trimmedCommand = commandLine.trimmingCharacters(in: .whitespaces)
                            if !trimmedCommand.isEmpty && trimmedCommand.count > 3 {
                                // Only remove lines that are exactly the command or very similar
                                // Don't remove lines that contain the command as part of a larger result
                                let lines = filteredOutput.components(separatedBy: .newlines)
                                filteredOutput = lines.filter { line in
                                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                                    // Only skip if line is exactly the command or very close to it
                                    // Keep lines that are significantly longer (likely results)
                                    let normalizedLine = trimmed.lowercased()
                                    let normalizedCommand = trimmedCommand.lowercased()
                                    
                                    // Skip only if:
                                    // 1. Line exactly matches command (ignoring case)
                                    // 2. Line is very short and contains command (likely just echo)
                                    // 3. Line is command with just a few extra characters (like prompt)
                                    if normalizedLine == normalizedCommand {
                                        return false // Exact match - skip
                                    }
                                    if trimmed.count <= trimmedCommand.count + 5 && normalizedLine.contains(normalizedCommand) {
                                        return false // Very short line containing command - likely echo
                                    }
                                    // Keep everything else - it's likely a result
                                    return true
                                }.joined(separator: "\n")
                            }
                        }
                    }
                    
                    // Extract result from filtered output
                    let result = self.extractCommandResult(from: filteredOutput)
                    
                    // Debug logging
                    if !result.isEmpty {
                        print("✅ RecordingView: Extracted result (\(result.count) chars): \(result.prefix(200))")
                    } else if !filteredOutput.isEmpty {
                        print("⚠️ RecordingView: extractCommandResult returned empty, filteredOutput (\(filteredOutput.count) chars): \(filteredOutput.prefix(200))")
                    }
                    
                    // Always try to update output, even if extraction returns empty
                    var textToAppend: String = ""
                    
                    if !result.isEmpty {
                        // Use extracted result
                        textToAppend = result
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
                            textToAppend = meaningfulText.count > 1000 
                                ? String(meaningfulText.suffix(1000))
                                : meaningfulText
                        }
                    }
                    
                    // Update output if we have text
                    if !textToAppend.isEmpty {
                        let newText = self.appendToTerminalOutput(textToAppend)
                        if !newText.isEmpty {
                            print("✅ RecordingView: Appended to terminal output: \(newText.prefix(200))")
                            // Schedule auto TTS for new additions only
                            self.scheduleAutoTTS(for: newText)
                        } else {
                            // Even if newText is empty (duplicate), ensure lastTerminalOutput is set
                            // This ensures UI updates even for duplicate content
                            if self.lastTerminalOutput.isEmpty {
                                self.lastTerminalOutput = textToAppend
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
        
        // Box drawing characters
        let boxChars = ["┌", "┐", "└", "┘", "│", "─"]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check if line starts a box (contains ┌)
            if trimmed.contains("┌") && !inBox {
                inBox = true
                currentBox = []
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
                
                // Skip lines starting with progress symbols (⬢, ⬡)
                if trimmed.hasPrefix("⬢") || trimmed.hasPrefix("⬡") {
                    continue
                }
                
                // Skip lines starting with vertical bar (│) - these are code lines
                if trimmed.hasPrefix("│") {
                    continue
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
                // But be careful - only skip exact matches or very short lines
                if !lastSentCommand.isEmpty {
                    let normalizedCommand = lastSentCommand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let normalizedLine = trimmed.lowercased()
                    
                    // Only skip if:
                    // 1. Line exactly matches command
                    // 2. Line is very short and contains command (likely just echo)
                    if normalizedLine == normalizedCommand {
                        continue // Exact match - skip
                    }
                    if trimmed.count <= normalizedCommand.count + 5 && normalizedLine.contains(normalizedCommand) {
                        continue // Very short line containing command - likely echo
                    }
                    // Keep everything else - it's likely a result
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
    
    // Filter out only specific UI elements:
    // 1. Lines with box drawing characters (┌, ┐, └, ┘, │, ─) - all box content
    // 2. Lines with ANSI dim codes (semi-transparent UI text)
    // 3. Lines starting with hexagon symbols (⬢, ⬡) - status indicators (after removing ANSI codes)
    // 4. Lines containing UI phrases like "Auto ·", "/ commands", "@ files", "! shell", "review edits"
    // All other lines should be kept and appended
    private func filterIntermediateMessages(_ output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        
        var meaningfulLines: [String] = []
        
        // Box drawing characters - if line contains any of these, it's part of a box
        let boxChars: Set<Character> = ["┌", "┐", "└", "┘", "│", "─"]
        
        // Filter out only the specific cases
        for line in lines {
            // First, remove ANSI codes to check the actual visible content
            let cleanedLine = removeAnsiCodes(from: line)
            let trimmed = cleanedLine.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            if trimmed.isEmpty {
                continue
            }
            
            // 1. Skip lines with box drawing characters - these are box borders or content
            // Check if line contains any box character
            if trimmed.contains(where: { boxChars.contains($0) }) {
                continue
            }
            
            // 2. Skip lines with ANSI dim codes (semi-transparent UI text)
            // ANSI dim codes: ESC[2m or ESC[2 followed by other codes
            // Also check for dim codes in various formats: [2m, [2;...m, etc.
            if line.contains("\u{001B}[2") || 
               line.range(of: #"\x1b\[2[0-9;]*m"#, options: .regularExpression) != nil {
                continue
            }
            
            // 3. Skip lines starting with hexagon symbols (⬢, ⬡) - status indicators
            // Check the cleaned line (after removing ANSI codes) to see if it starts with ⬢ or ⬡
            if trimmed.hasPrefix("⬢") || trimmed.hasPrefix("⬡") {
                continue
            }
            
            // 4. Skip UI status lines (check cleaned text after removing ANSI codes)
            // These are semi-transparent UI elements that should be filtered
            // Check for partial matches to catch variations like "Auto · 3.7%"
            let uiPhrases = [
                "Auto",
                "/ commands",
                "@ files",
                "! shell",
                "review edits",
                "add a follow-up",
                "follow-up",
                "ctrl+r to"
            ]
            
            var shouldSkip = false
            for phrase in uiPhrases {
                if trimmed.contains(phrase) {
                    shouldSkip = true
                    break
                }
            }
            
            if shouldSkip {
                continue
            }
            
            // 5. Skip lines that are just status indicators (like "Generating", "Reading", "Editing")
            // These are progress indicators that should be filtered
            let progressIndicators = ["Generating", "Reading", "Editing"]
            let lowerTrimmed = trimmed.lowercased()
            for indicator in progressIndicators {
                if lowerTrimmed.contains(indicator.lowercased()) && trimmed.count < 50 {
                    // Short line containing progress indicator - likely a status line
                    shouldSkip = true
                    break
                }
            }
            
            if shouldSkip {
                continue
            }
            
            // Keep all other lines - they are normal content that should be displayed
            meaningfulLines.append(line)
        }
        
        let result = meaningfulLines.joined(separator: "\n")
        
        // Debug logging
        if !result.isEmpty && result != output {
            print("🔍 filterIntermediateMessages: filtered from \(output.count) to \(result.count) chars")
        }
        
        return result
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
    
    // Append new text to terminal output (accumulate between voice inputs)
    private func appendToTerminalOutput(_ newText: String) -> String {
        let trimmedNew = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNew.isEmpty {
            return ""
        }
        
        // Since we're already in Task { @MainActor in }, we can update directly
        // If lastTerminalOutput is empty, just set it
        if self.lastTerminalOutput.isEmpty {
            self.lastTerminalOutput = trimmedNew
            return trimmedNew
        }
        
        // Check if this is new text (not already in output)
        let currentOutput = self.lastTerminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // More lenient check - only skip if the exact same text is at the end
        if currentOutput.hasSuffix(trimmedNew) && currentOutput.count == trimmedNew.count {
            // Exact duplicate, skip
            return ""
        }
        
        // Append new text with separator
        let separator = currentOutput.hasSuffix(".") || currentOutput.hasSuffix("!") || currentOutput.hasSuffix("?") 
            ? " " 
            : "\n\n"
        let appended = currentOutput + separator + trimmedNew
        
        // Limit total output to prevent memory issues (keep last 5000 characters)
        let finalOutput = appended.count > 5000 
            ? String(appended.suffix(5000))
            : appended
        
        self.lastTerminalOutput = finalOutput
        
        // Return only the new part for TTS
        return trimmedNew
    }
    
    // Schedule auto TTS with new logic:
    // 1. Accumulate all messages
    // 2. Wait 5 seconds without new messages (command completion)
    // 3. Play all accumulated messages at 1.5x speed
    // 4. If new message arrives during playback, add it to queue
    private func scheduleAutoTTS(for text: String) {
        // Cancel previous timer
        ttsTimer?.invalidate()
        ttsTimer = nil
        
        // Skip if text is empty or too short
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count < 3 {
            return
        }
        
        // Use full accumulated output
        let fullOutput = lastTerminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if fullOutput.isEmpty {
            return
        }
        
        // Update accumulated TTS text with full output
        accumulatedForTTS = fullOutput
        
        // If already playing, add new content to queue for later
        if audioPlayer.isPlaying {
            // Find new content that hasn't been spoken yet
            let newContent = extractNewContent(from: fullOutput, after: lastTTSOutput)
            if !newContent.isEmpty {
                let cleaned = cleanTerminalOutputForTTS(newContent)
                if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Add to queue if not already there
                    if !ttsQueue.contains(cleaned) {
                        ttsQueue.append(cleaned)
                    }
                }
            }
            return
        }
        
        // Not playing - wait 5 seconds for command completion
        lastOutputSnapshot = fullOutput
        let threshold: TimeInterval = 5.0 // 5 seconds
        
        ttsTimer = Timer.scheduledTimer(withTimeInterval: threshold, repeats: false) { [self] _ in
            // Check if output hasn't changed (command completed)
            let currentOutput = self.lastTerminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentOutput == self.lastOutputSnapshot && !currentOutput.isEmpty {
                // Command completed - play all accumulated messages
                Task { @MainActor in
                    await self.playAccumulatedTTS()
                }
            }
        }
    }
    
    // Extract new content that hasn't been spoken yet
    private func extractNewContent(from fullOutput: String, after spokenOutput: String) -> String {
        if spokenOutput.isEmpty {
            return fullOutput
        }
        
        // Find position of spoken output in full output
        if let range = fullOutput.range(of: spokenOutput) {
            let newStart = range.upperBound
            return String(fullOutput[newStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // If not found, return everything (fallback)
        return fullOutput
    }
    
    // Play all accumulated TTS messages at 1.5x speed
    private func playAccumulatedTTS() async {
        // Skip if already playing
        if audioPlayer.isPlaying {
            return
        }
        
        // Get accumulated text
        let accumulated = accumulatedForTTS.trimmingCharacters(in: .whitespacesAndNewlines)
        if accumulated.isEmpty {
            return
        }
        
        // Clean text for TTS
        let cleanedText = cleanTerminalOutputForTTS(accumulated)
        if cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        
        // Check for ephemeral keys
        guard let keys = settingsManager.ephemeralKeys else {
            print("⚠️ No ephemeral keys for TTS")
            return
        }
        
        print("🔊 Generating TTS for accumulated output (length: \(cleanedText.count)) at 1.5x speed...")
        
        do {
            let ttsHandler = LocalTTSHandler(apiKey: keys.openai)
            let voice = selectVoiceForLanguage(settingsManager.transcriptionLanguage)
            
            // Use 1.5x speed
            let audioData = try await ttsHandler.synthesize(text: cleanedText, voice: voice, speed: 1.5)
            
            // Update last spoken text
            await MainActor.run {
                self.lastTTSOutput = accumulated
            }
            
            // Play audio on main thread
            await MainActor.run {
                do {
                    try self.audioPlayer.play(audioData: audioData)
                    print("🔊 TTS playback started at 1.5x speed")
                } catch {
                    print("❌ Failed to play TTS audio: \(error)")
                }
            }
        } catch {
            print("❌ TTS generation error: \(error)")
        }
    }
    
    
    // Process queue after playback finishes
    private func processQueueAfterPlayback() async {
        // Wait a bit for audio session to settle
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Process queue if there are items
        while !ttsQueue.isEmpty {
            let queuedText = ttsQueue.removeFirst()
            
            // Generate and play TTS for queued text
            await generateAndPlayTTS(for: queuedText, isFromQueue: true)
            
            // Wait for playback to finish
            while audioPlayer.isPlaying {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }
    
    // Generate TTS audio and play it
    private func generateAndPlayTTS(for text: String, isFromQueue: Bool = false) async {
        // Skip if already playing (unless called from queue)
        if audioPlayer.isPlaying && !isFromQueue {
            return
        }
        
        // Skip if already spoken this text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == lastTTSOutput {
            return
        }
        
        // Check for ephemeral keys
        guard let keys = settingsManager.ephemeralKeys else {
            print("⚠️ No ephemeral keys for TTS")
            return
        }
        
        // Clean text for TTS (remove ANSI codes, etc.)
        let cleanedText = cleanTerminalOutputForTTS(trimmed)
        
        // Skip if cleaned text is empty
        if cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        
        print("🔊 Generating TTS (length: \(cleanedText.count))...")
        
        do {
            let ttsHandler = LocalTTSHandler(apiKey: keys.openai)
            let voice = selectVoiceForLanguage(settingsManager.transcriptionLanguage)
            
            // Use 1.5x speed for all TTS
            let audioData = try await ttsHandler.synthesize(text: cleanedText, voice: voice, speed: 1.5)
            
            // Update last spoken text
            await MainActor.run {
                self.lastTTSOutput = trimmed
            }
            
            // Play audio on main thread
            await MainActor.run {
                do {
                    try self.audioPlayer.play(audioData: audioData)
                    print("🔊 TTS playback started at 1.5x speed")
                    
                    // If there's a queue, process it after playback finishes
                    if !self.ttsQueue.isEmpty {
                        Task { @MainActor in
                            // Wait for playback to finish, then process queue
                            while self.audioPlayer.isPlaying {
                                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                            }
                            await self.processQueueAfterPlayback()
                        }
                    }
                } catch {
                    print("❌ Failed to play TTS audio: \(error)")
                }
            }
        } catch {
            print("❌ TTS generation error: \(error)")
        }
    }
    
    // Select voice based on language from settings
    private func selectVoiceForLanguage(_ language: TranscriptionLanguage) -> String {
        switch language {
        case .russian:
            return "nova" // Good for Russian
        case .english:
            return "alloy" // Good for English
        case .georgian:
            return "echo" // Neutral voice
        case .auto:
            return "alloy" // Default neutral voice
        }
    }
    
    // Clean terminal output for TTS (remove ANSI sequences, keep text readable)
    private func cleanTerminalOutputForTTS(_ output: String) -> String {
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



