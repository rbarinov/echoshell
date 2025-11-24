//
//  ContentView.swift
//  EchoShell Watch App
//
//  Created by Roman Barinov on 2025.11.20.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audioRecorder: AudioRecorder
    @StateObject private var settingsManager = WatchSettingsManager()
    @StateObject private var terminalViewModel = TerminalViewModel()
    @StateObject private var audioPlayer = AudioPlayer()
    @StateObject private var wsClient = WebSocketClient()
    @StateObject private var recordingStreamClient = RecordingStreamClient()
    @ObservedObject private var watchConnectivity = WatchConnectivityManager.shared
    
    @State private var commandResult: String = ""
    @State private var isProcessingCommand = false
    @State private var terminalOutput: String = ""
    @State private var recordingStreamSessionId: String?
    @State private var ttsTimer: Timer? = nil
    @State private var lastTTSOutput: String = ""
    @State private var isSessionPickerPresented = false
    
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
            commandResult = ""
            audioRecorder.startRecording()
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Top bar: connection status and mode toggle
                topBarView
                
                // Session selector (if laptop connected)
                if settingsManager.laptopConfig != nil {
                    sessionSelectorView
                }
                
                // Main Record Button
                recordButtonView
                
                // Status text
                statusTextView
                
                // Transcription indicator
                if audioRecorder.isTranscribing {
                    VStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Transcribing...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                // Command result display
                if !commandResult.isEmpty || !terminalOutput.isEmpty {
                    resultDisplayView
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear {
            // Load settings from WatchConnectivityManager
            loadSettings()
            
            // Load terminal sessions if laptop connected
            if let config = settingsManager.laptopConfig {
                Task {
                    // Request ephemeral keys if needed
                    if settingsManager.shouldRefreshKeys() || settingsManager.ephemeralKeys == nil {
                        await requestEphemeralKeys(config: config)
                    }
                    
                    await terminalViewModel.loadSessions(config: config)
                    // Set default session if none selected
                    if settingsManager.selectedSessionId == nil && !terminalViewModel.sessions.isEmpty {
                        settingsManager.selectedSessionId = terminalViewModel.sessions.first?.id
                    }
                    
                    // Connect WebSocket for direct mode
                    if settingsManager.commandMode == .direct,
                       let sessionId = settingsManager.selectedSessionId,
                       let session = terminalViewModel.sessions.first(where: { $0.id == sessionId }),
                       session.terminalType == .cursorAgent {
                        connectToTerminalStream(config: config, sessionId: sessionId)
                        connectToRecordingStream(config: config, sessionId: sessionId)
                    }
                }
            }
        }
        .onChange(of: watchConnectivity.isPhoneConnected) { _, _ in
            loadSettings()
                    }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SettingsUpdated"))) { _ in
            loadSettings()
        }
        .onChange(of: audioRecorder.isTranscribing) { oldValue, newValue in
            // When transcription completes (isTranscribing becomes false), execute command
            if oldValue == true && newValue == false && !audioRecorder.recognizedText.isEmpty {
                Task {
                    if settingsManager.commandMode == .direct && isCursorAgentTerminal {
                        // Direct mode: send command via WebSocket
                        sendCommandToTerminal(audioRecorder.recognizedText)
                    } else if settingsManager.commandMode == .agent {
                        // Agent mode: use agent endpoint
                        await executeCommand(audioRecorder.recognizedText)
                    }
                }
            }
        }
        .onChange(of: settingsManager.selectedSessionId) { oldValue, newValue in
            // Reconnect WebSocket when session changes
            if settingsManager.commandMode == .direct,
               let config = settingsManager.laptopConfig,
               let sessionId = newValue,
               let session = terminalViewModel.sessions.first(where: { $0.id == sessionId }),
               session.terminalType == .cursorAgent {
                connectToTerminalStream(config: config, sessionId: sessionId)
                connectToRecordingStream(config: config, sessionId: sessionId)
            }
        }
        .onChange(of: settingsManager.commandMode) { oldValue, newValue in
            // Reconnect WebSocket when mode changes
            if newValue == .direct,
               let config = settingsManager.laptopConfig,
               let sessionId = settingsManager.selectedSessionId,
               let session = terminalViewModel.sessions.first(where: { $0.id == sessionId }),
               session.terminalType == .cursorAgent {
                connectToTerminalStream(config: config, sessionId: sessionId)
                connectToRecordingStream(config: config, sessionId: sessionId)
            } else {
                wsClient.disconnect()
                recordingStreamClient.disconnect()
                recordingStreamSessionId = nil
                terminalOutput = ""
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TTSPlaybackFinished"))) { _ in
            // Process queue after playback
        }
        .onDisappear {
            recordingStreamClient.disconnect()
            recordingStreamSessionId = nil
        }
    }
    
    private func loadSettings() {
        // Settings are already loaded in WatchSettingsManager from UserDefaults
        // Update AudioRecorder with new settings
        audioRecorder.updateTranscriptionService()
        
        // Refresh terminal sessions if needed
        if let config = settingsManager.laptopConfig {
            Task {
                await terminalViewModel.refreshSessions(config: config)
            }
        }
    }
    
    private var topBarView: some View {
        HStack {
            if settingsManager.laptopConfig != nil {
                // Command mode toggle (compact for Watch)
                HStack(spacing: 6) {
                    Button(action: {
                        settingsManager.commandMode = .agent
                    }) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(settingsManager.commandMode == .agent ? .white : .secondary)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(settingsManager.commandMode == .agent ? Color.blue : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        settingsManager.commandMode = .direct
                    }) {
                        Image(systemName: "terminal")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(settingsManager.commandMode == .direct ? .white : .secondary)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(settingsManager.commandMode == .direct ? Color.blue : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                }
                
                Spacer()
            
            // Connection status
            Image(systemName: settingsManager.laptopConfig != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(settingsManager.laptopConfig != nil ? .green : .red)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 4)
    }
    
    private var sessionSelectorView: some View {
        VStack(spacing: 4) {
            if terminalViewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                let validSessions = validSessionsForCurrentMode
                
                if validSessions.isEmpty {
                    if settingsManager.commandMode == .direct {
                        createCursorAgentTerminalView
                    } else {
                        VStack(spacing: 4) {
                            Text("No sessions available")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Button("Create Session") {
                                createRegularSession()
                            }
                            .font(.caption2)
                        }
                    }
                } else {
                    Button(action: {
                        isSessionPickerPresented = true
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Session")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(selectedSession?.name ?? selectedSession?.id ?? "Select session")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $isSessionPickerPresented) {
                        SessionPickerSheet(
                            sessions: validSessions,
                            selectedId: settingsManager.selectedSessionId,
                            onSelect: { sessionId in
                                settingsManager.selectedSessionId = sessionId
                            },
                            onCreateCursorAgent: settingsManager.commandMode == .direct ? createCursorAgentSession : nil,
                            onCreateRegular: settingsManager.commandMode == .agent ? createRegularSession : nil
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var validSessionsForCurrentMode: [TerminalSession] {
        settingsManager.commandMode == .direct ? availableSessionsForDirectMode : terminalViewModel.sessions
    }
    
    private func createCursorAgentSession() {
        Task {
            guard let config = settingsManager.laptopConfig else { return }
            await terminalViewModel.createNewSession(
                config: config,
                terminalType: .cursorAgent
            )
            if let newSession = terminalViewModel.sessions.last {
                await MainActor.run {
                    settingsManager.selectedSessionId = newSession.id
                }
            }
        }
    }
    
    private func createRegularSession() {
        Task {
            guard let config = settingsManager.laptopConfig else { return }
            await terminalViewModel.createNewSession(
                config: config,
                terminalType: .regular
            )
            if let newSession = terminalViewModel.sessions.last {
                await MainActor.run {
                    settingsManager.selectedSessionId = newSession.id
                }
            }
        }
    }
    
    private var createCursorAgentTerminalView: some View {
        Button(action: {
            createCursorAgentSession()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 10))
                Text("Create Cursor Agent")
                    .font(.caption2)
            }
            .foregroundColor(.blue)
        }
    }
    
    private var recordButtonView: some View {
                Button(action: {
                    toggleRecording()
                }) {
                    ZStack {
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
                    .frame(width: 80, height: 80)
                            .shadow(color: audioRecorder.isRecording 
                                ? Color.red.opacity(0.6) 
                                : Color.blue.opacity(0.5), 
                        radius: 12, x: 0, y: 6)
                        
                        Circle()
                            .fill(Color.white.opacity(0.2))
                    .frame(width: 70, height: 70)
                        
                        Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white)
                            .symbolEffect(.pulse, isActive: audioRecorder.isRecording)
                    }
                }
                .buttonStyle(.plain)
        .disabled(audioRecorder.isTranscribing || settingsManager.laptopConfig == nil || 
                 (settingsManager.commandMode == .direct && !isCursorAgentTerminal))
                .scaleEffect(audioRecorder.isRecording ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: audioRecorder.isRecording)
    }
    
    private var statusTextView: some View {
        Group {
            if audioRecorder.isRecording {
                Text("Recording...")
                    .font(.caption)
                    .foregroundColor(.red)
            } else if settingsManager.laptopConfig == nil {
                Text("Setup on iPhone")
                    .font(.caption2)
                    .foregroundColor(.orange)
            } else if settingsManager.commandMode == .direct && !isCursorAgentTerminal {
                Text("Select Cursor Agent")
                    .font(.caption2)
                    .foregroundColor(.orange)
            } else {
                Text("Tap to Record")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var resultDisplayView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Result")
                            .font(.caption2)
                            .foregroundColor(.secondary)
            Text(settingsManager.commandMode == .direct ? terminalOutput : commandResult)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(5)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
        }
        .padding(.horizontal, 4)
    }
    
    // Execute command based on mode
    private func executeCommand(_ command: String) async {
        guard let config = settingsManager.laptopConfig else { return }
        guard let sessionId = settingsManager.selectedSessionId ?? terminalViewModel.sessions.first?.id else {
            // No session available, try to create one
            if settingsManager.commandMode == .direct {
                await terminalViewModel.createNewSession(config: config, terminalType: .cursorAgent)
                if let newSession = terminalViewModel.sessions.last {
                    settingsManager.selectedSessionId = newSession.id
                    await executeCommand(command)
                                    }
            } else {
                await terminalViewModel.createNewSession(config: config, terminalType: .regular)
                if let newSession = terminalViewModel.sessions.last {
                    settingsManager.selectedSessionId = newSession.id
                    await executeCommand(command)
                }
            }
            return
        }
        
        isProcessingCommand = true
        defer { isProcessingCommand = false }
        
        do {
            if terminalViewModel.apiClient == nil {
                terminalViewModel.apiClient = APIClient(config: config)
            }
            
            if settingsManager.commandMode == .agent {
                // Agent mode: use agent endpoint
                let result = try await terminalViewModel.apiClient!.executeAgentCommand(
                    sessionId: sessionId,
                    command: command
                )
                await MainActor.run {
                    commandResult = result
                }
                // Trigger TTS for result
                await playTTS(for: result)
            } else {
                // Direct mode: commands are sent via WebSocket in sendCommandToTerminal
                // This should not be called in direct mode, but handle it gracefully
                if isCursorAgentTerminal {
                    // In direct mode, commands are sent via WebSocket
                    // Output processing and TTS are handled by WebSocket callback
                    print("⚠️ executeCommand called in direct mode - should use WebSocket")
                }
            }
        } catch {
            await MainActor.run {
                commandResult = "Error: \(error.localizedDescription)"
            }
                                        }
                                    }
                                    
    // Request ephemeral keys from laptop
    private func requestEphemeralKeys(config: TunnelConfig) async {
        do {
            let apiClient = APIClient(config: config)
            let keyResponse = try await apiClient.requestKeys()
            
            await MainActor.run {
                settingsManager.ephemeralKeys = keyResponse.keys
                settingsManager.keyExpiresAt = Date(timeIntervalSince1970: TimeInterval(keyResponse.expiresAt))
            }
            
            print("✅ Ephemeral keys received on Watch")
        } catch {
            print("❌ Failed to request ephemeral keys: \(error)")
        }
    }
    
    // Play TTS for command result
    private func playTTS(for text: String) async {
        // Request keys if needed
        if settingsManager.shouldRefreshKeys() || settingsManager.ephemeralKeys == nil {
            if let config = settingsManager.laptopConfig {
                await requestEphemeralKeys(config: config)
            }
        }
        
        guard let keys = settingsManager.ephemeralKeys else {
            print("⚠️ No ephemeral keys for TTS")
            return
        }
        
        let cleanedText = cleanTextForTTS(text)
        guard !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        do {
            let ttsHandler = LocalTTSHandler(apiKey: keys.openai)
            let voice = selectVoiceForLanguage(settingsManager.transcriptionLanguage)
            let audioData = try await ttsHandler.synthesize(
                text: cleanedText,
                voice: voice,
                speed: settingsManager.ttsSpeed
            )
            
            await MainActor.run {
                do {
                    try audioPlayer.play(audioData: audioData)
                } catch {
                    print("❌ Failed to play TTS: \(error)")
                                        }
                                    }
        } catch {
            print("❌ TTS generation error: \(error)")
        }
    }
    
    private func selectVoiceForLanguage(_ language: TranscriptionLanguage) -> String {
        switch language {
        case .russian:
            return "nova"
        case .english:
            return "alloy"
        case .georgian:
            return "echo"
        case .auto:
            return "alloy"
        }
    }
    
    private func cleanTextForTTS(_ text: String) -> String {
        var cleaned = text
        // Remove ANSI codes
        cleaned = cleaned.replacingOccurrences(
            of: "\\u{001B}\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
        // Remove control characters except newline
        cleaned = cleaned.unicodeScalars.filter { scalar in
            let value = scalar.value
            return (value >= 32 && value <= 126) || value == 10 || value == 9 || (value >= 0x80 && value <= 0x10FFFF)
        }.map { Character($0) }.reduce("") { $0 + String($1) }
        return cleaned
    }
    
    private func connectToTerminalStream(config: TunnelConfig, sessionId: String) {
        wsClient.disconnect()
        
        guard settingsManager.commandMode == .direct,
              let session = terminalViewModel.sessions.first(where: { $0.id == sessionId }),
              session.terminalType == .cursorAgent else {
            return
        }
        
        wsClient.connect(config: config, sessionId: sessionId) { _ in
            // Ignore raw output - cleaned output is streamed separately
        }
    }

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
                self.terminalOutput = message.text
                self.scheduleAutoTTS(for: message.text)
            }
        }
    }
    
    // Send command to terminal via WebSocket
    private func sendCommandToTerminal(_ command: String) {
        if !wsClient.isConnected {
            // Reconnect if needed
            if let config = settingsManager.laptopConfig,
               let sessionId = settingsManager.selectedSessionId {
                connectToTerminalStream(config: config, sessionId: sessionId)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if self.wsClient.isConnected {
                        self.sendCommandToTerminal(command)
                                    }
                                }
                            }
            return
        }
        
        // Send command text first
        let cleanedCommand = command.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
        if !cleanedCommand.isEmpty {
            wsClient.sendInput(cleanedCommand)
                        }
        
        // Then send \r separately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.wsClient.sendInput("\r")
                }
    }
    
    // Schedule auto TTS
    private func scheduleAutoTTS(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        guard isCursorAgentTerminal else { return }
        
        ttsTimer?.invalidate()
        
        let threshold: TimeInterval = 3.0 // 3 seconds for Watch (shorter than iPhone)
        ttsTimer = Timer.scheduledTimer(withTimeInterval: threshold, repeats: false) { [self] _ in
            let currentOutput = self.terminalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentOutput == trimmed && !currentOutput.isEmpty {
                Task {
                    await self.playTTS(for: currentOutput)
                }
            }
        }
    }
    
}

private struct SessionPickerSheet: View {
    let sessions: [TerminalSession]
    let selectedId: String?
    let onSelect: (String) -> Void
    let onCreateCursorAgent: (() -> Void)?
    let onCreateRegular: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Text("No sessions available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sessions) { session in
                        Button(action: {
                            onSelect(session.id)
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.name ?? session.id)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    Text(session.terminalType == .cursorAgent ? "Cursor Agent" : "Regular")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if session.id == selectedId {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                if let createCursorAgent = onCreateCursorAgent {
                    Button(action: {
                        createCursorAgent()
                        dismiss()
                    }) {
                        Label("Create Cursor Agent", systemImage: "plus.circle")
                    }
                }
                
                if let createRegular = onCreateRegular {
                    Button(action: {
                        createRegular()
                        dismiss()
                    }) {
                        Label("Create Terminal", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Sessions")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioRecorder())
}
