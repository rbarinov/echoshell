//
//  RecordingView.swift
//  EchoShell
//
//  Created by Roman Barinov on 2025.11.21.
//

import SwiftUI
import AVFoundation

// Recording state enum
enum RecordingState {
    case idle
    case recording
    case transcribing
    case waitingForAgent
    case generatingTTS
    case playingTTS
    
    var description: String {
        switch self {
        case .idle:
            return "Ready to record"
        case .recording:
            return "Recording..."
        case .transcribing:
            return "Transcribing..."
        case .waitingForAgent:
            return "Waiting for agent response..."
        case .generatingTTS:
            return "Generating speech..."
        case .playingTTS:
            return "Playing response..."
        }
    }
    
    // All states use the same standard color (secondary) for consistency
    var color: Color {
        return .secondary
    }
    
    // Check if state is active (should show pulsing dot)
    var isActive: Bool {
        return self != .idle
    }
}

struct RecordingView: View {
    // Flag to indicate if this is the active tab (prevents duplicate event handling)
    let isActiveTab: Bool
    
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var terminalViewModel = TerminalViewModel()
    @StateObject private var wsClient = WebSocketClient()
    @StateObject private var recordingStreamClient = RecordingStreamClient()
    @StateObject private var laptopHealthChecker = LaptopHealthChecker()
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showSessionPicker = false
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
    @State private var lastTTSAudioData: Data? = nil // Store last TTS audio for replay
    @State private var isGeneratingTTS = false // Track TTS generation state
    @State private var pulseAnimation: Bool = false // For pulsing dot animation
    
    // Task cancellation for interrupting ongoing operations
    @State private var currentOperationTask: Task<Void, Never>? = nil
    @State private var currentOperationId: UUID? = nil
    
    // Default initializer for backward compatibility
    init(isActiveTab: Bool = true) {
        self.isActiveTab = isActiveTab
    }
    
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
    
    // Get worst connection state
    // Priority: laptop health check > WebSocket/RecordingStream (for direct mode)
    // In agent mode: only laptop health check matters
    // In direct mode: laptop health check + WebSocket/RecordingStream states
    private func getWorstConnectionState() -> ConnectionState {
        // No laptop config means no connection to backend
        guard settingsManager.laptopConfig != nil else {
            return .disconnected
        }
        
        // Get laptop health check state (real connection status)
        let laptopState = laptopHealthChecker.connectionState
        
        // In agent mode, only laptop health check matters (no WebSocket needed)
        if settingsManager.commandMode == .agent {
            return laptopState
        }
        
        // In direct mode, check both laptop health AND WebSocket/RecordingStream states
        let wsState = wsClient.connectionState
        let recordingState = recordingStreamClient.connectionState
        
        // Priority: dead > disconnected > reconnecting > connecting > connected
        // Combine laptop state with WebSocket states
        let states = [laptopState, wsState, recordingState]
        
        if states.contains(.dead) {
            return .dead
        }
        if states.contains(.disconnected) {
            return .disconnected
        }
        if states.contains(.reconnecting) {
            return .reconnecting
        }
        if states.contains(.connecting) {
            return .connecting
        }
        return .connected
    }
    
    // Handle connection state changes with user notifications
    private func handleConnectionStateChange(from oldState: ConnectionState, to newState: ConnectionState) {
        // Only show notifications for significant state changes
        if oldState == newState {
            return
        }
        
        switch newState {
        case .dead:
            showConnectionNotification(title: "Connection Lost", message: "Lost connection to server. Attempting to reconnect...")
        case .disconnected:
            if oldState != .dead {
                showConnectionNotification(title: "Disconnected", message: "Connection to server closed.")
            }
        case .reconnecting:
            showConnectionNotification(title: "Reconnecting", message: "Attempting to reconnect to server...")
        case .connected:
            if oldState == .reconnecting || oldState == .dead {
                showConnectionNotification(title: "Connected", message: "Successfully connected to server.")
            }
        case .connecting:
            // Don't show notification for initial connection
            break
        }
    }
    
    private func showConnectionNotification(title: String, message: String) {
        // Use a simple alert-style notification
        // In a production app, you might want to use a more sophisticated notification system
        print("🔔 Connection Status: \(title) - \(message)")
        
        // You can also use a banner or toast notification here
        // For now, we'll just log it. The visual indicator will show the state.
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

    private var isHeadlessTerminal: Bool {
        guard let type = selectedSession?.terminalType else { return false }
        return type.isHeadless
    }
    
    // Filter sessions for direct mode (only cursor_agent terminals)
    private var availableSessionsForDirectMode: [TerminalSession] {
        return terminalViewModel.sessions.filter { $0.terminalType.isHeadless }
    }
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        } else {
            // Cancel any ongoing operations when starting new recording
            cancelCurrentOperation()
            
            // Clear previous output when starting new recording
            Task { @MainActor in
                self.resetState()
            }
            audioRecorder.startRecording()
        }
    }
    
    // Cancel current operation chain (recording, transcription, TTS, playback)
    private func cancelCurrentOperation() {
        print("🛑 Cancelling current operation chain...")
        
        // Cancel any ongoing Task
        if let task = currentOperationTask {
            print("🛑 Cancelling ongoing Task")
            task.cancel()
            currentOperationTask = nil
        }
        
        // Invalidate current operation ID to mark all callbacks as stale
        let cancelledId = UUID()
        currentOperationId = cancelledId
        print("🛑 Operation ID invalidated: \(cancelledId)")
        
        // Stop recording if active
        if audioRecorder.isRecording {
            print("🛑 Stopping active recording")
            audioRecorder.stopRecording()
        }
        
        // Stop audio playback if playing
        if audioPlayer.isPlaying {
            print("🛑 Stopping audio playback")
            audioPlayer.stop()
        }
        
        // Reset TTS generation state
        isGeneratingTTS = false
        
        // Cancel TTS timer
        ttsTimer?.invalidate()
        ttsTimer = nil
        
        // Clear TTS queue
        ttsQueue = []
        accumulatedForTTS = ""
        lastTTSOutput = ""
        lastOutputSnapshot = ""
        
        // Cancel transcription (set flag to ignore results)
        audioRecorder.cancelTranscription()
        
        print("🛑 Current operation chain cancelled")
    }
    
    var body: some View {
        viewModifiers
    }
    
    private var mainContentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if settingsManager.laptopConfig != nil {
                    if settingsManager.commandMode == .direct {
                        // In direct mode, only show cursor_agent terminals
                        if !availableSessionsForDirectMode.isEmpty {
                    sessionSelectorView
                        } else {
                            // No cursor_agent terminals, show create button
                            createHeadlessTerminalView
                        }
                    } else {
                        // In agent mode, show all terminals
                        sessionSelectorView
                    }
                }
                
                Spacer()
                    .frame(height: 20)
                
                recordButtonView
                
                // Status indicator with progress (immediately below button)
                statusIndicatorView
                
                Spacer()
                    .frame(height: 0)
                
                resultDisplayView
            }
        }
        .onChange(of: wsClient.connectionState) { _, _ in
            // View will automatically update via .id modifier
        }
        .onChange(of: recordingStreamClient.connectionState) { _, _ in
            // View will automatically update via .id modifier
        }
        .onChange(of: settingsManager.commandMode) { _, _ in
            // View will automatically update via .id modifier
        }
        .onChange(of: settingsManager.laptopConfig) { oldValue, newValue in
            print("📱 RecordingView: laptopConfig changed (old: \(oldValue?.tunnelId ?? "nil"), new: \(newValue?.tunnelId ?? "nil"))")
            // Start/stop health checker when config changes
            if let config = newValue {
                print("📱 RecordingView: Starting health checker with new config")
                laptopHealthChecker.start(config: config)
            } else {
                print("📱 RecordingView: Stopping health checker (no config)")
                laptopHealthChecker.stop()
            }
            // View will automatically update via .id modifier
        }
        .onAppear {
            print("📱 RecordingView: onAppear - current commandMode: \(settingsManager.commandMode)")
            // Start health checker if config exists
            if let config = settingsManager.laptopConfig {
                print("📱 RecordingView: Starting health checker on appear")
                laptopHealthChecker.start(config: config)
            } else {
                print("📱 RecordingView: No laptop config on appear, health checker not started")
            }
        }
        .onDisappear {
            print("📱 RecordingView: onDisappear - stopping health checker")
            // Stop health checker when view disappears
            laptopHealthChecker.stop()
        }
        .onChange(of: laptopHealthChecker.connectionState) { oldValue, newValue in
            print("📱 RecordingView: Health check state changed: \(oldValue) -> \(newValue)")
            // View will automatically update via .id modifier when health check state changes
        }
    }
    
    
    private var sessionSelectorView: some View {
        // Terminal Session Selector (simplified)
        HStack {
            // Hide session picker in agent mode - agent works without terminal context
            if settingsManager.commandMode == .agent {
                // Empty space - no label needed, toggle in header shows the mode
                EmptyView()
            } else if terminalViewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                // Get sessions based on mode (only for direct mode)
                let validSessions = availableSessionsForDirectMode
                
                if validSessions.isEmpty {
                Button(action: {
                    Task {
                        if let config = settingsManager.laptopConfig {
                            if terminalViewModel.apiClient == nil {
                                terminalViewModel.apiClient = APIClient(config: config)
                            }
                                let terminalType: TerminalType = settingsManager.commandMode == .direct ? .cursorCLI : .regular
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
    
    private var createHeadlessTerminalView: some View {
        Menu {
            Button("Create Cursor CLI") {
                createHeadlessSession(.cursorCLI)
            }
            Button("Create Claude CLI") {
                createHeadlessSession(.claudeCLI)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                Text("Create Headless Terminal")
                    .font(.subheadline)
            }
            .foregroundColor(.blue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    private func createHeadlessSession(_ type: TerminalType) {
        Task {
            if let config = settingsManager.laptopConfig {
                if terminalViewModel.apiClient == nil {
                    terminalViewModel.apiClient = APIClient(config: config)
                }
                let _ = try? await terminalViewModel.apiClient?.createSession(terminalType: type)
                await terminalViewModel.refreshSessions(config: config)
            }
        }
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
        .disabled(settingsManager.laptopConfig == nil || 
                 (settingsManager.commandMode == .direct && !isHeadlessTerminal))
        .scaleEffect(audioRecorder.isRecording ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: audioRecorder.isRecording)
        .padding(.horizontal, 30)
    }
    
    // Status indicator with animated dot
    private var statusIndicatorView: some View {
        Group {
            let state = getCurrentState()
            
            // Show error messages outside the status component
            if state == .idle {
                if settingsManager.laptopConfig == nil {
                    Text("Please connect to laptop in Settings")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                } else if settingsManager.commandMode == .direct && !isHeadlessTerminal {
                    Text("Select a headless terminal")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                } else {
                    // Ready state - show inside status component (no dot for idle)
                    Text(state.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            } else {
                // Active states - show with pulsing and blinking dot
                HStack(spacing: 8) {
                    // Animated indicator dot (pulses and blinks for active states)
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true),
                            value: pulseAnimation
                        )
                        .onAppear {
                            // Start animation when view appears (only for active states)
                            if state.isActive {
                                pulseAnimation = true
                            }
                        }
                        .onChange(of: state) { oldValue, newValue in
                            // Restart animation when state changes
                            if newValue.isActive {
                                // For active states, ensure animation is running
                                pulseAnimation = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    pulseAnimation = true
                                }
                            } else {
                                // For idle state, stop animation
                                pulseAnimation = false
                            }
                        }
                        .onChange(of: isGeneratingTTS) { oldValue, newValue in
                            // Explicitly handle generatingTTS state changes
                            if newValue {
                                // State is now generatingTTS, ensure animation is running
                                print("🔄 GeneratingTTS changed to true, starting pulse animation")
                                pulseAnimation = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    pulseAnimation = true
                                }
                            } else if oldValue && !newValue {
                                // TTS generation stopped
                                print("🔄 GeneratingTTS changed to false, stopping pulse animation")
                                pulseAnimation = false
                            }
                        }
                        .onChange(of: audioRecorder.recognizedText) { oldValue, newValue in
                            // When recognizedText changes, check if we should be in generatingTTS state
                            let currentState = getCurrentState()
                            if currentState == .generatingTTS && !pulseAnimation {
                                print("🔄 State is generatingTTS (via recognizedText change), starting pulse animation")
                                pulseAnimation = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    pulseAnimation = true
                                }
                            }
                        }
                        .onChange(of: settingsManager.lastTerminalOutput) { oldValue, newValue in
                            // When lastTerminalOutput changes, check if we should be in generatingTTS state
                            let currentState = getCurrentState()
                            if currentState == .generatingTTS && !pulseAnimation {
                                print("🔄 State is generatingTTS (via lastTerminalOutput change), starting pulse animation")
                                pulseAnimation = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    pulseAnimation = true
                                }
                            }
                        }
                    
                    // Status text
                    Text(state.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }
    
    // Determine current state
    private func getCurrentState() -> RecordingState {
        // Priority order: recording > transcribing > playing > generating > waiting > idle
        if audioRecorder.isRecording {
            return .recording
        } else if audioRecorder.isTranscribing {
            return .transcribing
        } else if audioPlayer.isPlaying {
            return .playingTTS
        } else if isGeneratingTTS {
            return .generatingTTS
        } else if settingsManager.commandMode == .agent && !audioRecorder.recognizedText.isEmpty && settingsManager.lastTerminalOutput.isEmpty {
            // In agent mode, if we have recognized text but no response yet (lastTerminalOutput is empty), we're waiting
            // lastTerminalOutput will be updated when agent response is received in AudioRecorder
            return .waitingForAgent
        } else if settingsManager.commandMode == .agent && !audioRecorder.recognizedText.isEmpty && !settingsManager.lastTerminalOutput.isEmpty && !isGeneratingTTS && !audioPlayer.isPlaying {
            // If we have recognized text AND response, but TTS hasn't started yet, we're still waiting
            // This prevents showing "ready for recording" between transcribing and generatingTTS
            return .waitingForAgent
        } else {
            return .idle
        }
    }
    
    private var resultDisplayView: some View {
        // Display last transcription/terminal output
        // In direct mode: show when cursor_agent terminal is selected
        // In agent mode: show when there's recognized text OR lastTerminalOutput (agent response)
        Group {
            let shouldShow = settingsManager.commandMode == .direct 
                ? isHeadlessTerminal
                : (!audioRecorder.recognizedText.isEmpty || !settingsManager.lastTerminalOutput.isEmpty)
            
            if shouldShow && !audioRecorder.isTranscribing {
                VStack(alignment: .leading, spacing: 16) {
                    // Display text based on mode
                    // In direct mode, show terminal output (result), not the command
                    // In agent mode, show recognized text or agent response
                    let displayText = settingsManager.commandMode == .direct 
                        ? (settingsManager.lastTerminalOutput.isEmpty ? "Waiting for command output..." : settingsManager.lastTerminalOutput)
                        : (audioRecorder.recognizedText.isEmpty ? settingsManager.lastTerminalOutput : audioRecorder.recognizedText)
                    
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
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                    
                    // Replay button (show after TTS finished playing)
                    if lastTTSAudioData != nil && !audioPlayer.isPlaying && getCurrentState() == .idle {
                        HStack {
                            Spacer()
                            Button(action: {
                                replayLastTTS()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.caption)
                                    Text("Replay")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .padding(.horizontal, 20)
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
    
    // Replay last TTS audio
    private func replayLastTTS() {
        guard let audioData = lastTTSAudioData else {
            print("⚠️ No audio data to replay")
            return
        }
        
        Task { @MainActor in
            do {
                try self.audioPlayer.play(audioData: audioData)
                print("🔊 Replaying last TTS audio")
            } catch {
                print("❌ Failed to replay TTS: \(error)")
            }
        }
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
            guard settingsManager.commandMode == .direct else { return }
            
            Task { @MainActor in
                print("📤 Command sent notification received")
                
                self.ttsTimer?.invalidate()
                self.ttsTimer = nil
                self.lastTTSOutput = ""
                self.accumulatedForTTS = ""
                self.lastOutputSnapshot = ""
                self.ttsQueue = []
                self.accumulatedOutput = ""
                self.lastSentCommand = notification.userInfo?["command"] as? String ?? ""
            }
            
            guard let userInfo = notification.userInfo,
                  let command = userInfo["command"] as? String,
                  let sessionId = userInfo["sessionId"] as? String else {
                return
            }
            
            let transport = userInfo["transport"] as? String ?? "interactive"
            if transport == "headless" {
                return
            }
            
            guard isCursorAgentTerminal else { return }
            
            Task { @MainActor in
                self.lastSentCommand = command
            }
            
            if let config = settingsManager.laptopConfig {
                if !wsClient.isConnected || settingsManager.selectedSessionId != sessionId {
                    connectToTerminalStream(config: config, sessionId: sessionId)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        var retryCount = 0
                        let maxRetries = 3
                        
                        func trySend() {
                            if self.wsClient.isConnected {
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
                    sendCommandToTerminal(command, to: wsClient)
                    print("📤 Sent command via WebSocket input: \(command)")
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
                
                // Update AudioRecorder with text from Watch (ensure main thread)
                Task { @MainActor in
                    self.audioRecorder.recognizedText = userInfo["text"] as? String ?? ""
                    
                    print("   ✅ RecordingView updated successfully")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TTSPlaybackFinished"))) { _ in
            // When TTS playback finishes, process queue if there are items
            print("🔊 TTS playback finished, checking queue...")
            Task { @MainActor in
                // Ensure all TTS-related flags are reset
                self.isGeneratingTTS = false
                
                // Clear recognized text after playback to return to idle state
                // This ensures we don't show "waiting for agent" after response is played
                // But DON'T clear lastTerminalOutput - keep the agent response visible
                if settingsManager.commandMode == .agent {
                    self.audioRecorder.recognizedText = ""
                }
                await self.processQueueAfterPlayback()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AgentResponseTTSGenerating"))) { _ in
            // TTS generation started - only process in agent mode
            guard settingsManager.commandMode == .agent else { return }
            Task { @MainActor in
                self.isGeneratingTTS = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AgentResponseTTSFailed"))) { notification in
            // TTS generation failed - reset state to allow retry
            guard settingsManager.commandMode == .agent else { return }
            Task { @MainActor in
                self.isGeneratingTTS = false
                // Clear recognizedText after a delay to allow retry
                // Keep error message visible briefly, then clear for next attempt
                if let error = notification.userInfo?["error"] as? String {
                    print("❌ TTS failed: \(error)")
                    // Clear after 3 seconds to allow retry
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if self.audioRecorder.recognizedText.contains("Transcription error") || 
                           self.audioRecorder.recognizedText.contains("TTS error") {
                            self.audioRecorder.recognizedText = ""
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AgentResponseTTSReady"))) { notification in
            // Only process TTS if this is the active tab AND in agent mode
            guard isActiveTab else {
                print("⚠️ AgentResponseTTSReady: Ignoring - not active tab")
                return
            }
            
            guard settingsManager.commandMode == .agent else {
                print("⚠️ AgentResponseTTSReady: Ignoring in non-agent mode (current: \(settingsManager.commandMode))")
                return
            }
            
            // Check if this TTS is for a terminal session that's being handled by TerminalSessionAgentView
            // If userInfo contains "sessionId" and it matches a terminal session, ignore it
            // TerminalSessionAgentView handles its own TTS playback
            if let userInfo = notification.userInfo,
               let sessionId = userInfo["sessionId"] as? String,
               !sessionId.isEmpty {
                // This TTS is for a specific terminal session, which is handled by TerminalSessionAgentView
                // Ignore it here to prevent duplicate playback
                print("⚠️ AgentResponseTTSReady: Ignoring - TTS is for terminal session \(sessionId), handled by TerminalSessionAgentView")
                return
            }
            
            guard let userInfo = notification.userInfo,
                  let audioData = userInfo["audioData"] as? Data else {
                print("❌ AgentResponseTTSReady: Missing audio data")
                return
            }
            
            Task { @MainActor in
                // TTS generation is complete, reset the flag
                self.isGeneratingTTS = false
                
                // Always stop any current playback first to prevent echo/overlap
                if self.audioPlayer.isPlaying {
                    print("🛑 Stopping current playback before starting new TTS")
                    self.audioPlayer.stop()
                    // Wait for stop to complete
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                }
                
                // Double-check that we're still the active tab, in agent mode, and not playing
                guard self.isActiveTab,
                      settingsManager.commandMode == .agent,
                      !self.audioPlayer.isPlaying else {
                    print("⚠️ AgentResponseTTSReady: Skipping playback - tab/mode changed or already playing")
                    return
                }
                
                do {
                    try self.audioPlayer.play(audioData: audioData)
                    print("🔊 Agent response TTS playback started (active tab only)")
                } catch {
                    print("❌ Failed to play agent response TTS: \(error)")
                }
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
              (session.terminalType == .cursorAgent || session.terminalType.isHeadless) else {
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
                // Check if we're on a terminal detail page (TerminalSessionAgentView handles TTS for terminal sessions)
                // If we're on the Agent tab (activeTab == 0), we should handle TTS
                // But if we're on the Terminals tab (activeTab == 1), TerminalSessionAgentView handles TTS
                // So we should only schedule TTS if we're on the Agent tab
                guard self.isActiveTab else {
                    print("⚠️ RecordingView: Ignoring recording stream message - not active tab (handled by TerminalSessionAgentView)")
                    return
                }
                
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
        
        // Require a headless terminal for automatic TTS
        guard isHeadlessTerminal else {
            print("⚠️ scheduleAutoTTS: Not in headless terminal, skipping TTS")
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
                    // Check if we're still in headless terminal
                    guard self.isHeadlessTerminal else {
                        print("⚠️ scheduleAutoTTS: No longer in headless terminal, skipping playback")
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
        guard isHeadlessTerminal else {
            print("⚠️ playAccumulatedTTS: Not in headless terminal, skipping")
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
        
        // Check for laptop config
        guard let laptopConfig = settingsManager.laptopConfig else {
            print("⚠️ No laptop config for TTS")
            return
        }
        
        print("🔊 Generating TTS for accumulated output (length: \(cleanedText.count)) at \(settingsManager.ttsSpeed)x speed...")
        
        // Notify that TTS generation has started
        await MainActor.run {
            self.isGeneratingTTS = true
        }
        
        do {
            // Build TTS endpoint from laptop config (proxy endpoint via tunnel)
            let ttsEndpoint = "\(laptopConfig.apiBaseUrl)/proxy/tts/synthesize"
            let ttsHandler = LocalTTSHandler(laptopAuthKey: laptopConfig.authKey, endpoint: ttsEndpoint)
            let voice = selectVoiceForLanguage(settingsManager.transcriptionLanguage)
            let language = settingsManager.transcriptionLanguage.rawValue
            
            // Use speed and language from settings (client preferences)
            // Voice and speed are sent to server, but model and other params come from server config
            let audioData = try await ttsHandler.synthesize(
                text: cleanedText,
                voice: voice,
                speed: settingsManager.ttsSpeed,
                language: language
            )
            
            // Update last spoken text and store audio data for replay
            await MainActor.run {
                // TTS generation complete
                self.isGeneratingTTS = false
                self.lastTTSOutput = accumulated
                self.lastTTSAudioData = audioData
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
            // Check if we're still in a headless terminal
            guard isHeadlessTerminal else {
                print("🔇 processQueueAfterPlayback: No longer in headless terminal, clearing queue and stopping playback")
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
                // Check again if we're still in a headless terminal
                if !isHeadlessTerminal {
                    print("🔇 processQueueAfterPlayback: No longer in headless terminal during playback, stopping")
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
        
        // Check if we're in a headless terminal (unless from queue, which was already validated)
        if !isFromQueue && !isHeadlessTerminal {
            print("⚠️ generateAndPlayTTS: Not in headless terminal, skipping")
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
        
        // Check for laptop config
        guard settingsManager.laptopConfig != nil else {
            print("⚠️ No laptop config for TTS")
            return
        }
        
        // Clean text for TTS (remove ANSI codes, etc.)
        let cleanedText = cleanTerminalOutputForTTS(trimmed)
        
        // Skip if cleaned text is empty
        if cleanedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            return
        }
        
        print("🔊 Generating TTS (length: \(cleanedText.count)) at \(settingsManager.ttsSpeed)x speed...")
        
        // Notify that TTS generation has started
        await MainActor.run {
            self.isGeneratingTTS = true
        }
        
        do {
            guard let laptopConfig = settingsManager.laptopConfig else {
                print("❌ Laptop config not available")
                await MainActor.run {
                    self.isGeneratingTTS = false
                }
                return
            }
            // Build TTS endpoint from laptop config (proxy endpoint via tunnel)
            let ttsEndpoint = "\(laptopConfig.apiBaseUrl)/proxy/tts/synthesize"
            let ttsHandler = LocalTTSHandler(laptopAuthKey: laptopConfig.authKey, endpoint: ttsEndpoint)
            let voice = selectVoiceForLanguage(settingsManager.transcriptionLanguage)
            let language = settingsManager.transcriptionLanguage.rawValue
            
            // Use speed and language from settings (client preferences)
            // Voice and speed are sent to server, but model and other params come from server config
            let audioData = try await ttsHandler.synthesize(
                text: cleanedText,
                voice: voice,
                speed: settingsManager.ttsSpeed,
                language: language
            )
            
            // Update last spoken text
            // For queue items, we need to track what was actually spoken
            // Since queued items are already new content, we append them to lastTTSOutput
            await MainActor.run {
                // TTS generation complete
                self.isGeneratingTTS = false
                
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
            
            // Store audio data and play on main thread
            await MainActor.run {
                self.lastTTSAudioData = audioData
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



