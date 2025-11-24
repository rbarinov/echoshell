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
    @StateObject private var recordingStreamClient = RecordingStreamClient()
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showSessionPicker = false
    @State private var showModeTooltip: CommandMode? = nil
    // Use settingsManager.lastTerminalOutput instead of local state to persist across navigation
    @State private var accumulatedOutput: String = "" // Accumulate output chunks
    @State private var lastSentCommand: String = "" // Track last sent command to filter it from output
    @State private var ttsTimer: Timer? = nil // Timer for auto TTS after 5 seconds of silence
    @State private var lastTTSOutput: String = "" // Track what was last spoken to avoid duplicates
    @State private var accumulatedForTTS: String = "" // Accumulated text for TTS (all messages)
    @StateObject private var audioPlayer = AudioPlayer() // Audio player for TTS
    @State private var ttsQueue: [String] = [] // Queue for TTS messages
    @State private var lastOutputSnapshot: String = "" // Snapshot of output when timer started
    @State private var recordingStreamSessionId: String?
    
    // Centralized state reset function
    private func resetState() {
        // Don't clear lastTerminalOutput - keep it for history
        // settingsManager.lastTerminalOutput is preserved
        accumulatedOutput = ""
        lastSentCommand = ""
        lastTTSOutput = ""
        accumulatedForTTS = ""
        lastOutputSnapshot = ""
        ttsQueue = []
        ttsTimer?.invalidate()
        ttsTimer = nil
    }
    
    // Stop all TTS tasks and clear output
    private func stopAllTTSAndClearOutput() {
        print("🛑 stopAllTTSAndClearOutput: Stopping all TTS tasks and clearing output")
        
        // Stop audio playback if playing
        if audioPlayer.isPlaying {
            print("🛑 Stopping audio playback")
            audioPlayer.stop()
        }
        
        // Cancel TTS timer
        ttsTimer?.invalidate()
        ttsTimer = nil
        
        // Clear all TTS state
        ttsQueue = []
        accumulatedForTTS = ""
        lastTTSOutput = ""
        lastOutputSnapshot = ""
        
        // Don't clear lastTerminalOutput - keep it for history
        // settingsManager.lastTerminalOutput is preserved
        accumulatedOutput = ""
        
        print("🛑 All TTS tasks stopped and output cleared")
    }
    
    // Get selected session
    private var selectedSession: TerminalSession? {
        guard let sessionId = settingsManager.selectedSessionId else { return nil }
        return terminalViewModel.sessions.first { $0.id == sessionId }
    }
    
    // Check if selected session is Cursor Agent terminal
    private var isCursorAgentTerminal: Bool {
        return selectedSession?.terminalType == .cursorAgent
    }
    
    // Filter sessions for direct mode (only cursor_agent terminals)
    private var availableSessionsForDirectMode: [TerminalSession] {
        return terminalViewModel.sessions.filter { $0.terminalType == .cursorAgent }
    }
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        } else {
            // Clear previous output when starting new recording
            Task { @MainActor in
                self.resetState()
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
                    if settingsManager.commandMode == .direct {
                        // In direct mode, only show cursor_agent terminals
                        if !availableSessionsForDirectMode.isEmpty {
                    sessionSelectorView
                        } else {
                            // No cursor_agent terminals, show create button
                            createCursorAgentTerminalView
                        }
                    } else {
                        // In agent mode, show all terminals
                        sessionSelectorView
                    }
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
            } else {
                // Get sessions based on mode
                let validSessions = settingsManager.commandMode == .direct 
                    ? availableSessionsForDirectMode 
                    : terminalViewModel.sessions
                
                if validSessions.isEmpty {
                Button(action: {
                    Task {
                        if let config = settingsManager.laptopConfig {
                            if terminalViewModel.apiClient == nil {
                                terminalViewModel.apiClient = APIClient(config: config)
                            }
                                let terminalType: TerminalType = settingsManager.commandMode == .direct ? .cursorAgent : .regular
                                let _ = try? await terminalViewModel.apiClient?.createSession(terminalType: terminalType)
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
                                HStack {
                                    if session.terminalType == .cursorAgent {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 10))
                                    }
                                    Text(session.name ?? session.id)
                                .tag(session.id)
                                }
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
                        let validSessions = settingsManager.commandMode == .direct 
                            ? newSessions.filter { $0.terminalType == .cursorAgent }
                            : newSessions
                        
                    if let currentSelected = settingsManager.selectedSessionId,
                           !validSessions.contains(where: { $0.id == currentSelected }) {
                            // Selected session no longer exists or is invalid for current mode, select first available
                            settingsManager.selectedSessionId = validSessions.first?.id
                        } else if settingsManager.selectedSessionId == nil && !validSessions.isEmpty {
                        // No session selected, select first available
                            settingsManager.selectedSessionId = validSessions.first?.id
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }
    
    private var createCursorAgentTerminalView: some View {
        Button(action: {
            Task {
                if let config = settingsManager.laptopConfig {
                    if terminalViewModel.apiClient == nil {
                        terminalViewModel.apiClient = APIClient(config: config)
                    }
                    let _ = try? await terminalViewModel.apiClient?.createSession(terminalType: .cursorAgent)
                    await terminalViewModel.refreshSessions(config: config)
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                Text("Create Cursor Agent Terminal")
                    .font(.subheadline)
            }
            .foregroundColor(.blue)
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
        .disabled(audioRecorder.isTranscribing || settingsManager.laptopConfig == nil || 
                 (settingsManager.commandMode == .direct && !isCursorAgentTerminal))
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
            } else if settingsManager.commandMode == .direct && !isCursorAgentTerminal {
                Text("Select a Cursor Agent terminal")
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
        // In direct mode: show when cursor_agent terminal is selected
        // In agent mode: show when there's recognized text
        Group {
            let shouldShow = settingsManager.commandMode == .direct 
                ? isCursorAgentTerminal
                : !audioRecorder.recognizedText.isEmpty
            
            if shouldShow && !audioRecorder.isTranscribing {
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
                    let displayText = settingsManager.commandMode == .direct 
                        ? (settingsManager.lastTerminalOutput.isEmpty ? "Waiting for command output..." : settingsManager.lastTerminalOutput)
                        : audioRecorder.recognizedText
                    
                    Text(displayText)
                        .onAppear {
                            print("📱 resultDisplayView: Displaying text (length: \(displayText.count), mode: \(settingsManager.commandMode))")
                        }
                        .onChange(of: settingsManager.lastTerminalOutput) { oldValue, newValue in
                            print("📱 resultDisplayView: lastTerminalOutput changed (old: \(oldValue.count), new: \(newValue.count))")
                        }
                        .onChange(of: audioRecorder.recognizedText) { oldValue, newValue in
                            print("📱 resultDisplayView: recognizedText changed (old: \(oldValue.count), new: \(newValue.count), mode: \(settingsManager.commandMode))")
                        }
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
                        connectToRecordingStream(config: config, sessionId: sessionId)
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
                        connectToRecordingStream(config: config, sessionId: sessionId)
                    }
                }
            } else {
                wsClient.disconnect()
                recordingStreamClient.disconnect()
            }
        }
        .onChange(of: settingsManager.selectedSessionId) { oldValue, newValue in
            // Reconnect WebSocket when session changes
            if let config = settingsManager.laptopConfig, let sessionId = newValue {
                connectToTerminalStream(config: config, sessionId: sessionId)
                connectToRecordingStream(config: config, sessionId: sessionId)
            }
        }
        .onChange(of: settingsManager.commandMode) { oldValue, newValue in
            // Reconnect WebSocket when mode changes to track output in direct mode
            if newValue == .direct, let config = settingsManager.laptopConfig, let sessionId = settingsManager.selectedSessionId {
                // Only connect if selected session is cursor_agent
                if terminalViewModel.sessions.first(where: { $0.id == sessionId })?.terminalType == .cursorAgent {
                connectToTerminalStream(config: config, sessionId: sessionId)
                    connectToRecordingStream(config: config, sessionId: sessionId)
                }
            } else if newValue == .agent {
                recordingStreamClient.disconnect()
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
                        // Don't clear lastTerminalOutput when switching modes - keep history
                        // settingsManager.lastTerminalOutput is preserved
                    self.accumulatedOutput = "" // Reset accumulated output
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CommandSentToTerminal"))) { notification in
            // Clear previous output when new command is sent in direct mode
            if settingsManager.commandMode == .direct && isCursorAgentTerminal {
                // Ensure updates happen on main thread
                Task { @MainActor in
                    print("📤 Command sent to cursor_agent terminal")
                    
                    // Cancel any pending TTS
                    self.ttsTimer?.invalidate()
                    self.ttsTimer = nil
                    self.lastTTSOutput = ""
                    self.accumulatedForTTS = ""
                    self.lastOutputSnapshot = ""
                    self.ttsQueue = []
                    
                    // Don't clear lastTerminalOutput - keep accumulated output between commands
                    self.accumulatedOutput = "" // Reset accumulated output
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
                            // Wait longer for connection to establish (increased from 0.2 to 0.5)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                // Retry up to 3 times if not connected
                                var retryCount = 0
                                let maxRetries = 3
                                
                                func trySend() {
                                if self.wsClient.isConnected {
                                    // Send command as a single string with \r at the end
                                    // This matches what xterm.js sends when user presses Enter
                                    self.sendCommandToTerminal(command, to: self.wsClient)
                                    print("📤 Sent command via WebSocket input: \(command)")
                                    } else if retryCount < maxRetries {
                                        retryCount += 1
                                        print("⚠️ WebSocket not connected, retrying (\(retryCount)/\(maxRetries))...")
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            trySend()
                                        }
                                } else {
                                        print("❌ WebSocket not connected after \(maxRetries) retries, command not sent")
                                }
                                }
                                
                                trySend()
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
                print("🎤 Transcription started")
                
                // Don't clear lastTerminalOutput - keep it for history
                // settingsManager.lastTerminalOutput is preserved
                self.accumulatedOutput = ""
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TTSPlaybackFinished"))) { _ in
            // When TTS playback finishes, process queue if there are items
            print("🔊 TTS playback finished, checking queue...")
            Task { @MainActor in
                await self.processQueueAfterPlayback()
            }
        }
        .onDisappear {
            // Stop all TTS and audio playback when leaving the page
            print("📱 RecordingView: onDisappear - stopping TTS and audio")
            recordingStreamClient.disconnect()
            recordingStreamSessionId = nil
            Task { @MainActor in
                // Stop audio playback if playing
                if self.audioPlayer.isPlaying {
                    print("🛑 Stopping audio playback on disappear")
                    self.audioPlayer.stop()
                }
                
                // Cancel TTS timer
                self.ttsTimer?.invalidate()
                self.ttsTimer = nil
                
                // Clear TTS queue
                self.ttsQueue = []
                self.accumulatedForTTS = ""
                self.lastTTSOutput = ""
                self.lastOutputSnapshot = ""
                
                // Don't clear lastTerminalOutput - keep it for history
                // settingsManager.lastTerminalOutput is preserved
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
    
    // Maintain terminal connection for sending commands, but ignore raw output (clean output comes from backend)
    private func connectToTerminalStream(config: TunnelConfig, sessionId: String) {
        wsClient.disconnect()
        guard let session = terminalViewModel.sessions.first(where: { $0.id == sessionId }) else { return }
        guard session.terminalType == .cursorAgent else { return }

        wsClient.connect(config: config, sessionId: sessionId) { _ in
            // Intentionally ignore raw output for recording view - clean output is streamed separately
        }
    }
    
    // Connect to the backend-provided recording stream that already contains cleaned output
    private func connectToRecordingStream(config: TunnelConfig, sessionId: String) {
        guard settingsManager.commandMode == .direct else {
            recordingStreamClient.disconnect()
            recordingStreamSessionId = nil
                                return
                            }
        
        guard let session = terminalViewModel.sessions.first(where: { $0.id == sessionId }),
              session.terminalType == .cursorAgent else {
            recordingStreamClient.disconnect()
            recordingStreamSessionId = nil
                        return
                    }
                    
        if recordingStreamSessionId == sessionId && recordingStreamClient.isConnected {
                        return
                    }
        recordingStreamSessionId = sessionId
        
        recordingStreamClient.connect(config: config, sessionId: sessionId) { message in
            Task { @MainActor in
                self.settingsManager.lastTerminalOutput = message.text
                self.scheduleAutoTTS(for: message.text)
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
                // BUT: if line contains text AFTER box characters, it might be a result
                let hasBoxChars = boxChars.contains(where: { trimmed.contains($0) })
                if hasBoxChars {
                    // Check if there's meaningful text after box characters
                    var textAfterBox = trimmed
                    for boxChar in boxChars {
                        textAfterBox = textAfterBox.replacingOccurrences(of: boxChar, with: "")
                    }
                    textAfterBox = textAfterBox.trimmingCharacters(in: .whitespaces)
                    if textAfterBox.count < 3 {
                        continue // Only box characters, skip
                    }
                    // Has text after box chars, might be a result - continue processing
                }
                
                // Remove dim text segments first (semi-transparent UI text)
                // This removes ALL dim text content, regardless of position or model name
                let withoutDim = removeDimText(from: line)
                
                // Check if line had dim text - if it did and after removal it's empty or very short, skip it
                if line.contains("\u{001B}[2") || line.contains("\u{001B}[2m") {
                    let textWithoutAnsi = removeAnsiCodes(from: withoutDim)
                    let trimmedNoAnsi = textWithoutAnsi.trimmingCharacters(in: .whitespaces)
                    
                    // If after removing dim text the line is empty or very short, it was mostly dim text - skip it
                    if trimmedNoAnsi.isEmpty || trimmedNoAnsi.count < 3 {
                                continue
                            }
                        }
                
                // Skip UI status lines with model name and percentage (after removing dim text)
                // Universal check for pattern "· X%" (works for Auto, Composer 1, Composer 2, etc.)
                let uiStatusPattern = #"·\s*\d+\.?\d*%"#
                if trimmed.range(of: uiStatusPattern, options: .regularExpression) != nil {
                    // This is a UI status line with model name and percentage - skip it
                    continue
                }
                
                // Skip other UI status lines
                if trimmed.contains("/ commands") || trimmed.contains("@ files") {
                    continue
                }
                if trimmed.contains("review edits") {
                    continue
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
                // Examples: "3 + 3 = 6", "Один плюс один равно два (1 + 1 = 2).", etc.
                // Use cleaned version (without dim text and ANSI codes) - we want ONLY normal text
                let textWithoutAnsi = removeAnsiCodes(from: withoutDim)
                let cleanedLine = textWithoutAnsi.trimmingCharacters(in: .whitespaces)
                if !cleanedLine.isEmpty && cleanedLine.count >= 3 {
                    resultLines.append(cleanedLine)
                }
            }
        }
        
        // Priority: code boxes first, then result lines
        // But also include result lines that appear after boxes (like Cursor Agent responses)
        var allResults: [String] = []
        
        // Add code boxes
        allResults.append(contentsOf: codeBoxes)
        
        // Add result lines (these often appear after boxes in Cursor Agent)
        // Filter out duplicates, very short lines, and UI status lines
        let meaningfulResultLines = resultLines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip very short lines
            if trimmed.count < 5 || trimmed.isEmpty {
                return false
            }
            
            // Skip UI status lines with model name and percentage
            let uiStatusPattern = #"·\s*\d+\.?\d*%"#
            if trimmed.range(of: uiStatusPattern, options: .regularExpression) != nil {
                return false
            }
            
            return true
        }
        allResults.append(contentsOf: meaningfulResultLines)
        
        if !allResults.isEmpty {
            // Return all results joined, prioritizing the most recent
            // For Cursor Agent, the result is usually the last meaningful line
            return allResults.joined(separator: "\n\n")
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
            // First, remove dim text segments (semi-transparent UI text)
            // This removes ALL dim text content, regardless of position or model name
            // Dim text is semi-transparent UI text - we want to show ONLY normal text
            let withoutDim = removeDimText(from: line)
            
            // Then remove remaining ANSI codes to check the actual visible content
            let cleanedLine = removeAnsiCodes(from: withoutDim)
            let trimmed = cleanedLine.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines (after removing dim text and ANSI codes)
            if trimmed.isEmpty {
                continue
            }
            
            // 1. Skip lines with box drawing characters - these are box borders or content
            // Check if line contains any box character
            if trimmed.contains(where: { boxChars.contains($0) }) {
                continue
            }
            
            // 3. Skip UI status lines with model name and percentage (after removing dim text)
            // Universal check for pattern "· X%" (works for Auto, Composer 1, Composer 2, etc.)
            let uiStatusPattern = #"·\s*\d+\.?\d*%"#
            if trimmed.range(of: uiStatusPattern, options: .regularExpression) != nil {
                // This is a UI status line with model name and percentage - skip it
                continue
            }
            
            // 4. Skip lines starting with hexagon symbols (⬢, ⬡) - status indicators
            // Check the cleaned line (after removing ANSI codes) to see if it starts with ⬢ or ⬡
            if trimmed.hasPrefix("⬢") || trimmed.hasPrefix("⬡") {
                continue
            }
            
            // 5. Skip other UI status lines (check cleaned text after removing ANSI codes)
            // These are semi-transparent UI elements that should be filtered
            let uiPhrases = [
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
            // Use cleanedLine (without dim text and ANSI codes) instead of original line
            meaningfulLines.append(cleanedLine)
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
    
    // Helper function to remove all dim text segments (semi-transparent UI text)
    // Dim text starts with ESC[2m (or ESC[2;...m) and ends with ESC[0m (or other reset codes)
    // This removes ALL dim text content, not just specific patterns
    private func removeDimText(from text: String) -> String {
        var result = text
        
        // Pattern: Remove dim text segments: ESC[2m ... ESC[0m (or ESC[22m, ESC[27m, ESC[m, etc.)
        // This matches: ESC[2m or ESC[2;...m followed by any content until reset code
        // Reset codes: ESC[0m, ESC[22m (normal intensity), ESC[27m (not inverse), ESC[m (default)
        // The pattern uses non-greedy matching to find the first reset code after dim start
        let dimPattern = #"\x1b\[2[0-9;]*m.*?\x1b\[([0-9;]*m|m)"#
        
        // Use while loop to remove all dim segments (they can be multiple)
        var previousLength = result.count
        var iterations = 0
        repeat {
            previousLength = result.count
            if let regex = try? NSRegularExpression(pattern: dimPattern, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
            iterations += 1
        } while result.count < previousLength && iterations < 100 // Safety limit
        
        // Also handle cases where dim text doesn't have explicit reset (continues to end of line/string)
        // Pattern: ESC[2m followed by everything until end of string or newline
        let dimToEndPattern = #"\x1b\[2[0-9;]*m[^\n]*"#
        if let endRegex = try? NSRegularExpression(pattern: dimToEndPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = endRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        // Also remove standalone dim codes (ESC[2m without matching reset) - these might be at end of line
        let standaloneDimPattern = #"\x1b\[2[0-9;]*m"#
        if let dimRegex = try? NSRegularExpression(pattern: standaloneDimPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = dimRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        return result
    }
    
    // Append new text to terminal output (accumulate between voice inputs)
    private func appendToTerminalOutput(_ newText: String) -> String {
        let trimmedNew = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNew.isEmpty {
            return ""
        }
        
        // Since we're already in Task { @MainActor in }, we can update directly
        // If lastTerminalOutput is empty, just set it
        if self.settingsManager.lastTerminalOutput.isEmpty {
            self.settingsManager.lastTerminalOutput = trimmedNew
            print("📝 appendToTerminalOutput: Set initial output (\(trimmedNew.count) chars)")
            return trimmedNew
        }
        
        // Check if this is new text (not already in output)
        let currentOutput = self.settingsManager.lastTerminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Only skip if the entire current output is exactly equal to new text (complete duplicate)
        if currentOutput == trimmedNew {
            print("📝 appendToTerminalOutput: Skipping exact duplicate")
            return ""
        }
        
        // Check if new text is already at the end of current output
        // Only skip if it's a very large portion (more than 90% of current output)
        // This is more conservative to avoid filtering legitimate updates
        if currentOutput.hasSuffix(trimmedNew) {
            let suffixLength = trimmedNew.count
            let currentLength = currentOutput.count
            
            // Only skip if new text is more than 90% of current output (very likely a duplicate)
            if currentLength > 0 && suffixLength > Int(Double(currentLength) * 0.9) {
                print("📝 appendToTerminalOutput: Skipping very large duplicate suffix (\(suffixLength)/\(currentLength) chars)")
                return ""
            }
        }
        
        // Check if new text is already contained in current output (not just at the end)
        // Only skip if it's an extremely large portion (more than 95% of current output)
        // This is very conservative to avoid false positives
        if currentOutput.contains(trimmedNew) {
            let newLength = trimmedNew.count
            let currentLength = currentOutput.count
            
            // Only skip if new text is more than 95% of current output (almost certainly a duplicate)
            if currentLength > 0 && newLength > Int(Double(currentLength) * 0.95) {
                print("📝 appendToTerminalOutput: Skipping extremely large duplicate (\(newLength)/\(currentLength) chars)")
                return ""
            }
        }
        
        // Append new text with separator
        let separator = currentOutput.hasSuffix(".") || currentOutput.hasSuffix("!") || currentOutput.hasSuffix("?") 
            ? " " 
            : "\n\n"
        let appended = currentOutput + separator + trimmedNew
        
        // Limit total output to prevent memory issues (keep last 10000 characters)
        let finalOutput = appended.count > 10000 
            ? String(appended.suffix(10000))
            : appended
        
        self.settingsManager.lastTerminalOutput = finalOutput
        print("📝 appendToTerminalOutput: Appended new text (\(trimmedNew.count) chars), total now: \(finalOutput.count) chars")
        
        // Return only the new part for TTS
        return trimmedNew
    }
    
    // Schedule auto TTS with reactive logic:
    // 1. Always update accumulated text and set timer (even if playing)
    // 2. Wait 5 seconds without new messages (command completion)
    // 3. If playing: add new content to queue after threshold
    // 4. If not playing: start playback after threshold
    // 5. After playback finishes, process queue and check for more new content
    private func scheduleAutoTTS(for text: String) {
        // Use full accumulated output (not just the passed text)
        let fullOutput = settingsManager.lastTerminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if fullOutput.isEmpty {
            print("🔇 scheduleAutoTTS: Skipped - no output to speak")
            return
        }
        
        // Check if we're in a cursor_agent terminal
        guard isCursorAgentTerminal else {
            print("⚠️ scheduleAutoTTS: Not in cursor_agent terminal, skipping TTS")
            return
        }
        
            print("🔊 scheduleAutoTTS: Scheduling TTS for output (\(fullOutput.count) chars)")
        
        // Cancel previous timer
        ttsTimer?.invalidate()
        ttsTimer = nil
        
        // Always update accumulated TTS text with full output
        accumulatedForTTS = fullOutput
        
        // Always set timer, regardless of playback state
        lastOutputSnapshot = fullOutput
        let threshold: TimeInterval = 5.0 // 5 seconds
        
        print("🔊 scheduleAutoTTS: Timer set for \(threshold) seconds")
        
        ttsTimer = Timer.scheduledTimer(withTimeInterval: threshold, repeats: false) { [self] _ in
            // Check if output hasn't changed (command completed)
            let currentOutput = self.settingsManager.lastTerminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            print("🔊 scheduleAutoTTS: Timer fired, checking output (current: \(currentOutput.count), snapshot: \(self.lastOutputSnapshot.count))")
            
            if currentOutput == self.lastOutputSnapshot && !currentOutput.isEmpty {
                print("🔊 scheduleAutoTTS: Output stable, starting TTS")
                // Command completed - check if we're playing
                if self.audioPlayer.isPlaying {
                    // Playing - extract new content and add to queue
                    let newContent = self.extractNewContent(from: currentOutput, after: self.lastTTSOutput)
                    if !newContent.isEmpty {
                        let cleaned = self.cleanTerminalOutputForTTS(newContent)
                        if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // Add to queue if not already there
                            if !self.ttsQueue.contains(cleaned) {
                                self.ttsQueue.append(cleaned)
                                print("🔊 Added new content to TTS queue (length: \(cleaned.count))")
                            }
                        }
                    }
                } else {
                    // Not playing - start playback
                    // Check if we're still in cursor_agent terminal
                    guard self.isCursorAgentTerminal else {
                        print("⚠️ scheduleAutoTTS: No longer in cursor_agent terminal, skipping playback")
                        return
                    }
                    print("🔊 scheduleAutoTTS: Starting playback")
                    Task { @MainActor in
                        await self.playAccumulatedTTS()
                    }
                }
            } else {
                print("🔊 scheduleAutoTTS: Output changed, rescheduling")
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
    
    // Play all accumulated TTS messages at configured speed
    private func playAccumulatedTTS() async {
        // Check if we have output to play
        let accumulated = accumulatedForTTS.trimmingCharacters(in: .whitespacesAndNewlines)
        if accumulated.isEmpty {
            print("🔇 playAccumulatedTTS: Skipped - no accumulated text")
            return
        }
        
        // Check if we're in a cursor_agent terminal
        guard isCursorAgentTerminal else {
            print("⚠️ playAccumulatedTTS: Not in cursor_agent terminal, skipping")
            return
        }
        
        // Skip if already playing
        if audioPlayer.isPlaying {
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
        
        print("🔊 Generating TTS for accumulated output (length: \(cleanedText.count)) at \(settingsManager.ttsSpeed)x speed...")
        
        do {
            let ttsHandler = LocalTTSHandler(apiKey: keys.openai)
            let voice = selectVoiceForLanguage(settingsManager.transcriptionLanguage)
            
            // Use speed from settings
            let audioData = try await ttsHandler.synthesize(text: cleanedText, voice: voice, speed: settingsManager.ttsSpeed)
            
            // Update last spoken text
            await MainActor.run {
                self.lastTTSOutput = accumulated
            }
            
            // Play audio on main thread
            await MainActor.run {
                do {
                    try self.audioPlayer.play(audioData: audioData)
                    print("🔊 TTS playback started at \(self.settingsManager.ttsSpeed)x speed")
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
            // Check if we're still in cursor_agent terminal
            guard isCursorAgentTerminal else {
                print("🔇 processQueueAfterPlayback: No longer in cursor_agent terminal, clearing queue and stopping playback")
                await MainActor.run {
                    self.ttsQueue = []
                    if self.audioPlayer.isPlaying {
                        self.audioPlayer.stop()
                    }
                }
                return
            }
            
            let queuedText = ttsQueue.removeFirst()
            
            // Generate and play TTS for queued text
            await generateAndPlayTTS(for: queuedText, isFromQueue: true)
            
            // Wait for playback to finish
            while audioPlayer.isPlaying {
                // Check again if we're still in cursor_agent terminal
                if !isCursorAgentTerminal {
                    print("🔇 processQueueAfterPlayback: No longer in cursor_agent terminal during playback, stopping")
                    await MainActor.run {
                        self.ttsQueue = []
                        if self.audioPlayer.isPlaying {
                            self.audioPlayer.stop()
                        }
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        
        // After queue is processed, check if there's more new content
        // (new messages might have arrived during queue processing)
        let currentOutput = settingsManager.lastTerminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let newContent = extractNewContent(from: currentOutput, after: lastTTSOutput)
        if !newContent.isEmpty {
            // New content arrived - set timer again to wait for completion
            print("🔊 New content detected after queue processing (length: \(newContent.count)), setting timer...")
            accumulatedForTTS = currentOutput
            lastOutputSnapshot = currentOutput
            let threshold: TimeInterval = 5.0
            
            ttsTimer = Timer.scheduledTimer(withTimeInterval: threshold, repeats: false) { [self] _ in
                let finalOutput = self.settingsManager.lastTerminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if finalOutput == self.lastOutputSnapshot && !finalOutput.isEmpty {
                    let finalNewContent = self.extractNewContent(from: finalOutput, after: self.lastTTSOutput)
                    if !finalNewContent.isEmpty {
                        let cleaned = self.cleanTerminalOutputForTTS(finalNewContent)
                        if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // Start playback for new content
                            Task { @MainActor in
                                await self.generateAndPlayTTS(for: cleaned, isFromQueue: false)
                            }
                        }
                    }
                }
            }
        } else {
            print("🔊 No new content after queue processing")
        }
    }
    
    // Generate TTS audio and play it
    private func generateAndPlayTTS(for text: String, isFromQueue: Bool = false) async {
        // Check if text is valid
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            print("🔇 generateAndPlayTTS: Skipped - empty text")
            return
        }
        
        // Check if we're in a cursor_agent terminal (unless from queue, which was already validated)
        if !isFromQueue && !isCursorAgentTerminal {
            print("⚠️ generateAndPlayTTS: Not in cursor_agent terminal, skipping")
            return
        }
        
        // Skip if already playing (unless called from queue)
        if audioPlayer.isPlaying && !isFromQueue {
            return
        }
        
        // Skip if already spoken this text
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
        if cleanedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            return
        }
        
        print("🔊 Generating TTS (length: \(cleanedText.count)) at \(settingsManager.ttsSpeed)x speed...")
        
        do {
            let ttsHandler = LocalTTSHandler(apiKey: keys.openai)
            let voice = selectVoiceForLanguage(settingsManager.transcriptionLanguage)
            
            // Use speed from settings
            let audioData = try await ttsHandler.synthesize(text: cleanedText, voice: voice, speed: settingsManager.ttsSpeed)
            
            // Update last spoken text
            // For queue items, we need to track what was actually spoken
            // Since queued items are already new content, we append them to lastTTSOutput
            await MainActor.run {
                if isFromQueue && !self.lastTTSOutput.isEmpty {
                    // Append queued text to lastTTSOutput to track all spoken content
                    let separator = self.lastTTSOutput.hasSuffix(".") || self.lastTTSOutput.hasSuffix("!") || self.lastTTSOutput.hasSuffix("?") 
                        ? " " 
                        : "\n\n"
                    self.lastTTSOutput = self.lastTTSOutput + separator + trimmed
                } else {
                    // For new content (not from queue), update to current accumulated output
                    // This ensures we track all spoken content correctly
                    self.lastTTSOutput = self.accumulatedForTTS.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
            // Play audio on main thread
            await MainActor.run {
                do {
                    try self.audioPlayer.play(audioData: audioData)
                    print("🔊 TTS playback started at \(self.settingsManager.ttsSpeed)x speed")
                    
                    // Queue processing will be handled by notification observer
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



