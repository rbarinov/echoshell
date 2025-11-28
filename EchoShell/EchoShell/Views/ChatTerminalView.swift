//
//  ChatTerminalView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Chat interface for headless terminals - continuous message accumulation
//

import SwiftUI
import AVFoundation

/// TTS lifecycle state machine (simplified for server-side TTS)
enum TTSState: Equatable {
    case idle
    case playing
    case error(String)

    var isActive: Bool {
        switch self {
        case .playing:
            return true
        case .idle, .error:
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
    @State private var isAgentProcessing: Bool = false // Track if agent is processing
    @State private var ttsState: TTSState = .idle // TTS state machine
    @State private var avAudioPlayer: AVAudioPlayer? // For playing server-side TTS audio
    @State private var audioPlayerDelegate: AudioPlayerDelegateWrapper? // Keep delegate alive
    
    init(session: TerminalSession, config: TunnelConfig) {
        self.session = session
        self.config = config
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(sessionId: session.id))
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
            setupAudioRecorder()
        }
        .onDisappear {
            wsClient.disconnect()
            stopAudioPlayback()
        }
        .onChange(of: audioRecorder.isTranscribing) { oldValue, newValue in
            // This is now a no-op - transcription comes from WebSocket callback
            // Keeping for potential UI state updates
            if oldValue == true && newValue == false {
                print("📱 ChatTerminalView: isTranscribing changed from \(oldValue) to \(newValue)")
            }
        }
        // NOTE: Commands are now sent via WebSocket executeAudioCommand in handleAudioFileReady
        // The old flow of "transcribe locally then send text" is replaced by:
        // "send audio via WebSocket, server transcribes and processes"
        .onChange(of: audioRecorder.isRecording) { oldValue, newValue in
            // Just for debugging
            print("📱 ChatTerminalView: isRecording changed from \(oldValue) to \(newValue)")
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
                    if ttsState.isActive {
                        print("🛑 ChatTerminalView: Stopping TTS before new recording")
                        stopAudioPlayback()
                    }
                    
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
    
    private func setupAudioRecorder() {
        audioRecorder.configure(with: settingsManager)
        audioRecorder.autoSendCommand = false
        
        // Set callback for when audio file is ready (WebSocket mode)
        // Use a capture list with unowned references since this view owns the recorder
        audioRecorder.onAudioFileReady = { audioURL in
            Task { @MainActor in
                await self.handleAudioFileReady(audioURL)
            }
        }
        
        print("✅ ChatTerminalView: AudioRecorder configured (WebSocket mode enabled)")
    }
    
    /// Handle audio file ready for WebSocket transmission
    @MainActor
    private func handleAudioFileReady(_ audioURL: URL) async {
        print("🎤 ChatTerminalView: Audio file ready: \(audioURL.path)")
        
        // Load audio data
        guard let audioData = try? Data(contentsOf: audioURL) else {
            print("❌ ChatTerminalView: Failed to load audio file")
            return
        }
        
        print("🎤 ChatTerminalView: Loaded audio data: \(audioData.count) bytes")
        
        guard wsClient.isConnected else {
            print("❌ ChatTerminalView: WebSocket not connected, cannot send audio")
            return
        }
        
        // Mark as processing
        isAgentProcessing = true
        
        // Send audio via WebSocket
        let language = settingsManager.transcriptionLanguage.whisperCode ?? "en"
        wsClient.executeAudioCommand(
            audioData,
            audioFormat: "audio/m4a",
            ttsEnabled: settingsManager.ttsEnabled,
            ttsSpeed: settingsManager.ttsSpeed,
            language: language
        )
        
        // Clean up audio file
        try? FileManager.default.removeItem(at: audioURL)
        
        print("📤 ChatTerminalView: Sent audio command via WebSocket")
    }
    
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
                        // Process completed - reset processing state
                        // TTS audio will arrive via onTTSAudio callback
                        self.isAgentProcessing = false
                        print("✅ ChatTerminalView: Completion message received, resetting isAgentProcessing")
                        return
                    }
                    
                    // Check if this is an error message (indicates completion)
                    if message.type == .error {
                        // Error indicates completion (even if failed)
                        self.isAgentProcessing = false
                        print("✅ ChatTerminalView: Error message received, resetting isAgentProcessing")
                    }
                }
            },
            onTTSAudio: { event in
                // Server-side TTS audio received - play it directly
                Task { @MainActor in
                    print("🔊 ChatTerminalView: Received TTS audio from server: \(event.audio.count) bytes")
                    
                    // Stop any previous playback before starting new one
                    if self.ttsState.isActive {
                        print("🛑 ChatTerminalView: Stopping previous audio before playing new")
                        self.stopAudioPlayback()
                    }
                    
                    // Play the received audio
                    self.playServerTTSAudio(event.audio)
                }
            },
            onTranscription: { transcribedText in
                Task { @MainActor in
                    // Server-side transcription received
                    print("🎤 ChatTerminalView: Received transcription from server: \(transcribedText.prefix(50))...")
                    // Note: The transcription is automatically added as a user message by the server
                    // So we don't need to add it to chat history here
                }
            }
        )
    }
    
    // MARK: - Audio Playback (Server-side TTS)
    
    private func playServerTTSAudio(_ audioData: Data) {
        do {
            // Configure audio session for playback
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // Create delegate wrapper and store it to keep it alive
            let delegate = AudioPlayerDelegateWrapper {
                Task { @MainActor in
                    self.ttsState = .idle
                    self.isAgentProcessing = false
                    self.audioPlayerDelegate = nil
                    self.avAudioPlayer = nil
                    print("🔇 ChatTerminalView: Server TTS playback finished")
                }
            }
            audioPlayerDelegate = delegate
            
            // Create and play audio
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = delegate
            player.play()
            avAudioPlayer = player // Keep reference to prevent deallocation
            ttsState = .playing
            print("▶️ ChatTerminalView: Started playing server TTS audio")
        } catch {
            print("❌ ChatTerminalView: Error playing server TTS audio: \(error)")
            ttsState = .error(error.localizedDescription)
            isAgentProcessing = false
            
            // Auto-reset error state after 3 seconds
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if case .error = self.ttsState {
                    self.ttsState = .idle
                }
            }
        }
    }
    
    private func stopAudioPlayback() {
        avAudioPlayer?.stop()
        avAudioPlayer = nil
        ttsState = .idle
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
    
}

// MARK: - Audio Player Delegate Wrapper

/// Wrapper class to handle AVAudioPlayerDelegate callbacks
private class AudioPlayerDelegateWrapper: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        super.init()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("❌ AVAudioPlayer decode error: \(error?.localizedDescription ?? "unknown")")
        onFinish()
    }
}

