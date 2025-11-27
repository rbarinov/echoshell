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
    @State private var isHeadlessTerminalSheetPresented = false
    
    // Get selected session
    private var selectedSession: TerminalSession? {
        guard let sessionId = settingsManager.selectedSessionId else { return nil }
        return terminalViewModel.sessions.first { $0.id == sessionId }
    }
    
    // Check if selected session is Cursor terminal
    private var isCursorTerminal: Bool {
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
                    await terminalViewModel.loadSessions(config: config)
                    // Set default session if none selected
                    if settingsManager.selectedSessionId == nil && !terminalViewModel.sessions.isEmpty {
                        settingsManager.selectedSessionId = terminalViewModel.sessions.first?.id
                    }
                    
                    // Connect WebSocket for direct mode
                    if settingsManager.commandMode == .direct,
                       let sessionId = settingsManager.selectedSessionId,
                       let session = terminalViewModel.sessions.first(where: { $0.id == sessionId }),
                       session.terminalType == .cursor {
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
                    switch settingsManager.commandMode {
                    case .direct:
                        if isHeadlessTerminal {
                            await executeCommand(audioRecorder.recognizedText)
                        } else if isCursorTerminal {
                            sendCommandToTerminal(audioRecorder.recognizedText)
                        }
                    case .agent:
                        // Agent mode: execute without requiring terminal session
                        await executeAgentCommand(audioRecorder.recognizedText)
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
               session.terminalType == .cursor {
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
               session.terminalType == .cursor {
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
            if settingsManager.laptopConfig != nil {
                // Show the worst connection state between WebSocket and RecordingStream
                let worstState = getWorstConnectionState()
                ConnectionStatusView(connectionState: worstState)
                    .onChange(of: worstState) { oldValue, newValue in
                        handleConnectionStateChange(from: oldValue, to: newValue)
                    }
            } else {
                ConnectionStatusView(connectionState: .disconnected)
            }
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
                
                // Hide session picker in agent mode - agent works without terminal context
                if settingsManager.commandMode == .agent {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Agent Mode")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                } else if validSessions.isEmpty {
                    if settingsManager.commandMode == .direct {
                        createHeadlessTerminalView
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
                            onCreateHeadless: settingsManager.commandMode == .direct ? { createHeadlessSession(.cursor) } : nil,
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
    
    private func createHeadlessSession(_ type: TerminalType = .cursor) {
        Task {
            guard let config = settingsManager.laptopConfig else { return }
            await terminalViewModel.createNewSession(
                config: config,
                terminalType: type
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
    
    private var createHeadlessTerminalView: some View {
        Button(action: {
            isHeadlessTerminalSheetPresented = true
        }) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 10))
                Text("Create Headless")
                    .font(.caption2)
            }
            .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isHeadlessTerminalSheetPresented) {
            HeadlessTerminalCreationSheet(
                onCreateCursorCLI: {
                    createHeadlessSession(.cursor)
                    isHeadlessTerminalSheetPresented = false
                },
                onCreateClaudeCLI: {
                    createHeadlessSession(.claude)
                    isHeadlessTerminalSheetPresented = false
                }
            )
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
                 (settingsManager.commandMode == .direct && !isHeadlessTerminal))
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
            } else if settingsManager.commandMode == .direct && !isHeadlessTerminal {
                Text("Select Headless")
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
                await terminalViewModel.createNewSession(config: config, terminalType: .cursor)
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
                // Agent mode: use agent endpoint without requiring session
                let result = try await terminalViewModel.apiClient!.executeAgentCommand(
                    sessionId: nil,
                    command: command
                )
                await MainActor.run {
                    commandResult = result
                }
            } else {
                // Direct mode: requires session
                let activeSession = terminalViewModel.sessions.first(where: { $0.id == sessionId })
                
                if activeSession?.terminalType.isHeadless == true {
                    _ = try await terminalViewModel.apiClient!.executeCommand(
                        sessionId: sessionId,
                        command: command
                    )
                } else if isCursorTerminal {
                    print("⚠️ executeCommand called in direct mode - should use WebSocket")
                }
            }
        } catch {
            await MainActor.run {
                commandResult = "Error: \(error.localizedDescription)"
            }
        }
    }

    // New function for agent mode execution without session requirement
    private func executeAgentCommand(_ command: String) async {
        guard let config = settingsManager.laptopConfig else {
            await MainActor.run {
                commandResult = "Error: Not connected to laptop"
            }
            return
        }

        do {
            if terminalViewModel.apiClient == nil {
                terminalViewModel.apiClient = APIClient(config: config)
            }

            // Agent mode: execute without requiring terminal session
            let result = try await terminalViewModel.apiClient!.executeAgentCommand(
                sessionId: nil,
                command: command
            )
            await MainActor.run {
                commandResult = result
            }
            // Trigger TTS for result
            await playTTS(for: result)
        } catch {
            await MainActor.run {
                commandResult = "Error: \(error.localizedDescription)"
            }
        }
    }

    // Play TTS for command result
    private func playTTS(for text: String) async {
        guard let laptopConfig = settingsManager.laptopConfig else {
            print("⚠️ No laptop config for TTS")
            return
        }
        
        let cleanedText = cleanTextForTTS(text)
        guard !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        do {
            // Build TTS endpoint from laptop config (proxy endpoint via tunnel)
            let ttsEndpoint = "\(laptopConfig.apiBaseUrl)/proxy/tts/synthesize"
            
            let language = settingsManager.transcriptionLanguage.rawValue
            
            // Call TTS proxy endpoint directly
            // Voice is controlled by server configuration (TTS_VOICE env var), not sent from client
            var request = URLRequest(url: URL(string: ttsEndpoint)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(laptopConfig.authKey, forHTTPHeaderField: "X-Laptop-Auth-Key")
            
            var body: [String: Any] = [
                "text": cleanedText,
                "speed": settingsManager.ttsSpeed
            ]
            if language != "auto" {
                body["language"] = language
            }
            
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw TTSError.requestFailed
            }
            
            // Parse response - should contain base64 audio
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let audioBase64 = json["audio"] as? String,
                  let audioData = Data(base64Encoded: audioBase64) else {
                throw TTSError.requestFailed
            }
            
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
              session.terminalType == .cursor else {
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
        
        guard isHeadlessTerminal else { return }
        
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
    
    // Get worst connection state between WebSocket and RecordingStream
    private func getWorstConnectionState() -> ConnectionState {
        let wsState = wsClient.connectionState
        let recordingState = recordingStreamClient.connectionState
        
        // Priority: dead > disconnected > reconnecting > connecting > connected
        if wsState == .dead || recordingState == .dead {
            return .dead
        }
        if wsState == .disconnected || recordingState == .disconnected {
            return .disconnected
        }
        if wsState == .reconnecting || recordingState == .reconnecting {
            return .reconnecting
        }
        if wsState == .connecting || recordingState == .connecting {
            return .connecting
        }
        return .connected
    }
    
    // Handle connection state changes with haptic feedback
    private func handleConnectionStateChange(from oldState: ConnectionState, to newState: ConnectionState) {
        // Only trigger haptic feedback for significant state changes
        if oldState == newState {
            return
        }
        
        // Haptic feedback is not available in watchOS 10+ without WatchKit
        // Connection state changes are already visible in the UI
    }
    
}

private struct SessionPickerSheet: View {
    let sessions: [TerminalSession]
    let selectedId: String?
    let onSelect: (String) -> Void
    let onCreateHeadless: (() -> Void)?
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
                                    Text(label(for: session.terminalType))
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
                
                if let createHeadless = onCreateHeadless {
                    Button(action: {
                        createHeadless()
                        dismiss()
                    }) {
                        Label("Create Headless", systemImage: "plus.circle")
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
    
    private func label(for type: TerminalType) -> String {
        switch type {
        case .cursor:
            return "Cursor CLI"
        case .claude:
            return "Claude CLI"
        case .regular:
            return "Regular"
        }
    }
}

private struct HeadlessTerminalCreationSheet: View {
    let onCreateCursorCLI: () -> Void
    let onCreateClaudeCLI: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Button(action: {
                    onCreateCursorCLI()
                    dismiss()
                }) {
                    Label("Create Cursor CLI", systemImage: "terminal")
                }
                
                Button(action: {
                    onCreateClaudeCLI()
                    dismiss()
                }) {
                    Label("Create Claude CLI", systemImage: "brain.head.profile")
                }
            }
            .navigationTitle("Create Headless")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioRecorder())
}

enum TTSError: Error, LocalizedError {
    case requestFailed
    
    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "TTS request failed"
        }
    }
}
