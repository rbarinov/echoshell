//
//  ChatTerminalView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Chat interface for headless terminals - continuous message accumulation
//

import SwiftUI

/// TTS lifecycle state machine
enum TTSState: Equatable {
    case idle
    case generating
    case ready
    case playing
    case error(String)

    var isActive: Bool {
        switch self {
        case .generating, .playing:
            return true
        case .idle, .ready, .error:
            return false
        }
    }
}

struct ChatTerminalView: View {
    let session: TerminalSession
    let config: TunnelConfig
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var sessionState: SessionStateManager

    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var wsClient = WebSocketClient()
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var recordingStreamClient = RecordingStreamClient()
    @StateObject private var audioPlayer: AudioPlayer
    @StateObject private var ttsService: TTSService
    @State private var lastTTSedText: String = "" // Track last TTS to prevent duplicates
    @State private var showTTSPlayer: Bool = false // Show TTS playback card
    @State private var isAgentProcessing: Bool = false // Track if agent is processing
    @State private var ttsState: TTSState = .idle // TTS state machine
    
    init(session: TerminalSession, config: TunnelConfig) {
        self.session = session
        self.config = config
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(sessionId: session.id))
        
        let player = AudioPlayer()
        _audioPlayer = StateObject(wrappedValue: player)
        _ttsService = StateObject(wrappedValue: TTSService(audioPlayer: player))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat interface - always show full history (no mode switching)
            ChatHistoryView(
                messages: chatViewModel.chatHistory,
                isAgentMode: true // Always in "agent" mode (showing all messages)
            )
            
            // TTS playback card (shown after TTS is generated)
            if showTTSPlayer && ttsService.lastAudioData != nil {
                TTSPlayerCard(
                    ttsService: ttsService,
                    onDismiss: {
                        showTTSPlayer = false
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Recording button
            recordingButtonView
        }
        .onAppear {
            
            // Load chat history from server
            Task {
                await loadChatHistory()
            }
            
            setupWebSocket()
            setupRecordingStream()
            audioRecorder.configure(with: settingsManager)
            audioRecorder.autoSendCommand = false
        }
        .onDisappear {
            wsClient.disconnect()
            recordingStreamClient.disconnect()
        }
        .onChange(of: audioRecorder.isTranscribing) { oldValue, newValue in
            // When transcription completes, send command to terminal
            if oldValue == true && newValue == false && !audioRecorder.recognizedText.isEmpty {
                isAgentProcessing = true // Mark as processing
                Task {
                    await sendCommand(audioRecorder.recognizedText)
                }
            }
        }
        .onReceive(EventBus.shared.ttsPlaybackFinishedPublisher) { _ in
            // When audio playback finishes, agent processing is complete
            isAgentProcessing = false
        }
        .onChange(of: audioPlayer.isPlaying) { oldValue, newValue in
            // Update TTS state machine based on playback state
            if newValue == true {
                // Audio started playing
                ttsState = .playing
                print("🔊 ChatTerminalView: TTS playback started")
            } else if oldValue == true && newValue == false {
                // Audio stopped playing
                ttsState = .idle
                isAgentProcessing = false
                print("🔇 ChatTerminalView: TTS playback stopped, resetting to idle")
            }
        }
    }
    
    // MARK: - Recording Button
    
    private var recordingButtonView: some View {
        VStack(spacing: 12) {
            Button(action: {
                if audioRecorder.isRecording {
                    audioRecorder.stopRecording()
                } else {
                    // Cancel current command execution before starting new recording
                    Task {
                        await cancelCurrentCommand()
                        isAgentProcessing = false // Reset processing state
                        ttsState = .idle // Reset TTS state
                    }

                    audioRecorder.startRecording()
                    // Don't clear history - keep all messages
                }
            }) {
                // Icon changes based on state
                let iconName: String = {
                    if audioRecorder.isRecording {
                        return "stop.circle.fill"
                    } else if isAgentProcessing {
                        return "hourglass"
                    } else if ttsState.isActive {
                        return "waveform"
                    } else {
                        return "mic.circle.fill"
                    }
                }()

                let iconColor: Color = {
                    if audioRecorder.isRecording {
                        return .red
                    } else if isAgentProcessing {
                        return .orange
                    } else if ttsState.isActive {
                        return .purple
                    } else {
                        return .blue
                    }
                }()

                Image(systemName: iconName)
                    .font(.system(size: 60))
                    .foregroundColor(iconColor)
                    .scaleEffect(audioRecorder.isRecording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: audioRecorder.isRecording)
            }
            
            if audioRecorder.isTranscribing {
                Text("Transcribing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if !audioRecorder.recognizedText.isEmpty {
                Text(audioRecorder.recognizedText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
    
    // MARK: - Setup Methods
    
    private func setupWebSocket() {
        wsClient.connect(
            config: config,
            sessionId: session.id,
            onMessage: nil, // Not needed for chat interface
            onChatMessage: { message in
                Task { @MainActor in
                    self.chatViewModel.addMessage(message)
                    
                    // Check if this is a completion message (system message with completion metadata)
                    if message.type == .system, 
                       let metadata = message.metadata,
                       metadata.completion == true {
                        // Process completed - reset processing state immediately
                        // TTS will be handled separately via tts_ready event
                        self.isAgentProcessing = false
                        print("✅ ChatTerminalView: Completion message received, resetting isAgentProcessing")
                        return
                    }
                    
                    // Check if this is an error message (indicates completion)
                    if message.type == .error {
                        // Error indicates completion (even if failed)
                        // Don't wait for TTS - error means process is done
                        self.isAgentProcessing = false
                        print("✅ ChatTerminalView: Error message received, resetting isAgentProcessing")
                    }
                    
                    // Note: We don't reset isAgentProcessing here for assistant/tool messages
                    // because TTS might still be generating. We'll reset it when:
                    // 1. Completion message received (handled above)
                    // 2. TTS playback finishes (handled in onReceive/onChange)
                    // 3. Error message received (handled above)
                    // 4. User cancels command (handled in cancelCurrentCommand)
                }
            }
        )
    }
    
    private func setupRecordingStream() {
        recordingStreamClient.connect(
            config: config,
            sessionId: session.id,
            onMessage: { message in
                // Legacy format support - no action needed
                // Messages are already in chatHistory and accumulate continuously
            },
            onTTSReady: { text in
                Task { @MainActor in
                    // Prevent duplicate TTS for same text
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedText.isEmpty else { return }

                    // Check if we already generated TTS for this exact text
                    if self.lastTTSedText == trimmedText {
                        print("⚠️ ChatTerminalView: Skipping duplicate TTS for same text")
                        return
                    }

                    // Check if TTS is already in progress using state machine
                    if self.ttsState.isActive {
                        print("⚠️ ChatTerminalView: TTS already active (state: \(self.ttsState)), skipping")
                        return
                    }

                    // Mark this text as processed BEFORE generating (prevent race conditions)
                    self.lastTTSedText = trimmedText

                    // Transition to generating state
                    self.ttsState = .generating

                    do {
                        _ = try await self.ttsService.synthesizeAndPlay(
                            text: text,
                            config: config,
                            speed: 1.0,
                            language: "en"
                        )
                        print("✅ ChatTerminalView: TTS completed for text (\(trimmedText.count) chars)")

                        // Transition to ready state
                        self.ttsState = .ready

                        // Show TTS player card after successful generation
                        withAnimation {
                            self.showTTSPlayer = true
                        }

                        // Reset agent processing state after TTS completes
                        self.isAgentProcessing = false

                        // Monitor playback to transition to playing state
                        // This is handled by onChange(of: audioPlayer.isPlaying) below
                    } catch {
                        print("❌ TTS error: \(error)")

                        // Transition to error state
                        self.ttsState = .error(error.localizedDescription)

                        // Reset on error to allow retry
                        self.lastTTSedText = ""
                        self.isAgentProcessing = false

                        // Auto-reset error state after 3 seconds
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            if case .error = self.ttsState {
                                self.ttsState = .idle
                            }
                        }
                    }
                }
            }
        )
    }
    
    // MARK: - History Loading
    
    private func loadChatHistory() async {
        do {
            print("📂 ChatTerminalView: Loading chat history for session \(session.id)")
            print("   API URL: \(config.apiBaseUrl)/terminal/\(session.id)/history")
            
            // Try to get chat history as JSON (for headless terminals)
            let url = URL(string: "\(config.apiBaseUrl)/terminal/\(session.id)/history")!
            var request = URLRequest(url: url)
            request.setValue(UIDevice.current.identifierForVendor?.uuidString ?? "unknown", forHTTPHeaderField: "X-Device-ID")
            
            // Add auth header
            request.setValue(config.authKey, forHTTPHeaderField: "X-Laptop-Auth-Key")
            
            print("   Request headers: X-Device-ID=\(UIDevice.current.identifierForVendor?.uuidString ?? "unknown"), X-Laptop-Auth-Key=\(config.authKey.prefix(10))...")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("⚠️ ChatTerminalView: Invalid response type")
                return
            }
            
            print("   Response status: \(httpResponse.statusCode)")
            print("   Response data size: \(data.count) bytes")
            
            guard httpResponse.statusCode == 200 else {
                if let errorString = String(data: data, encoding: .utf8) {
                    print("⚠️ ChatTerminalView: Failed to load history (status: \(httpResponse.statusCode), error: \(errorString))")
                } else {
                    print("⚠️ ChatTerminalView: Failed to load history (status: \(httpResponse.statusCode))")
                }
                return
            }
            
            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("   Raw response: \(responseString.prefix(500))")
            }
            
            struct HistoryResponse: Codable {
                let session_id: String
                let chat_history: [ChatMessage]?
                let history: String?
            }
            
            let historyResponse = try JSONDecoder().decode(HistoryResponse.self, from: data)
            
            print("   Parsed response: session_id=\(historyResponse.session_id), chat_history count=\(historyResponse.chat_history?.count ?? 0)")
            
            // Load chat history if available (even if empty, to initialize the view)
            if let chatHistory = historyResponse.chat_history {
                await MainActor.run {
                    if !chatHistory.isEmpty {
                        print("✅ ChatTerminalView: Loaded \(chatHistory.count) messages from history")
                    } else {
                        print("ℹ️ ChatTerminalView: Chat history is empty (no messages yet)")
                    }
                    chatViewModel.loadMessages(chatHistory)
                }
            } else {
                print("⚠️ ChatTerminalView: chat_history field is nil in response")
            }
        } catch {
            print("❌ ChatTerminalView: Error loading chat history: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                print("   Decoding error details: \(decodingError)")
                switch decodingError {
                case .typeMismatch(let type, let context):
                    print("     Type mismatch: expected \(type), at \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    print("     Value not found: \(type), at \(context.codingPath)")
                case .keyNotFound(let key, let context):
                    print("     Key not found: \(key), at \(context.codingPath)")
                case .dataCorrupted(let context):
                    print("     Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("     Unknown decoding error")
                }
            }
        }
    }
    
    // MARK: - Command Cancellation
    
    private func cancelCurrentCommand() async {
        let apiClient = APIClient(config: config)
        do {
            try await apiClient.cancelCommand(sessionId: session.id)
            print("✅ ChatTerminalView: Current command cancelled")
        } catch {
            print("⚠️ ChatTerminalView: Error cancelling command: \(error)")
            // Don't throw - cancellation failure shouldn't prevent new recording
        }
    }
    
    // MARK: - Command Execution
    
    private func sendCommand(_ command: String) async {
        guard !command.isEmpty else { return }
        
        let apiClient = APIClient(config: config)
        do {
            _ = try await apiClient.executeCommand(sessionId: session.id, command: command)
            print("✅ Command sent: \(command)")
        } catch {
            print("❌ Error sending command: \(error)")
            
            // Add error message to chat
            let errorMessage = ChatMessage(
                id: UUID().uuidString,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                type: .error,
                content: "Failed to execute command: \(error.localizedDescription)"
            )
            await MainActor.run {
                chatViewModel.addMessage(errorMessage)
            }
        }
    }
}

// MARK: - TTS Player Card

struct TTSPlayerCard: View {
    @ObservedObject var ttsService: TTSService
    let onDismiss: () -> Void
    @State private var isPlaying: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button(action: {
                if isPlaying {
                    ttsService.stop()
                    isPlaying = false
                } else {
                    Task {
                        await ttsService.replay()
                        isPlaying = true
                    }
                }
            }) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
            }
            
            // TTS label
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Response Audio")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Tap to replay")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: -2)
        .padding(.horizontal)
        .onReceive(EventBus.shared.ttsPlaybackFinishedPublisher) { _ in
            isPlaying = false
        }
        .onChange(of: ttsService.audioPlayer.isPlaying) { oldValue, newValue in
            isPlaying = newValue
        }
    }
}
