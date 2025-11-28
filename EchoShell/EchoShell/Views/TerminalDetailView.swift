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
                // Content based on selected mode
                if viewMode == .pty {
                    ptyTerminalView
                } else {
                    agentView
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
            // For AI terminals (cursor/claude), default to agent mode on first open
            // For regular terminals, always use PTY mode
            if session.terminalType == .regular {
                sessionState.setActiveSession(session.id, name: session.name ?? "", defaultMode: .pty)
                sessionState.setViewMode(.pty, for: session.id)
            } else {
                // For AI terminals, check if we have a saved mode
                let savedMode = sessionState.getViewMode(for: session.id)
                if savedMode == .pty || savedMode == .agent {
                    // Use saved mode if it exists (user previously selected a mode)
                    sessionState.setActiveSession(session.id, name: session.name ?? "", defaultMode: savedMode)
                    sessionState.setViewMode(savedMode, for: session.id)
                } else {
                    // First time opening - use agent mode as default
                    sessionState.setActiveSession(session.id, name: session.name ?? "", defaultMode: .agent)
                    sessionState.setViewMode(.agent, for: session.id)
                }
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
            
            // Update view mode via SessionStateManager (single source of truth)
            let newMode: TerminalViewMode = mode == .agent ? .agent : .pty
            sessionState.setViewMode(newMode, for: session.id)
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
            wsClient.connect(config: config, sessionId: session.id) { text in
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
    private var agentView: some View {
        // For headless terminals, show chat interface
        if session.terminalType == .cursor || session.terminalType == .claude {
            ChatTerminalView(session: session, config: config)
                .environmentObject(settingsManager)
        } else {
            // For regular terminals in agent mode (legacy), show old agent view
            TerminalSessionAgentView(session: session, config: config)
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

// Terminal Session Agent View - similar to RecordingView but for specific terminal session
struct TerminalSessionAgentView: View {
    let session: TerminalSession
    let config: TunnelConfig
    @EnvironmentObject var settingsManager: SettingsManager

    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var recordingStreamClient = RecordingStreamClient()
    @StateObject private var audioPlayer: AudioPlayer
    @StateObject private var ttsService: TTSService
    @State private var pulseAnimation: Bool = false
    @State private var accumulatedText: String = "" // Accumulate assistant messages until completion
    @State private var lastTTSedText: String = "" // Track what text we've already generated TTS for
    @State private var ttsTriggeredForCurrentResponse: Bool = false // Track if TTS was triggered for current response
    @State private var agentResponseText: String = "" // Local storage for agent response (separate from global settingsManager)
    @State private var lastCompletionText: String = "" // Track the last text for which we received completion signal

    // Initialize with shared AudioPlayer and TTSService
    init(session: TerminalSession, config: TunnelConfig) {
        self.session = session
        self.config = config

        let player = AudioPlayer()
        _audioPlayer = StateObject(wrappedValue: player)
        _ttsService = StateObject(wrappedValue: TTSService(audioPlayer: player))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
        .onAppear {
            audioRecorder.configure(with: settingsManager)
            // Disable automatic command sending to agent - we'll send directly to terminal
            audioRecorder.autoSendCommand = false
            // Connect to recording stream for this specific session
            connectToRecordingStream()
        }
        .onChange(of: audioRecorder.isTranscribing) { oldValue, newValue in
            // When transcription completes (isTranscribing becomes false), send command to this session
            if oldValue == true && newValue == false && !audioRecorder.recognizedText.isEmpty {
                print("✅ TerminalSessionAgentView: Transcription completed, sending command to session \(session.id): \(audioRecorder.recognizedText)")
                sendCommandToSession(audioRecorder.recognizedText)
            }
        }
        .onDisappear {
            // Save terminal state before leaving
            saveTerminalState()
            
            // DON'T disconnect WebSocket on disappear - keep it connected in background
            // This ensures we receive completion events even when user navigates away
            // The connection will be cleaned up when the view is actually deallocated
            
            // Re-enable automatic command sending when leaving this view
            audioRecorder.autoSendCommand = true
        }
        .onAppear {
            // Load terminal state when appearing
            loadTerminalState()
            
            // Reconnect to stream if not already connected (in case it was disconnected)
            if !recordingStreamClient.isConnected {
                connectToRecordingStream()
            }
            
            // Check if we have a completed response that needs TTS
            // This handles the case where user navigated away and came back
            let trimmedText = agentResponseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty &&
               trimmedText != lastTTSedText &&
               !ttsService.isGenerating &&
               !audioPlayer.isPlaying &&
               ttsService.lastAudioData == nil,
               let laptopConfig = settingsManager.laptopConfig {
                // We have text but no TTS - generate it now
                print("🔄 TerminalSessionAgentView: Found completed response without TTS, generating now")
                lastTTSedText = trimmedText
                ttsTriggeredForCurrentResponse = true
                generateTTS(for: agentResponseText, config: laptopConfig)
            } else if !trimmedText.isEmpty &&
                      trimmedText == lastTTSedText &&
                      ttsService.lastAudioData != nil &&
                      !audioPlayer.isPlaying {
                // We have TTS audio but it's not playing - offer to play it
                print("🔄 TerminalSessionAgentView: Found completed response with TTS, ready to play")
            }
        }
    }
    
    private var recordButtonView: some View {
        // Main Record Button - same style as RecordingView
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
        .disabled(settingsManager.laptopConfig == nil)
        .scaleEffect(audioRecorder.isRecording ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: audioRecorder.isRecording)
        .padding(.horizontal, 30)
    }
    
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
                        .onChange(of: ttsService.isGenerating) { oldValue, newValue in
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
                        .onChange(of: agentResponseText) { oldValue, newValue in
                            // When agentResponseText changes, check if we should be in generatingTTS state
                            let currentState = getCurrentState()
                            if currentState == .generatingTTS && !pulseAnimation {
                                print("🔄 State is generatingTTS (via agentResponseText change), starting pulse animation")
                                pulseAnimation = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    pulseAnimation = true
                                }
                            }
                        }
                        .onChange(of: ttsService.isGenerating) { oldValue, newValue in
                            // When isGenerating changes, update pulse animation
                            if newValue && !pulseAnimation {
                                print("🔄 isGenerating changed to true, starting pulse animation")
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
    
    private var resultDisplayView: some View {
        // Display last transcription/terminal output
        // Show when there's recognized text OR agentResponseText (agent response)
        // Also show audio controls if TTS audio is available, even if no text to display
        // Use local agentResponseText instead of global settingsManager.lastTerminalOutput
        Group {
            let shouldShowText = !audioRecorder.recognizedText.isEmpty || !agentResponseText.isEmpty
            let shouldShowAudioControls = ttsService.lastAudioData != nil || audioPlayer.isPlaying || audioPlayer.isPaused
            
            if (shouldShowText || shouldShowAudioControls) && !audioRecorder.isTranscribing {
                VStack(alignment: .leading, spacing: 16) {
                    // Display text based on what's available (only if there's text to show)
                    if shouldShowText {
                        // Priority: show agent response (agentResponseText) if available, otherwise show recognized text (question)
                        let displayText = !agentResponseText.isEmpty ? agentResponseText : audioRecorder.recognizedText
                        
                        Text(displayText)
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
                            if ttsService.lastAudioData != nil && !audioPlayer.isPlaying && !audioPlayer.isPaused {
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
                        .padding(.top, shouldShowText ? 10 : 0)
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
    
    // Determine current state - simplified logic
    private func getCurrentState() -> RecordingState {
        // Priority order: recording > transcribing > playing > generating > waiting > idle
        if audioRecorder.isRecording {
            return .recording
        } else if audioRecorder.isTranscribing {
            return .transcribing
        } else if audioPlayer.isPlaying {
            return .playingTTS
        } else if ttsService.isGenerating {
            print("🔍🔍🔍 getCurrentState: isGenerating=true, returning .generatingTTS")
            return .generatingTTS
        } else if !audioRecorder.recognizedText.isEmpty && agentResponseText.isEmpty {
            // We have a question but no answer yet
            print("🔍🔍🔍 getCurrentState: recognizedText=\(audioRecorder.recognizedText.count) chars, agentResponseText empty, returning .waitingForAgent")
            return .waitingForAgent
        } else if !agentResponseText.isEmpty {
            // We have an answer - check if TTS is done
            print("🔍🔍🔍 getCurrentState: agentResponseText=\(agentResponseText.count) chars, lastAudioData=\(ttsService.lastAudioData != nil), isGenerating=\(ttsService.isGenerating), isPlaying=\(audioPlayer.isPlaying), ttsTriggered=\(ttsTriggeredForCurrentResponse)")
            
            // If audio is playing, show playing state
            if audioPlayer.isPlaying {
                print("🔍🔍🔍 getCurrentState: Audio is playing, returning .playingTTS")
                return .playingTTS
            }
            
            // If TTS is generating, show generating state
            if ttsService.isGenerating {
                print("🔍🔍🔍 getCurrentState: TTS is generating, returning .generatingTTS")
                return .generatingTTS
            }
            
            // If TTS audio is available (even if not playing), we're done (idle)
            if ttsService.lastAudioData != nil {
                print("🔍🔍🔍 getCurrentState: TTS audio available, returning .idle")
                return .idle
            }
            
            // If TTS was triggered but not completed yet - still generating
            if ttsTriggeredForCurrentResponse {
                print("🔍🔍🔍 getCurrentState: TTS triggered but not completed, returning .generatingTTS")
                return .generatingTTS
            }
            
            // Answer received but TTS not triggered yet - waiting for isComplete message
            print("🔍🔍🔍 getCurrentState: Answer received but TTS not triggered, returning .waitingForAgent")
            return .waitingForAgent
        } else {
            print("🔍🔍🔍 getCurrentState: No conditions met, returning .idle")
            return .idle
        }
    }
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        } else {
            cancelCurrentOperation()
            // Reset accumulated text for new command
            accumulatedText = ""
            agentResponseText = "" // Reset local agent response
            lastTTSedText = "" // Reset TTS tracking
            lastCompletionText = "" // Reset completion tracking
            ttsService.reset() // Reset TTS service state
            ttsTriggeredForCurrentResponse = false // Reset TTS trigger flag - CRITICAL for preventing duplicates
            audioRecorder.startRecording()
        }
    }
    
    private func cancelCurrentOperation() {
        // Only stop recording if explicitly canceling (user action)
        // Don't stop recording on view transitions - allow continuous operation
        if audioPlayer.isPlaying {
            audioPlayer.stop()
        }
        // Note: TTSService manages isGenerating internally
    }
    
    private func connectToRecordingStream() {
        print("🔌🔌🔌 TerminalSessionAgentView: Connecting to recording stream for session \(session.id)")
        print("🔌🔌🔌 TerminalSessionAgentView: Config - tunnelId=\(config.tunnelId), wsUrl=\(config.wsUrl)")
        
        recordingStreamClient.connect(config: config, sessionId: session.id) { message in
            
            // Process filtered assistant messages for TTS
            Task { @MainActor in
                print("📨📨📨 TerminalSessionAgentView: Received recording stream message: isComplete=\(message.isComplete?.description ?? "nil"), delta=\(message.delta?.count ?? 0) chars, text=\(message.text.count) chars")
                print("📨📨📨 TerminalSessionAgentView: message.text preview: '\(message.text.prefix(100))...'")
                
                // Save state immediately on each message (real-time persistence)
                // This ensures state is saved even if user navigates away
                self.saveTerminalState()
                
                // For assistant messages (delta), append to accumulated text
                // For completion (isComplete=true), use full text and trigger TTS immediately
                print("🔍🔍🔍 iOS: Checking isComplete: message.isComplete=\(message.isComplete?.description ?? "nil"), type=\(type(of: message.isComplete))")
                
                if let isComplete = message.isComplete, isComplete {
                    print("✅✅✅ iOS: isComplete=true detected! Processing completion...")
                    // Command completed - use full accumulated text from server
                    let finalText = message.text.isEmpty ? accumulatedText : message.text
                    let trimmedFinalText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("✅✅✅ iOS: finalText determined: \(finalText.count) chars (message.text: \(message.text.count), accumulatedText: \(accumulatedText.count))")
                    
                    // STRICT check: if we already processed this exact completion, ignore it completely
                    if trimmedFinalText == lastCompletionText && !trimmedFinalText.isEmpty {
                        print("⚠️⚠️⚠️ iOS: Duplicate completion signal detected for same text, ignoring completely")
                        return
                    }
                    
                    // STRICT check: if TTS is already generating or playing for this text, ignore
                    if ttsService.isGenerating || audioPlayer.isPlaying || audioPlayer.isPaused {
                        print("⚠️⚠️⚠️ iOS: TTS already in progress (generating=\(ttsService.isGenerating), playing=\(audioPlayer.isPlaying), paused=\(audioPlayer.isPaused)), ignoring completion")
                        // Still update the text for display, but don't trigger TTS
                        accumulatedText = finalText
                        agentResponseText = finalText
                        lastCompletionText = trimmedFinalText
                        return
                    }
                    
                    // STRICT check: if we already have TTS audio for this exact text, just play it (don't regenerate)
                    if lastTTSedText == trimmedFinalText && ttsService.lastAudioData != nil {
                        print("🔊🔊🔊 iOS: Already have TTS for this exact text, playing existing audio")
                        accumulatedText = finalText
                        agentResponseText = finalText
                        lastCompletionText = trimmedFinalText
                        // Play existing audio without regenerating
                        Task {
                            await ttsService.replay()
                        }
                        print("🔊🔊🔊 iOS: Playing existing TTS audio")
                        return
                    }
                    
                    // All checks passed - this is a new completion, process it
                    accumulatedText = finalText
                    agentResponseText = finalText
                    lastCompletionText = trimmedFinalText
                    
                    // Save state immediately after completion
                    self.saveTerminalState()
                    
                    print("✅✅✅ iOS: Command completed - received isComplete=true, final text (\(finalText.count) chars)")
                    print("✅✅✅ iOS: agentResponseText updated to: '\(agentResponseText.prefix(100))...'")
                    
                    // Trigger TTS only once for this completion
                    // Check if view is still active (user might have navigated away)
                    if !trimmedFinalText.isEmpty, let laptopConfig = settingsManager.laptopConfig {
                        print("✅✅✅ iOS: Triggering TTS for complete response (first time)")
                        lastTTSedText = trimmedFinalText
                        ttsTriggeredForCurrentResponse = true
                        
                        // Generate TTS even if view is in background - it will be available when user returns
                        generateTTS(for: finalText, config: laptopConfig)
                    } else {
                        print("⚠️⚠️⚠️ iOS: Command completed but no text available or no laptopConfig")
                        ttsTriggeredForCurrentResponse = true
                    }
                } else if message.isComplete == nil || message.isComplete == false {
                    // Delta message without isComplete field - only process if we haven't received completion yet
                    if ttsTriggeredForCurrentResponse {
                        print("⚠️⚠️⚠️ iOS: Received delta message after completion, ignoring to prevent duplicate")
                        return
                    }
                    print("⚠️⚠️⚠️ iOS: isComplete is nil! Message may not have isComplete field")
                } else if message.isComplete == false {
                    // Delta message (isComplete=false) - only process if we haven't received completion yet
                    if ttsTriggeredForCurrentResponse {
                        print("⚠️⚠️⚠️ iOS: Received delta message after completion, ignoring to prevent duplicate")
                        return
                    }
                    print("🔍🔍🔍 iOS: isComplete=false, treating as delta message")
                } else {
                    // Assistant message (delta) - only process if we haven't received completion yet
                    if ttsTriggeredForCurrentResponse {
                        print("⚠️⚠️⚠️ iOS: Received delta message after completion, ignoring to prevent duplicate")
                        return
                    }
                    
                    // Assistant message (delta) - append to accumulated text locally
                    // Update agentResponseText for UI display (status indicator), but don't trigger TTS yet
                    var updated = false
                    
                    // Try delta first, then fallback to text
                    if let delta = message.delta, !delta.isEmpty {
                        accumulatedText = accumulatedText.isEmpty ? delta : "\(accumulatedText)\n\n\(delta)"
                        agentResponseText = accumulatedText
                        updated = true
                        print("📝 Assistant delta: \(delta.count) chars, total: \(accumulatedText.count) chars")
                    } else if !message.text.isEmpty {
                        // Use full text if delta is not available
                        if accumulatedText.isEmpty {
                            accumulatedText = message.text
                        } else if message.text.contains(accumulatedText) {
                            accumulatedText = message.text
                        } else {
                            accumulatedText = "\(accumulatedText)\n\n\(message.text)"
                        }
                        agentResponseText = accumulatedText
                        updated = true
                        print("📝 Assistant text: \(message.text.count) chars, total: \(accumulatedText.count) chars")
                    }
                    
                    if !updated {
                        print("⚠️ No text or delta in assistant message - skipping")
                    } else {
                        // Save state immediately after delta update (real-time persistence)
                        self.saveTerminalState()
                    }
                    // Don't trigger TTS yet - wait for completion signal
                }
            }
        }
    }
    
    // Send transcribed command to this specific terminal session
    private func sendCommandToSession(_ text: String) {
        let apiClient = APIClient(config: config)
        
        Task {
            do {
                // For headless terminals (cursor/claude), use executeCommand
                // This will send the command to the terminal's CLI tool
                if session.terminalType.isHeadless {
                    _ = try await apiClient.executeCommand(sessionId: session.id, command: text)
                    print("✅ Command sent to terminal session \(session.id): \(text)")
                } else {
                    // For regular terminals, we could use executeAgentCommand with sessionId
                    // But for now, just use executeCommand
                    _ = try await apiClient.executeCommand(sessionId: session.id, command: text)
                    print("✅ Command sent to terminal session \(session.id): \(text)")
                }
            } catch {
                print("❌ Error sending command to session: \(error)")
                await MainActor.run {
                    agentResponseText = "Error: \(error.localizedDescription)" // Update local response, not global
                }
            }
        }
    }
    
    // Save terminal state to UserDefaults
    private func saveTerminalState() {
        let stateKey = "terminal_state_\(session.id)"
        let state: [String: Any] = [
            "agentResponseText": agentResponseText,
            "accumulatedText": accumulatedText,
            "lastTTSedText": lastTTSedText,
            "recognizedText": audioRecorder.recognizedText,
            "lastTTSAudioData": ttsService.lastAudioData?.base64EncodedString() ?? ""
        ]
        UserDefaults.standard.set(state, forKey: stateKey)
        print("💾 Saved terminal state for session \(session.id)")
    }

    // Load terminal state from UserDefaults
    private func loadTerminalState() {
        let stateKey = "terminal_state_\(session.id)"
        if let state = UserDefaults.standard.dictionary(forKey: stateKey) {
            agentResponseText = state["agentResponseText"] as? String ?? ""
            accumulatedText = state["accumulatedText"] as? String ?? ""
            lastTTSedText = state["lastTTSedText"] as? String ?? ""
            audioRecorder.recognizedText = state["recognizedText"] as? String ?? ""

            if let audioDataString = state["lastTTSAudioData"] as? String,
               !audioDataString.isEmpty,
               let audioData = Data(base64Encoded: audioDataString) {
                ttsService.lastAudioData = audioData
            }
            print("📂 Loaded terminal state for session \(session.id)")
        }
    }

    // Clear terminal state (called when terminal is closed on backend)
    private func clearTerminalState() {
        let stateKey = "terminal_state_\(session.id)"
        UserDefaults.standard.removeObject(forKey: stateKey)
        agentResponseText = ""
        accumulatedText = ""
        lastTTSedText = ""
        audioRecorder.recognizedText = ""
        ttsService.reset() // Reset TTS service state
        print("🗑️ Cleared terminal state for session \(session.id)")
    }
    
    private func generateTTS(for text: String, config: TunnelConfig) {
        // Check if text is valid
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            print("🔇🔇🔇 generateTTS: Empty text, skipping")
            return
        }

        // Check if we should generate TTS
        if !ttsService.shouldGenerateTTS(
            newText: trimmed,
            lastText: lastTTSedText,
            isPlaying: audioPlayer.isPlaying
        ) {
            print("⚠️⚠️⚠️ generateTTS: Skipping duplicate TTS")
            // If we have existing audio for same text, play it
            if lastTTSedText == trimmed && ttsService.lastAudioData != nil {
                print("🔊🔊🔊 generateTTS: Using existing TTS audio for same text")
                Task {
                    await ttsService.replay()
                }
            }
            return
        }

        print("🔊🔊🔊 generateTTS: Starting TTS generation for text (\(trimmed.count) chars)")
        print("🔊🔊🔊 generateTTS: Text preview: '\(trimmed.prefix(150))...'")

        Task {
            do {
                // Use TTSService to synthesize and play
                _ = try await ttsService.synthesizeAndPlay(
                    text: trimmed,
                    config: config,
                    speed: settingsManager.ttsSpeed,
                    language: settingsManager.transcriptionLanguage.rawValue,
                    cleaningFunction: nil
                )

                print("✅ generateTTS: TTS synthesis and playback completed")

            } catch {
                print("❌ TTS error: \(error)")
                print("❌ TTS error details: \(error.localizedDescription)")
            }
        }
    }
    
}
