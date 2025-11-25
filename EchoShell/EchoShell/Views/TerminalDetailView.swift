//
//  TerminalDetailView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Detailed view for a single terminal session with two modes: PTY and Agent
//

import SwiftUI
import SwiftTerm

enum TerminalViewMode {
    case pty
    case agent
}

struct TerminalDetailView: View {
    let session: TerminalSession
    let config: TunnelConfig
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) var dismiss
    
    @State private var viewMode: TerminalViewMode = .pty
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
        NavigationStack {
            VStack(spacing: 0) {
                // Mode selector (only show for AI-powered terminals)
                if session.terminalType == .cursorCLI || session.terminalType == .claudeCLI {
                    Picker("View Mode", selection: $viewMode) {
                        Label("Terminal", systemImage: "terminal")
                            .tag(TerminalViewMode.pty)
                        Label("Agent", systemImage: "brain.head.profile")
                            .tag(TerminalViewMode.agent)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                
                // Content based on selected mode
                if viewMode == .pty {
                    ptyTerminalView
                } else {
                    agentView
                }
            }
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    // Header with BACK button and connection status
                    // This MUST override the parent's header completely
                    RecordingHeaderView(
                        connectionState: connectionState,
                        leftButtonType: .back(action: {
                            print("🔙 Back button tapped - dismissing TerminalDetailView")
                            dismiss()
                        })
                    )
                    .background(Color(.systemBackground))
                    .id("TerminalDetailHeader-\(session.id)") // Force SwiftUI to treat this as a new view
                    
                    // Session title and working directory
                    VStack(spacing: 2) {
                        Text(session.name ?? session.id)
                            .font(.system(size: 15, weight: .semibold))
                        Text(session.workingDir)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                }
            }
        }
        .onAppear {
            // Set initial view mode
            viewMode = initialViewMode
            // Start health checker
            laptopHealthChecker.start(config: config)
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
            // Connect WebSocket for streaming
            wsClient.connect(config: config, sessionId: session.id) { text in
                let cleanedText = self.removeZshPercentSymbol(text)
                
                if let coordinator = self.terminalCoordinator {
                    coordinator.feed(cleanedText)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        coordinator.scrollToBottom()
                    }
                } else {
                    self.pendingData.append(cleanedText)
                }
            }
            
            // Load history
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Record button
            recordButtonView
            
            // Status indicator
            statusIndicatorView
            
            // Result display
            resultDisplayView
        }
        .onAppear {
            audioRecorder.configure(with: settingsManager)
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
        .padding(.top, 40)
    }
    
    private var statusIndicatorView: some View {
        Group {
            let state = getCurrentState()
            
            if state == .idle {
                Text(state.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
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
                            if state.isActive {
                                pulseAnimation = true
                            }
                        }
                        .onChange(of: state) { oldValue, newValue in
                            if newValue.isActive {
                                pulseAnimation = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    pulseAnimation = true
                                }
                            } else {
                                pulseAnimation = false
                            }
                        }
                    
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
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if !audioRecorder.recognizedText.isEmpty {
                    Text(audioRecorder.recognizedText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding()
                } else if !settingsManager.lastTerminalOutput.isEmpty {
                    Text(settingsManager.lastTerminalOutput)
                        .font(.body)
                        .foregroundColor(.primary)
                .textSelection(.enabled)
                        .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func getCurrentState() -> RecordingState {
        if audioRecorder.isRecording {
            return .recording
        } else if audioRecorder.isTranscribing {
            return .transcribing
        } else if audioPlayer.isPlaying {
            return .playingTTS
        } else if isGeneratingTTS {
            return .generatingTTS
        } else if !audioRecorder.recognizedText.isEmpty && settingsManager.lastTerminalOutput.isEmpty {
            return .waitingForAgent
        } else {
            return .idle
        }
    }
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        } else {
            cancelCurrentOperation()
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
        recordingStreamClient.connect(config: config, sessionId: session.id) { message in
            // Process filtered assistant messages for TTS
            Task { @MainActor in
                // Update lastTerminalOutput with message text
                settingsManager.lastTerminalOutput = message.text
                
                // Generate TTS for the response
                if let laptopConfig = settingsManager.laptopConfig {
                    generateTTS(for: message.text, config: laptopConfig)
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
                    settingsManager.lastTerminalOutput = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func generateTTS(for text: String, config: TunnelConfig) {
        isGeneratingTTS = true
        
        Task {
            do {
                guard let ttsEndpoint = settingsManager.providerEndpoints?.tts else {
                    print("❌ TTS endpoint not available")
                    isGeneratingTTS = false
                    return
                }
                
                let ttsHandler = LocalTTSHandler(laptopAuthKey: config.authKey, endpoint: ttsEndpoint)
                let language = settingsManager.transcriptionLanguage.rawValue
                let speed = settingsManager.ttsSpeed
                let voice = "alloy" // Default voice
                
                let audioData = try await ttsHandler.synthesize(text: text, voice: voice, speed: speed, language: language)
                
                await MainActor.run {
                    isGeneratingTTS = false
                    lastTTSAudioData = audioData
                    
                    if audioPlayer.isPlaying {
                        audioPlayer.stop()
                    }
                    
                    do {
                        try audioPlayer.play(audioData: audioData)
                    } catch {
                        print("❌ Failed to play TTS: \(error)")
                    }
                }
            } catch {
                print("❌ TTS error: \(error)")
                await MainActor.run {
                    isGeneratingTTS = false
                }
            }
        }
    }
}
