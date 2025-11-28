//
//  ChatTerminalView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Chat interface for headless terminals with Agent/History mode toggle
//

import SwiftUI

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
            // View mode toggle (Agent/History)
            viewModeToggle
            
            // Chat interface
            ChatHistoryView(
                messages: chatViewModel.getMessagesForCurrentMode(),
                isAgentMode: chatViewModel.viewMode == .agent
            )
            
            // Recording button (only in Agent mode)
            if chatViewModel.viewMode == .agent {
                recordingButtonView
            }
        }
        .onAppear {
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
                Task {
                    await sendCommand(audioRecorder.recognizedText)
                }
            }
        }
    }
    
    // MARK: - View Mode Toggle
    
    private var viewModeToggle: some View {
        HStack {
            Spacer()
            
            Picker("View Mode", selection: Binding(
                get: { chatViewModel.viewMode },
                set: { chatViewModel.viewMode = $0 }
            )) {
                Text("Agent").tag(ChatViewMode.agent)
                Text("History").tag(ChatViewMode.history)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Spacer()
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Recording Button
    
    private var recordingButtonView: some View {
        VStack(spacing: 12) {
            Button(action: {
                if audioRecorder.isRecording {
                    audioRecorder.stopRecording()
                } else {
                    audioRecorder.startRecording()
                    chatViewModel.clearCurrentExecution()
                }
            }) {
                Image(systemName: audioRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(audioRecorder.isRecording ? .red : .blue)
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
                }
            }
        )
    }
    
    private func setupRecordingStream() {
        recordingStreamClient.connect(
            config: config,
            sessionId: session.id,
            onMessage: { message in
                // Legacy format support
                if message.isComplete == true {
                    Task { @MainActor in
                        self.chatViewModel.finalizeCurrentExecution()
                    }
                }
            },
            onTTSReady: { text in
                // Only trigger TTS in Agent mode
                guard self.chatViewModel.viewMode == .agent else { return }
                
                Task { @MainActor in
                    do {
                        _ = try await self.ttsService.synthesizeAndPlay(
                            text: text,
                            config: config,
                            speed: 1.0,
                            language: "en"
                        )
                    } catch {
                        print("❌ TTS error: \(error)")
                    }
                }
            }
        )
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
