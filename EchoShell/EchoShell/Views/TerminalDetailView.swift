//
//  TerminalDetailView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Detailed view for a single terminal session with two modes: PTY and Agent
//

import SwiftUI
import SwiftTerm

// TerminalViewMode is now defined in UnifiedHeaderView.swift

struct TerminalDetailView: View {
    let session: TerminalSession
    let config: TunnelConfig
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var navigationStateManager: NavigationStateManager
    @Environment(\.dismiss) var dismiss
    
    @State private var viewMode: TerminalViewMode = .agent
    @StateObject private var wsClient = WebSocketClient()
    @State private var terminalCoordinator: SwiftTermTerminalView.Coordinator?
    @State private var pendingData: [String] = []
    
    // Determine initial view mode based on terminal type
    private var initialViewMode: TerminalViewMode {
        // For AI-powered terminals (cursor/claude), default to agent mode
        // For regular terminals, use PTY mode
        if session.terminalType == .cursorCLI || session.terminalType == .claudeCLI {
            return .agent
        }
        return .pty
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
        .onChange(of: viewMode) { oldValue, newValue in
            // Notify header about mode change
            let modeString = newValue == .agent ? "agent" : "pty"
            NotificationCenter.default.post(
                name: NSNotification.Name("TerminalViewModeChanged"),
                object: nil,
                userInfo: ["viewMode": modeString]
            )
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Set initial view mode
            viewMode = initialViewMode
            // Notify header about initial mode
            let modeString = viewMode == .agent ? "agent" : "pty"
            NotificationCenter.default.post(
                name: NSNotification.Name("TerminalViewModeChanged"),
                object: nil,
                userInfo: ["viewMode": modeString]
            )
            // Start health checker
            laptopHealthChecker.start(config: config)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleTerminalViewMode"))) { notification in
            if let modeString = notification.userInfo?["viewMode"] as? String {
                viewMode = modeString == "agent" ? .agent : .pty
            }
        }
        .onDisappear {
            laptopHealthChecker.stop()
        }
    }
    
    // PTY Terminal View (for regular terminals or PTY mode of AI terminals)
    private var ptyTerminalView: some View {
        VStack(spacing: 0) {
            SwiftTermTerminalView(onInput: { input in
                sendInput(input)
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
                
                let cleanedText = self.removeZshPercentSymbol(text)
                
                // Skip if cleaned text is empty
                guard !cleanedText.isEmpty else { return }
                
                if let coordinator = self.terminalCoordinator {
                    coordinator.feed(cleanedText)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        coordinator.scrollToBottom()
                    }
                } else {
                    self.pendingData.append(cleanedText)
                }
            }
            
            // Load history after a delay to ensure terminal is ready
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await loadHistory()
            }
        }
        .onDisappear {
            wsClient.disconnect()
        }
    }
    
    // Agent View (for AI-powered terminals in agent mode)
    private var agentView: some View {
        TerminalSessionAgentView(session: session, config: config)
            .environmentObject(settingsManager)
    }
    
    private func loadHistory() async {
        let apiClient = APIClient(config: config)
        do {
            let history = try await apiClient.getHistory(sessionId: session.id)
            
            await MainActor.run {
                if let coordinator = self.terminalCoordinator {
                    if !history.isEmpty {
                        let cleanedHistory = self.removeZshPercentSymbol(history)
                        coordinator.feed(cleanedHistory)
                        print("✅ Loaded terminal history: \(history.count) characters")
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            coordinator.scrollToBottom()
                        }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            coordinator.scrollToBottom()
                        }
                    }
                    coordinator.focus()
                }
            }
        } catch {
            print("❌ Error loading history: \(error)")
            await MainActor.run {
                if let coordinator = self.terminalCoordinator {
                    coordinator.focus()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        coordinator.scrollToBottom()
                    }
                }
            }
        }
    }
    
    private func removeZshPercentSymbol(_ text: String) -> String {
        var cleaned = text
        
        cleaned = cleaned.replacingOccurrences(of: "History", with: "")
        cleaned = cleaned.replacingOccurrences(of: "Load Full History", with: "")
        
        cleaned = cleaned.replacingOccurrences(
            of: "\\u{001B}\\[[0-9;]*m\\u{001B}\\[7m%\\u{001B}\\[27m\\u{001B}\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
        
        cleaned = cleaned.replacingOccurrences(
            of: "\\u{001B}\\[7m%\\u{001B}\\[27m",
            with: "",
            options: .regularExpression
        )
        
        cleaned = cleaned.replacingOccurrences(
            of: "\\u{001B}\\[[0-9;]*m%\\u{001B}\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
        
        cleaned = cleaned.replacingOccurrences(of: " %", with: " ", options: [])
        cleaned = cleaned.replacingOccurrences(of: "% ", with: " ", options: [])
        cleaned = cleaned.replacingOccurrences(of: "%(?=\\r|\\n)", with: "", options: .regularExpression)
        
        while cleaned.hasSuffix("%") {
            cleaned = String(cleaned.dropLast())
        }
        
        cleaned = cleaned.replacingOccurrences(of: "([~→])%", with: "$1", options: .regularExpression)
        
        return cleaned
    }
    
    private func sendInput(_ input: String) {
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
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var isGeneratingTTS = false
    @State private var pulseAnimation: Bool = false
    @State private var lastTTSAudioData: Data? = nil
    @State private var transcriptionObserver: NSObjectProtocol?
    @State private var accumulatedText: String = "" // Accumulate assistant messages until completion
    @State private var lastTTSedText: String = "" // Track what text we've already generated TTS for
    @State private var ttsTriggeredForCurrentResponse: Bool = false // Track if TTS was triggered for current response
    @State private var agentResponseText: String = "" // Local storage for agent response (separate from global settingsManager)
    
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
            
            // Listen for transcription completion to send command to this session
            transcriptionObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("TranscriptionCompleted"),
                object: nil,
                queue: .main
            ) { notification in
                guard let text = notification.userInfo?["text"] as? String else { return }
                sendCommandToSession(text)
            }
        }
        .onDisappear {
            recordingStreamClient.disconnect()
            // Re-enable automatic command sending when leaving this view
            audioRecorder.autoSendCommand = true
            // Remove transcription observer
            if let observer = transcriptionObserver {
                NotificationCenter.default.removeObserver(observer)
                transcriptionObserver = nil
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
                        .onChange(of: isGeneratingTTS) { oldValue, newValue in
                            // When isGeneratingTTS changes, update pulse animation
                            if newValue && !pulseAnimation {
                                print("🔄 isGeneratingTTS changed to true, starting pulse animation")
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
        // Use local agentResponseText instead of global settingsManager.lastTerminalOutput
        Group {
            let shouldShow = !audioRecorder.recognizedText.isEmpty || !agentResponseText.isEmpty
            
            if shouldShow && !audioRecorder.isTranscribing {
                VStack(alignment: .leading, spacing: 16) {
                    // Display text based on what's available
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
                    
                    // Audio control buttons
                    HStack {
                        Spacer()
                        
                        // Stop button (show during playback)
                        if audioPlayer.isPlaying {
                            Button(action: {
                                audioPlayer.pause()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "pause.fill")
                                        .font(.caption)
                                    Text("Pause")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.orange.opacity(0.1))
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
                        // Replay button (show after TTS finished playing)
                        else if lastTTSAudioData != nil && getCurrentState() == .idle {
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
    
    // Determine current state - simplified logic
    private func getCurrentState() -> RecordingState {
        // Priority order: recording > transcribing > playing > generating > waiting > idle
        if audioRecorder.isRecording {
            return .recording
        } else if audioRecorder.isTranscribing {
            return .transcribing
        } else if audioPlayer.isPlaying {
            return .playingTTS
        } else if isGeneratingTTS {
            print("🔍🔍🔍 getCurrentState: isGeneratingTTS=true, returning .generatingTTS")
            return .generatingTTS
        } else if !audioRecorder.recognizedText.isEmpty && agentResponseText.isEmpty {
            // We have a question but no answer yet
            print("🔍🔍🔍 getCurrentState: recognizedText=\(audioRecorder.recognizedText.count) chars, agentResponseText empty, returning .waitingForAgent")
            return .waitingForAgent
        } else if !agentResponseText.isEmpty {
            // We have an answer - check if TTS is done
            print("🔍🔍🔍 getCurrentState: agentResponseText=\(agentResponseText.count) chars, lastTTSAudioData=\(lastTTSAudioData != nil), ttsTriggered=\(ttsTriggeredForCurrentResponse)")
            if lastTTSAudioData != nil {
                // TTS was generated, we're done
                print("🔍🔍🔍 getCurrentState: TTS audio available, returning .idle")
                return .idle
            } else if ttsTriggeredForCurrentResponse {
                // TTS was triggered but not completed yet - still generating
                print("🔍🔍🔍 getCurrentState: TTS triggered but not completed, returning .generatingTTS")
                return .generatingTTS
            } else {
                // Answer received but TTS not triggered yet - waiting for isComplete message
                print("🔍🔍🔍 getCurrentState: Answer received but TTS not triggered, returning .waitingForAgent")
                return .waitingForAgent
            }
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
            lastTTSAudioData = nil // Reset TTS audio data
            ttsTriggeredForCurrentResponse = false // Reset TTS trigger flag
            audioRecorder.startRecording()
        }
    }
    
    private func cancelCurrentOperation() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        }
        if audioPlayer.isPlaying {
            audioPlayer.stop()
        }
        isGeneratingTTS = false
    }
    
    private func connectToRecordingStream() {
        print("🔌🔌🔌 TerminalSessionAgentView: Connecting to recording stream for session \(session.id)")
        print("🔌🔌🔌 TerminalSessionAgentView: Config - tunnelId=\(config.tunnelId), wsUrl=\(config.wsUrl)")
        
        recordingStreamClient.connect(config: config, sessionId: session.id) { message in
            // Process filtered assistant messages for TTS
            Task { @MainActor in
                print("📨📨📨 TerminalSessionAgentView: Received recording stream message: isComplete=\(message.isComplete?.description ?? "nil"), delta=\(message.delta?.count ?? 0) chars, text=\(message.text.count) chars")
                print("📨📨📨 TerminalSessionAgentView: message.text preview: '\(message.text.prefix(100))...'")
                
                // For assistant messages (delta), append to accumulated text
                // For completion (isComplete=true), use full text and trigger TTS immediately
                print("🔍🔍🔍 iOS: Checking isComplete: message.isComplete=\(message.isComplete?.description ?? "nil"), type=\(type(of: message.isComplete))")
                
                if let isComplete = message.isComplete, isComplete {
                    print("✅✅✅ iOS: isComplete=true detected! Processing completion...")
                    // Command completed - use full accumulated text from server
                    let finalText = message.text.isEmpty ? accumulatedText : message.text
                    print("✅✅✅ iOS: finalText determined: \(finalText.count) chars (message.text: \(message.text.count), accumulatedText: \(accumulatedText.count))")
                    
                    accumulatedText = finalText
                    agentResponseText = finalText
                    print("✅✅✅ iOS: Command completed - received isComplete=true, final text (\(finalText.count) chars)")
                    print("✅✅✅ iOS: agentResponseText updated to: '\(agentResponseText.prefix(100))...'")
                    print("✅✅✅ iOS: Current state before TTS: \(getCurrentState())")
                    
                    // Always trigger TTS when command is completed
                    if !finalText.isEmpty, let laptopConfig = settingsManager.laptopConfig {
                        print("✅✅✅ iOS: Triggering TTS for complete response")
                        lastTTSedText = finalText
                        ttsTriggeredForCurrentResponse = true
                        // Don't set isGeneratingTTS here - let generateTTS set it to avoid race condition
                        print("✅✅✅ iOS: Calling generateTTS...")
                        generateTTS(for: finalText, config: laptopConfig)
                    } else {
                        print("⚠️⚠️⚠️ iOS: Command completed but no text available or no laptopConfig")
                        print("⚠️⚠️⚠️ iOS: finalText.isEmpty=\(finalText.isEmpty), laptopConfig=\(settingsManager.laptopConfig != nil)")
                        ttsTriggeredForCurrentResponse = true // Mark as triggered even if empty
                    }
                } else if message.isComplete == nil {
                    print("⚠️⚠️⚠️ iOS: isComplete is nil! Message may not have isComplete field")
                } else if message.isComplete == false {
                    print("🔍🔍🔍 iOS: isComplete=false, treating as delta message")
                } else {
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
    
    private func generateTTS(for text: String, config: TunnelConfig) {
        // Prevent duplicate TTS generation
        if isGeneratingTTS {
            print("⚠️⚠️⚠️ generateTTS: Already generating, skipping duplicate")
            return
        }
        
        // Check if text is valid
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            print("🔇🔇🔇 generateTTS: Empty text, skipping")
            return
        }
        
        // Check if we already have TTS for this exact text
        if lastTTSedText == trimmed && lastTTSAudioData != nil {
            print("🔊🔊🔊 generateTTS: Using existing TTS audio for same text")
            if !audioPlayer.isPlaying, let audioData = lastTTSAudioData {
                do {
                    try audioPlayer.play(audioData: audioData)
                    print("🔊🔊🔊 generateTTS: Playing existing audio")
                    return
                } catch {
                    print("❌❌❌ generateTTS: Failed to play existing audio: \(error), will regenerate")
                }
            } else {
                print("⚠️⚠️⚠️ generateTTS: Audio already playing or no data, skipping")
                return
            }
        }
        
        print("🔊🔊🔊 generateTTS: Starting TTS generation for text (\(trimmed.count) chars)")
        print("🔊🔊🔊 generateTTS: Text preview: '\(trimmed.prefix(150))...'")
        isGeneratingTTS = true
        
        Task {
            do {
                // Clean text for TTS (remove ANSI codes, etc.)
                let cleanedText = cleanTerminalOutputForTTS(trimmed)
                
                // Skip if cleaned text is empty
                if cleanedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                    print("⚠️ generateTTS: Cleaned text is empty, skipping TTS")
                    await MainActor.run {
                    isGeneratingTTS = false
                    }
                    return
                }
                
                print("🔊 generateTTS: Cleaned text (\(cleanedText.count) chars) at \(settingsManager.ttsSpeed)x speed")
                
                // Build TTS endpoint from laptop config (proxy endpoint via tunnel)
                let ttsEndpoint = "\(config.apiBaseUrl)/proxy/tts/synthesize"
                let ttsHandler = LocalTTSHandler(laptopAuthKey: config.authKey, endpoint: ttsEndpoint)
                let language = settingsManager.transcriptionLanguage.rawValue
                let speed = settingsManager.ttsSpeed
                let voice = "alloy" // Default voice
                
                print("🔊 generateTTS: Calling TTS handler with endpoint: \(ttsEndpoint)")
                let audioData = try await ttsHandler.synthesize(text: cleanedText, voice: voice, speed: speed, language: language)
                
                print("✅ generateTTS: TTS synthesis completed, audio data size: \(audioData.count) bytes")
                
                await MainActor.run {
                    isGeneratingTTS = false
                    lastTTSAudioData = audioData
                    
                    if audioPlayer.isPlaying {
                        audioPlayer.stop()
                    }
                    
                    do {
                        try audioPlayer.play(audioData: audioData)
                        print("🔊 generateTTS: TTS playback started")
                    } catch {
                        print("❌ Failed to play TTS: \(error)")
                    }
                }
            } catch {
                print("❌ TTS error: \(error)")
                print("❌ TTS error details: \(error.localizedDescription)")
                await MainActor.run {
                    isGeneratingTTS = false
                }
            }
        }
    }
    
    // Clean terminal output for TTS (remove ANSI codes, etc.)
    private func cleanTerminalOutputForTTS(_ text: String) -> String {
        var cleaned = text
        
        // Remove ANSI escape sequences
        cleaned = cleaned.replacingOccurrences(
            of: #"\u{001B}\[[0-9;]*m"#,
            with: "",
            options: .regularExpression
        )
        
        // Remove other control characters but keep newlines and tabs
        cleaned = cleaned.replacingOccurrences(
            of: #"[\u{0000}-\u{0008}\u{000B}\u{000C}\u{000E}-\u{001F}\u{007F}-\u{009F}]"#,
            with: "",
            options: .regularExpression
        )
        
        // Normalize whitespace (multiple spaces/newlines to single)
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
