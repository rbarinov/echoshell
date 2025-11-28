//
//  RecordingView.swift
//  EchoShell
//
//  Created by Roman Barinov on 2025.11.21.
//

import SwiftUI
import AVFoundation
import UserNotifications

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

    @StateObject private var viewModel: AgentViewModel
    @StateObject private var terminalViewModel = TerminalViewModel()
    @StateObject private var wsClient = WebSocketClient()
    @StateObject private var recordingStreamClient = RecordingStreamClient()
    @StateObject private var laptopHealthChecker = LaptopHealthChecker()
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showSessionPicker = false
    @State private var lastSentCommand: String = "" // Track last sent command to filter it from output
    @State private var recordingStreamSessionId: String?

    // Default initializer for backward compatibility
    init(isActiveTab: Bool = true) {
        self.isActiveTab = isActiveTab

        // Initialize dependencies with placeholder config (will be updated via updateConfig)
        let player = AudioPlayer()
        let ttsService = TTSService(audioPlayer: player)
        let audioRecorder = AudioRecorder()
        let placeholderConfig = TunnelConfig(tunnelId: "", tunnelUrl: "", wsUrl: "", keyEndpoint: "", authKey: "")
        let apiClient = APIClient(config: placeholderConfig)
        let recordingStreamClient = RecordingStreamClient()

        // Create AgentViewModel with dependencies
        _viewModel = StateObject(wrappedValue: AgentViewModel(
            audioRecorder: audioRecorder,
            ttsService: ttsService,
            apiClient: apiClient,
            recordingStreamClient: recordingStreamClient,
            config: placeholderConfig
        ))
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
    
    // Show error notification (system notification)
    private func showErrorNotification(title: String, message: String) {
        print("🔔 Error Notification: \(title) - \(message)")
        
        // Request notification permission if not already granted
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = message
                content.sound = .default
                content.categoryIdentifier = "ERROR"
                
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil // Show immediately
                )
                
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ Failed to show error notification: \(error)")
                    }
                }
            } else {
                print("⚠️ Notification permission not granted")
            }
        }
    }
    
    // Stop all TTS tasks and clear output
    // Note: This method delegates to ViewModel for proper separation of concerns
    private func stopAllTTSAndClearOutput() {
        print("🛑 RecordingView: Delegating stopAllTTSAndClearOutput to ViewModel")
        viewModel.stopAllTTSAndClearOutput()
    }
    
    // Get selected session
    private var selectedSession: TerminalSession? {
        guard let sessionId = settingsManager.selectedSessionId else { return nil }
        return terminalViewModel.sessions.first { $0.id == sessionId }
    }
    
    // Check if selected session is Cursor Agent terminal
    private var isCursorAgentTerminal: Bool {
        return selectedSession?.terminalType == .cursor
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
        if viewModel.isRecording {
            viewModel.stopRecording()
        } else {
            // Cancel any ongoing operations when starting new recording
            viewModel.cancelCurrentOperation()

            // Clear previous output when starting new recording
            viewModel.resetStateForNewCommand()

            viewModel.startRecording()
        }
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
            }
            
            // Check if we have TTS audio that was generated while we were away
            // If so, play it automatically when user returns to Agent page
            if isActiveTab && settingsManager.commandMode == .agent {
                Task { @MainActor in
                    // Small delay to ensure view is fully loaded
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

                    let ttsService = self.viewModel.ttsService
                    let audioPlayer = ttsService.audioPlayer

                    // Check if we have TTS audio and it's not already playing
                    if let audioData = ttsService.lastAudioData,
                       !audioPlayer.isPlaying,
                       !audioPlayer.isPaused,
                       !self.viewModel.agentResponseText.isEmpty {
                        print("📱 RecordingView: Found TTS audio from background - playing now")
                        do {
                            try await audioPlayer.play(audioData: audioData, title: "AI Assistant Response")
                            print("🔊 Playing TTS audio that was generated while away")
                        } catch {
                            print("❌ Failed to play background TTS: \(error)")
                        }
                    }
                }
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
                                let terminalType: TerminalType = settingsManager.commandMode == .direct ? .cursor : .regular
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
                                    if session.terminalType == .cursor {
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
                            ? newSessions.filter { $0.terminalType == .cursor }
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
                createHeadlessSession(.cursor)
            }
            Button("Create Claude CLI") {
                createHeadlessSession(.claude)
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
                                    gradient: Gradient(colors: viewModel.isRecording
                                        ? [Color.red, Color.pink]
                                        : [Color.blue, Color.cyan]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 160, height: 160)
                            .shadow(color: viewModel.isRecording
                                ? Color.red.opacity(0.6)
                                : Color.blue.opacity(0.5),
                                radius: 20, x: 0, y: 10)

                        // Inner circle
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 140, height: 140)

                        // Icon
                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 55, weight: .medium))
                .foregroundColor(.white)
                .symbolEffect(.pulse, isActive: viewModel.isRecording)
            }
        }
        .buttonStyle(.plain)
        .disabled(settingsManager.laptopConfig == nil ||
                 (settingsManager.commandMode == .direct && !isHeadlessTerminal))
        .scaleEffect(viewModel.isRecording ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.isRecording)
        .padding(.horizontal, 30)
    }
    
    // Status indicator with animated dot
    private var statusIndicatorView: some View {
        Group {
            let state = viewModel.getCurrentState()

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
                // Active states - show with pulsing dot
                HStack(spacing: 8) {
                    // Animated indicator dot (pulses for active states)
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(viewModel.pulseAnimation ? 1.2 : 1.0)
                        .opacity(viewModel.pulseAnimation ? 1.0 : 0.5)
                        .animation(
                            viewModel.pulseAnimation ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                            value: viewModel.pulseAnimation
                        )

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
    
    private var resultDisplayView: some View {
        // Display last transcription/terminal output
        // In direct mode: show when cursor_agent terminal is selected
        // In agent mode: show when there's recognized text OR lastTerminalOutput (agent response)
        // Also show audio controls if TTS audio is available, even if no text to display
        Group {
            let shouldShowText = settingsManager.commandMode == .direct
                ? isHeadlessTerminal
                : (!viewModel.recognizedText.isEmpty || !viewModel.agentResponseText.isEmpty)

            let ttsService = viewModel.ttsService // Access through viewModel
            let audioPlayer = ttsService.audioPlayer
            let shouldShowAudioControls = ttsService.lastAudioData != nil || audioPlayer.isPlaying || audioPlayer.isPaused

            if (shouldShowText || shouldShowAudioControls) && !viewModel.isTranscribing {
                VStack(alignment: .leading, spacing: 16) {
                    // Display text based on mode (only if there's text to show)
                    if shouldShowText {
                        let displayText = settingsManager.commandMode == .direct
                            ? (settingsManager.lastTerminalOutput.isEmpty ? "Waiting for command output..." : settingsManager.lastTerminalOutput)
                            : (viewModel.recognizedText.isEmpty ? viewModel.agentResponseText : viewModel.recognizedText)

                        Text(displayText)
                            .onAppear {
                                print("📱 resultDisplayView: Displaying text (length: \(displayText.count), mode: \(settingsManager.commandMode))")
                            }
                            .onChange(of: viewModel.agentResponseText) { oldValue, newValue in
                                print("📱 resultDisplayView: agentResponseText changed (old: \(oldValue.count), new: \(newValue.count))")
                            }
                            .onChange(of: viewModel.recognizedText) { oldValue, newValue in
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
                    }
                    
                    // Audio control buttons (always show if audio is available)
                    if shouldShowAudioControls {
                        AudioControlButtonsView(
                            audioPlayer: audioPlayer,
                            ttsService: ttsService,
                            showTopPadding: shouldShowText
                        )
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
                // Load ViewModel state from persistence
                viewModel.loadState()

                // Configure AudioRecorder with settingsManager
                // This will disable autoSendCommand in Agent mode so commands are sent via AgentViewModel.executeCommand()
                viewModel.configure(with: settingsManager)

                // Update ViewModel config when laptop config is available
                if let config = settingsManager.laptopConfig {
                    viewModel.updateConfig(config)
                }

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
            .onDisappear {
                // Save ViewModel state to persistence
                viewModel.saveState()
            }
        .onChange(of: settingsManager.laptopConfig) { oldValue, newValue in
            // Configure AudioRecorder when config changes
            viewModel.configure(with: settingsManager)

            // Update ViewModel config
            if let config = newValue {
                viewModel.updateConfig(config)

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
                if terminalViewModel.sessions.first(where: { $0.id == sessionId })?.terminalType == .cursor {
                connectToTerminalStream(config: config, sessionId: sessionId)
                    connectToRecordingStream(config: config, sessionId: sessionId)
                }
            } else if newValue == .agent {
                recordingStreamClient.disconnect()
                // Clear terminal output when switching to agent mode
                // Ensure updates happen on main thread
                Task { @MainActor in
                    // Reset ViewModel state for agent mode
                    self.viewModel.resetStateForNewCommand()
                    // Don't clear lastTerminalOutput when switching modes - keep history
                    // settingsManager.lastTerminalOutput is preserved
                }
            }
        }
        .onChange(of: viewModel.isTranscribing) { oldValue, newValue in
            // When transcription completes in Agent mode, execute command via AgentViewModel
            if oldValue == true && newValue == false && !viewModel.recognizedText.isEmpty {
                if settingsManager.commandMode == .agent {
                    print("✅ RecordingView: Transcription completed in Agent mode, executing command via AgentViewModel")
                    Task {
                        await viewModel.executeCommand(viewModel.recognizedText, sessionId: nil)
                    }
                }
            }
        }
        .onReceive(EventBus.shared.commandSentPublisher) { event in
            guard settingsManager.commandMode == .direct else { return }
            
            Task { @MainActor in
                print("📤 Command sent notification received")
                
                // Reset ViewModel state for new command
                self.viewModel.resetStateForNewCommand()
                self.lastSentCommand = event.command
            }
            
            let command = event.command
            guard let sessionId = event.sessionId else {
                return
            }
            
            let transport = event.transport
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
                            if wsClient.isConnected {
                                sendCommandToTerminal(command, to: wsClient)
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
.onReceive(EventBus.shared.$transcriptionStarted) { started in
            guard started else { return }
            // Clear state when transcription starts (handled by ViewModel)
            Task { @MainActor in
                print("🎤 Transcription started")
                self.viewModel.resetStateForNewCommand()
                self.lastSentCommand = ""
            }
        }
        .onReceive(EventBus.shared.transcriptionStatsUpdatedPublisher) { stats in
            print("📱 iOS RecordingView: Received TranscriptionStatsUpdated notification")
            print("   📊 Updating RecordingView with new transcription:")
            print("      Text length: \(stats.text?.count ?? 0) chars")

            // Update ViewModel with text from Watch (ensure main thread)
            Task { @MainActor in
                if let text = stats.text {
                    self.viewModel.recognizedText = text
                }
                print("   ✅ RecordingView updated successfully")
            }
        }
        .onReceive(EventBus.shared.ttsPlaybackFinishedPublisher) { _ in
            // When TTS playback finishes, clear recognized text in agent mode
            print("🔊 TTS playback finished")
            Task { @MainActor in
                // Clear recognized text after playback to return to idle state
                if settingsManager.commandMode == .agent {
                    self.viewModel.recognizedText = ""
                }
            }
        }
        .onReceive(EventBus.shared.$ttsGenerating) { isGenerating in
            guard isGenerating else { return }
            // TTS generation started - only process in agent mode
            // Note: TTSService tracks isGenerating internally
            print("🔊 Agent response TTS generation started")
        }
        .onReceive(EventBus.shared.ttsFailedPublisher) { error in
            // TTS generation failed - show error notification
            guard settingsManager.commandMode == .agent else { return }
            Task { @MainActor in
                let errorMessage: String
                switch error {
                case .synthesisFailed(let message):
                    errorMessage = message
                case .playbackFailed(let err):
                    errorMessage = err.localizedDescription
                }
                
                print("❌ TTS failed: \(errorMessage)")
                // Show error notification
                self.showErrorNotification(title: "TTS Generation Failed", message: errorMessage)
                // Clear after 3 seconds to allow retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if viewModel.recognizedText.contains("Transcription error") ||
                       viewModel.recognizedText.contains("TTS error") {
                        viewModel.recognizedText = ""
                    }
                }
            }
        }
        .onReceive(EventBus.shared.ttsReadyPublisher) { event in
            // Process TTS even if not active tab - store it for playback when user returns
            guard settingsManager.commandMode == .agent else {
                print("⚠️ AgentResponseTTSReady: Ignoring in non-agent mode (current: \(settingsManager.commandMode))")
                return
            }

            // Check if this TTS is for a terminal session that's being handled by TerminalSessionAgentView
            if let sessionId = event.sessionId, !sessionId.isEmpty {
                print("⚠️ AgentResponseTTSReady: Ignoring - TTS is for terminal session \(sessionId), handled by TerminalSessionAgentView")
                return
            }

            let audioData = event.audioData

            Task { @MainActor in
                // Store audio data in TTS service for replay
                self.viewModel.ttsService.lastAudioData = audioData

                // Note: ttsService.synthesizeAndPlay() already plays the audio
                // We just need to ensure UI is updated and replay button is available
                // Only play again if active tab and not already playing (for safety)
                if self.isActiveTab {
                    let audioPlayer = self.viewModel.ttsService.audioPlayer

                    // Check if audio is already playing (from ttsService.synthesizeAndPlay())
                    // If not playing, start playback (fallback in case synthesizeAndPlay didn't play)
                    if !audioPlayer.isPlaying {
                        // Double-check that we're still in agent mode
                        guard settingsManager.commandMode == .agent else {
                            print("⚠️ AgentResponseTTSReady: Skipping playback - not in agent mode")
                            return
                        }

                        do {
                            try await audioPlayer.play(audioData: audioData, title: "AI Assistant Response")
                            print("🔊 Agent response TTS playback started (fallback)")
                        } catch {
                            print("❌ Failed to play agent response TTS: \(error)")
                            self.showErrorNotification(title: "TTS Playback Failed", message: error.localizedDescription)
                        }
                    } else {
                        print("🔊 Agent response TTS already playing (from synthesizeAndPlay)")
                    }
                } else {
                    print("📱 AgentResponseTTSReady: TTS received but not active tab - stored for later playback")
                }
            }
        }
        .onDisappear {
            // DON'T stop TTS and audio playback when leaving the page
            // Allow background tasks to complete - they will continue in background
            print("📱 RecordingView: onDisappear - keeping TTS and audio running in background")

            // DON'T disconnect recording stream - keep it connected for background events
            // recordingStreamClient.disconnect() - REMOVED

            // DON'T stop audio playback - let it continue
            // This allows TTS to finish playing even if user navigates away

            // ViewModel handles TTS timer management internally
            // State is preserved in ViewModel for when user returns
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
        guard session.terminalType == .cursor else { return }

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
              (session.terminalType == .cursor || session.terminalType.isHeadless) else {
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
                // Always update lastTerminalOutput even if not active tab - it will be displayed when user returns
                settingsManager.lastTerminalOutput = message.text
                
                // Only schedule TTS if active tab, otherwise it will be generated when user returns
                if isActiveTab {
                    // Use ViewModel method for TTS scheduling
                    viewModel.scheduleAutoTTS(
                        lastTerminalOutput: settingsManager.lastTerminalOutput,
                        isHeadlessTerminal: isHeadlessTerminal,
                        ttsSpeed: settingsManager.ttsSpeed,
                        language: settingsManager.transcriptionLanguage.rawValue
                    )
                } else {
                    print("📱 RecordingView: Recording stream message received but not active tab - stored for later")
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
    
    // MARK: - Deprecated: Not used anymore
    // Server handles all output filtering for headless agents
    // This method is kept for reference only
    private func extractCommandResult_DEPRECATED(from output: String) -> String {
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
    
    // MARK: - TTS Methods (moved to ViewModel)
    // All TTS scheduling and playback logic has been moved to AgentViewModel
    // Methods: scheduleAutoTTS, playAccumulatedTTS, processQueueAfterPlayback, generateAndPlayTTS
    // are now in AgentViewModel and should be called via viewModel
    
}

// MARK: - Audio Control Buttons Component
/// Separate view component that properly observes AudioPlayer state changes
/// This ensures buttons update correctly when playback state changes
struct AudioControlButtonsView: View {
    @ObservedObject var audioPlayer: AudioPlayer
    let ttsService: TTSService
    let showTopPadding: Bool

    var body: some View {
        HStack {
            Spacer()

            // Stop button (show during playback)
            if audioPlayer.isPlaying {
                Button(action: {
                    audioPlayer.stop()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.caption)
                        Text("Stop")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 20)
            }
            // Resume button (show when paused)
            else if audioPlayer.isPaused {
                Button(action: {
                    audioPlayer.resume()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                        Text("Resume")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 20)
            }
            // Replay button (show when TTS audio is available and not playing)
            else if ttsService.lastAudioData != nil {
                Button(action: {
                    Task {
                        await ttsService.replay()
                    }
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
        .padding(.top, showTopPadding ? 10 : 0)
    }
}

#Preview {
    RecordingView()
        .environmentObject(SettingsManager())
}



