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
                    // Stop any current TTS playback before starting new recording
                    if ttsState.isActive || audioPlayer.isPlaying {
                        print("🛑 ChatTerminalView: Stopping TTS before new recording")
                        ttsService.stop()
                    }
                    
                    // Cancel current command execution before starting new recording
                    Task {
                        await cancelCurrentCommand()
                        isAgentProcessing = false // Reset processing state
                        ttsState = .idle // Reset TTS state
                        lastTTSedText = "" // Reset last TTS text to allow new generation
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
            }
            
            if audioRecorder.isTranscribing {
                Text("Transcribing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

                    // Stop any previous playback before starting new TTS
                    // This ensures only one playback at a time
                    if self.ttsState.isActive || self.audioPlayer.isPlaying {
                        print("🛑 ChatTerminalView: Stopping previous TTS playback")
                        self.ttsService.stop()
                        self.ttsState = .idle
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
            print("📂📂📂 ChatTerminalView: Loading chat history for session \(session.id)")
            print("   API URL: \(config.apiBaseUrl)/terminal/\(session.id)/history")
            print("   Current chatHistory count BEFORE load: \(chatViewModel.chatHistory.count)")
            
            // Try to get chat history as JSON (for headless terminals)
            let url = URL(string: "\(config.apiBaseUrl)/terminal/\(session.id)/history")!
            var request = URLRequest(url: url)
            request.setValue(UIDevice.current.identifierForVendor?.uuidString ?? "unknown", forHTTPHeaderField: "X-Device-ID")
            
            // Add auth header
            request.setValue(config.authKey, forHTTPHeaderField: "X-Laptop-Auth-Key")
            
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
                print("   Raw response (first 1000 chars): \(responseString.prefix(1000))")
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
                    // Log message types for debugging
                    let typeCounts = Dictionary(grouping: chatHistory, by: { $0.type }).mapValues { $0.count }
                    print("   Message types in history: \(typeCounts)")
                    
                    if !chatHistory.isEmpty {
                        print("✅✅✅ ChatTerminalView: Loading \(chatHistory.count) messages from history")
                    } else {
                        print("ℹ️ ChatTerminalView: Chat history is empty (no messages yet)")
                    }
                    chatViewModel.loadMessages(chatHistory)
                    print("   chatHistory count AFTER load: \(chatViewModel.chatHistory.count)")
                }
            } else {
                print("⚠️ ChatTerminalView: chat_history field is nil in response")
            }
        } catch {
            print("❌❌❌ ChatTerminalView: Error loading chat history: \(error)")
            if let decodingError = error as? DecodingError {
                print("   Decoding error details: \(decodingError)")
                switch decodingError {
                case .typeMismatch(let type, let context):
                    print("     Type mismatch: expected \(type), at codingPath: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    print("     Value not found: \(type), at codingPath: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .keyNotFound(let key, let context):
                    print("     Key not found: '\(key.stringValue)', at codingPath: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .dataCorrupted(let context):
                    print("     Data corrupted: \(context.debugDescription), at codingPath: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
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

