//
//  HeadlessAgentView.swift
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

struct HeadlessAgentView: View {
    let session: TerminalSession
    let config: TunnelConfig
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var sessionState: SessionStateManager

    @StateObject private var baseChatViewModel: ChatViewModel
    @StateObject private var chatViewModel: HeadlessAgentChatViewModel
    @StateObject private var wsClient = WebSocketClient()
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var isAgentProcessing: Bool = false // Track if agent is processing
    @State private var ttsState: TTSState = .idle // TTS state machine
    @State private var avAudioPlayer: AVAudioPlayer? // For playing server-side TTS audio
    @State private var audioPlayerDelegate: AudioPlayerDelegateWrapper? // Keep delegate alive
    @State private var pendingVoiceMessageId: String?
    
    init(session: TerminalSession, config: TunnelConfig) {
        self.session = session
        self.config = config
        let baseViewModel = ChatViewModel(sessionId: session.id)
        _baseChatViewModel = StateObject(wrappedValue: baseViewModel)
        _chatViewModel = StateObject(wrappedValue: HeadlessAgentChatViewModel(baseViewModel: baseViewModel))
    }
    
    var body: some View {
        GenericChatView(
            viewModel: chatViewModel,
            isAgentMode: true // Always in "agent" mode (showing all messages)
        )
        .onAppear {
            // Setup callbacks for HeadlessAgentChatViewModel
            chatViewModel.onSendTextCommand = { command in
                await sendTextCommand(command)
            }
            chatViewModel.onStartRecording = {
                audioRecorder.startRecording()
            }
            chatViewModel.onStopRecording = {
                audioRecorder.stopRecording()
            }
            chatViewModel.updateRecordingState(audioRecorder.isRecording)
            
            // Sync isProcessing state
            chatViewModel.isProcessing = isAgentProcessing
            
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
                print("📱 HeadlessAgentView: isTranscribing changed from \(oldValue) to \(newValue)")
            }
        }
        // NOTE: Commands are now sent via WebSocket executeAudioCommand in handleAudioFileReady
        // The old flow of "transcribe locally then send text" is replaced by:
        // "send audio via WebSocket, server transcribes and processes"
        .onChange(of: audioRecorder.isRecording) { oldValue, newValue in
            chatViewModel.updateRecordingState(newValue)
            print("📱 HeadlessAgentView: isRecording changed from \(oldValue) to \(newValue)")
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
                        print("🛑 HeadlessAgentView: Stopping TTS before new recording")
                        stopAudioPlayback()
                    }
                    
                    // Cancel current command execution before starting new recording
                    Task {
                        await cancelCurrentCommand()
                        isAgentProcessing = false // Reset processing state
                        Task { @MainActor in
                            self.chatViewModel.isProcessing = false
                        }
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
        
        print("✅ HeadlessAgentView: AudioRecorder configured (WebSocket mode enabled)")
    }
    
    /// Handle audio file ready for WebSocket transmission
    @MainActor
    private func handleAudioFileReady(_ audioURL: URL) async {
        print("🎤 HeadlessAgentView: Audio file ready: \(audioURL.path)")
        
        // Load audio data
        guard let audioData = try? Data(contentsOf: audioURL) else {
            print("❌ HeadlessAgentView: Failed to load audio file")
            return
        }
        
        print("🎤 HeadlessAgentView: Loaded audio data: \(audioData.count) bytes")
        
        // Add voice bubble & placeholder before sending
        addPendingVoiceMessage(audioURL: audioURL)
        
        guard wsClient.isConnected else {
            print("❌ HeadlessAgentView: WebSocket not connected, cannot send audio")
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
        
        print("📤 HeadlessAgentView: Sent audio command via WebSocket")
    }
    
    /// Send text command via WebSocket
    @MainActor
    private func sendTextCommand(_ command: String) async {
        guard !command.isEmpty else { return }
        
        print("📤 HeadlessAgentView: Sending text command: \(command)")
        
        guard wsClient.isConnected else {
            print("❌ HeadlessAgentView: WebSocket not connected, cannot send command")
            return
        }
        
        // Mark as processing
        isAgentProcessing = true
        Task { @MainActor in
            chatViewModel.isProcessing = true
        }
        
        // Send text command via WebSocket
        let language = settingsManager.transcriptionLanguage.whisperCode ?? "en"
        wsClient.executeCommand(
            command,
            ttsEnabled: settingsManager.ttsEnabled,
            ttsSpeed: settingsManager.ttsSpeed,
            language: language
        )
        
        print("✅ HeadlessAgentView: Sent text command via WebSocket")
    }
    
    private func setupWebSocket() {
        wsClient.connect(
            config: config,
            sessionId: session.id,
            onMessage: nil, // Not needed for chat interface
            onChatMessage: { message in
                Task { @MainActor in
                    if self.handleServerUserMessage(message) {
                        return
                    }
                    
                    self.baseChatViewModel.addMessage(message)
                    self.appendTranscriptIfNeeded(for: message)
                    
                    // Check if this is a completion message (system message with completion metadata)
                    if message.type == .system,
                       let metadata = message.metadata,
                       metadata.completion == true {
                        // Process completed - reset processing state
                        // TTS audio will arrive via onTTSAudio callback
                        self.isAgentProcessing = false
                        Task { @MainActor in
                            self.chatViewModel.isProcessing = false
                        }
                        print("✅ HeadlessAgentView: Completion message received, resetting isAgentProcessing")
                        return
                    }
                    
                    // Check if this is an error message (indicates completion)
                    if message.type == .error {
                        // Error indicates completion (even if failed)
                        self.isAgentProcessing = false
                        Task { @MainActor in
                            self.chatViewModel.isProcessing = false
                        }
                        print("✅ HeadlessAgentView: Error message received, resetting isAgentProcessing")
                    }
                }
            },
            onTTSAudio: { event in
                // Server-side TTS audio received - play it directly
                Task { @MainActor in
            print("🔊 HeadlessAgentView: Received TTS audio from server: \(event.audio.count) bytes")
                    
                    // Stop any previous playback before starting new one
                    if self.ttsState.isActive {
                        print("🛑 HeadlessAgentView: Stopping previous audio before playing new")
                        self.stopAudioPlayback()
                    }
                    
                    // Play the received audio
                    self.playServerTTSAudio(event.audio)
                }
            },
            onTranscription: { transcribedText in
                Task { @MainActor in
                    print("🎤 HeadlessAgentView: Received transcription from server: \(transcribedText.prefix(50))...")
                    self.handleTranscriptionResult(transcribedText)
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
                    ttsState = .idle
                    isAgentProcessing = false
                    Task { @MainActor in
                        chatViewModel.isProcessing = false
                    }
                    audioPlayerDelegate = nil
                    avAudioPlayer = nil
                    print("🔇 HeadlessAgentView: Server TTS playback finished")
                }
            }
            audioPlayerDelegate = delegate
            
            // Create and play audio
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = delegate
            player.play()
            avAudioPlayer = player // Keep reference to prevent deallocation
            ttsState = .playing
            print("▶️ HeadlessAgentView: Started playing server TTS audio")
        } catch {
            print("❌ HeadlessAgentView: Error playing server TTS audio: \(error)")
            ttsState = .error(error.localizedDescription)
            isAgentProcessing = false
            Task { @MainActor in
                self.chatViewModel.isProcessing = false
            }
            
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
            print("📂📂📂 HeadlessAgentView: Loading chat history for session \(session.id)")
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
                print("⚠️ HeadlessAgentView: Invalid response type")
                return
            }
            
            print("   Response status: \(httpResponse.statusCode)")
            print("   Response data size: \(data.count) bytes")
            
            guard httpResponse.statusCode == 200 else {
                if let errorString = String(data: data, encoding: .utf8) {
                    print("⚠️ HeadlessAgentView: Failed to load history (status: \(httpResponse.statusCode), error: \(errorString))")
                } else {
                    print("⚠️ HeadlessAgentView: Failed to load history (status: \(httpResponse.statusCode))")
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
                        print("✅✅✅ HeadlessAgentView: Loading \(chatHistory.count) messages from history")
                    } else {
                        print("ℹ️ HeadlessAgentView: Chat history is empty (no messages yet)")
                    }
                    baseChatViewModel.loadMessages(chatHistory)
                    chatHistory.forEach { message in
                        self.appendTranscriptIfNeeded(for: message)
                    }
                    print("   chatHistory count AFTER load: \(chatViewModel.chatHistory.count)")
                }
            } else {
                print("⚠️ HeadlessAgentView: chat_history field is nil in response")
            }
        } catch {
            print("❌❌❌ HeadlessAgentView: Error loading chat history: \(error)")
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
            print("✅ HeadlessAgentView: Current command cancelled")
        } catch {
            print("⚠️ HeadlessAgentView: Error cancelling command: \(error)")
            // Don't throw - cancellation failure shouldn't prevent new recording
        }
    }
    
    // MARK: - Transcript Helpers
    
    @MainActor
    private func addPendingVoiceMessage(audioURL: URL) {
        let messageId = UUID().uuidString
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        guard let relativePath = saveVoiceAudio(from: audioURL, messageId: messageId) else {
            pendingVoiceMessageId = nil
            return
        }
        
        let voiceMessage = ChatMessage(
            id: messageId,
            timestamp: timestamp,
            type: .tts_audio,
            content: "🎤 Voice message",
            metadata: ChatMessage.Metadata(
                audioFilePath: relativePath
            )
        )
        baseChatViewModel.addMessage(voiceMessage)
        pendingVoiceMessageId = messageId
        
        let placeholder = ChatMessage(
            id: UUID().uuidString,
            timestamp: timestamp + 1,
            type: .user,
            content: "… transcribing …",
            metadata: ChatMessage.Metadata(
                isPlaceholder: true,
                parentMessageId: messageId
            )
        )
        baseChatViewModel.addMessage(placeholder)
    }
    
    @MainActor
    private func handleTranscriptionResult(_ transcribedText: String) {
        let cleaned = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        
        if let pendingId = pendingVoiceMessageId {
            if let index = baseChatViewModel.chatHistory.firstIndex(where: { $0.id == pendingId }) {
                let existing = baseChatViewModel.chatHistory[index]
                let updatedMetadata = metadata(byUpdating: existing.metadata, ttsText: cleaned)
                var updatedHistory = baseChatViewModel.chatHistory
                updatedHistory[index] = ChatMessage(
                    id: existing.id,
                    timestamp: existing.timestamp,
                    type: existing.type,
                    content: existing.content,
                    metadata: updatedMetadata
                )
                baseChatViewModel.chatHistory = updatedHistory
            }
            
            if let placeholderIndex = baseChatViewModel.chatHistory.firstIndex(where: {
                $0.metadata?.isPlaceholder == true && $0.metadata?.parentMessageId == pendingId
            }) {
                let placeholder = baseChatViewModel.chatHistory[placeholderIndex]
                var updatedHistory = baseChatViewModel.chatHistory
                updatedHistory[placeholderIndex] = ChatMessage(
                    id: placeholder.id,
                    timestamp: placeholder.timestamp,
                    type: .user,
                    content: cleaned,
                    metadata: ChatMessage.Metadata(parentMessageId: pendingId)
                )
                baseChatViewModel.chatHistory = updatedHistory
            } else {
                appendTranscriptMessage(for: cleaned, parentId: pendingId, isUser: true)
            }
            
            pendingVoiceMessageId = nil
        } else {
            let userMessage = ChatMessage(
                id: UUID().uuidString,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                type: .user,
                content: cleaned,
                metadata: nil
            )
            baseChatViewModel.addMessage(userMessage)
        }
    }
    
    /// Returns true if message was handled (placeholder replaced)
    @MainActor
    private func handleServerUserMessage(_ message: ChatMessage) -> Bool {
        guard message.type == .user,
              let pendingId = pendingVoiceMessageId else {
            return false
        }
        
        guard let voiceIndex = baseChatViewModel.chatHistory.firstIndex(where: { $0.id == pendingId }) else {
            return false
        }
        
        var updatedHistory = baseChatViewModel.chatHistory
        let voiceMessage = updatedHistory[voiceIndex]
        let updatedMetadata = metadata(byUpdating: voiceMessage.metadata, ttsText: message.content)
        updatedHistory[voiceIndex] = ChatMessage(
            id: voiceMessage.id,
            timestamp: voiceMessage.timestamp,
            type: voiceMessage.type,
            content: voiceMessage.content,
            metadata: updatedMetadata
        )
        
        if let placeholderIndex = updatedHistory.firstIndex(where: {
            $0.metadata?.isPlaceholder == true && $0.metadata?.parentMessageId == pendingId
        }) {
            updatedHistory[placeholderIndex] = ChatMessage(
                id: message.id,
                timestamp: message.timestamp,
                type: .user,
                content: message.content,
                metadata: ChatMessage.Metadata(parentMessageId: pendingId)
            )
        }
        
        baseChatViewModel.chatHistory = updatedHistory
        pendingVoiceMessageId = nil
        return true
    }
    
    @MainActor
    private func appendTranscriptIfNeeded(for message: ChatMessage) {
        guard message.type == .tts_audio,
              let transcript = message.metadata?.ttsText,
              !transcript.isEmpty else { return }
        
        let alreadyExists = baseChatViewModel.chatHistory.contains {
            $0.metadata?.parentMessageId == message.id && $0.content == transcript
        }
        guard !alreadyExists else { return }
        
        appendTranscriptMessage(
            for: transcript,
            parentId: message.id,
            isUser: isUserVoiceMessage(message),
            timestamp: message.timestamp + 1
        )
    }
    
    private func appendTranscriptMessage(for text: String, parentId: String, isUser: Bool, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        let transcriptMessage = ChatMessage(
            id: UUID().uuidString,
            timestamp: timestamp,
            type: isUser ? .user : .assistant,
            content: text,
            metadata: ChatMessage.Metadata(parentMessageId: parentId)
        )
        baseChatViewModel.addMessage(transcriptMessage)
    }
    
    private func saveVoiceAudio(from sourceURL: URL, messageId: String) -> String? {
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioDir = documentsDir.appendingPathComponent("headless_audio", isDirectory: true)
        
        do {
            if !fileManager.fileExists(atPath: audioDir.path) {
                try fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)
            }
            
            let filename = "user_headless_\(messageId).m4a"
            let destinationURL = audioDir.appendingPathComponent(filename)
            
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return "headless_audio/\(filename)"
        } catch {
            print("❌ HeadlessAgentView: Failed to save voice audio: \(error)")
            return nil
        }
    }
    
    private func metadata(byUpdating metadata: ChatMessage.Metadata?, ttsText: String? = nil) -> ChatMessage.Metadata {
        ChatMessage.Metadata(
            toolName: metadata?.toolName,
            toolInput: metadata?.toolInput,
            toolOutput: metadata?.toolOutput,
            thinking: metadata?.thinking,
            errorCode: metadata?.errorCode,
            stackTrace: metadata?.stackTrace,
            completion: metadata?.completion,
            ttsText: ttsText ?? metadata?.ttsText,
            ttsDuration: metadata?.ttsDuration,
            audioFilePath: metadata?.audioFilePath,
            isPlaceholder: metadata?.isPlaceholder,
            parentMessageId: metadata?.parentMessageId
        )
    }
    
    private func isUserVoiceMessage(_ message: ChatMessage) -> Bool {
        guard message.type == .tts_audio else { return false }
        if let path = message.metadata?.audioFilePath, path.contains("user_") {
            return true
        }
        return false
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

