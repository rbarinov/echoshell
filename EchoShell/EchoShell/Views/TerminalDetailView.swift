//
//  TerminalDetailView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Detailed view for a single terminal session with real-time streaming
//

import SwiftUI

struct TerminalDetailView: View {
    let session: TerminalSession
    let config: TunnelConfig
    
    @StateObject private var wsClient = WebSocketClient()
    @State private var commandInput = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Terminal output
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(wsClient.messages) { message in
                                TerminalMessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .background(Color.black)
                    .onChange(of: wsClient.messages.count) { _ in
                        if let lastMessage = wsClient.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Command input
                HStack {
                    TextField("Enter command...", text: $commandInput)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit {
                            sendCommand()
                        }
                    
                    Button {
                        sendCommand()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                    }
                    .disabled(commandInput.isEmpty)
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
            }
            .navigationTitle(session.id)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Image(systemName: wsClient.isConnected ? "circle.fill" : "circle")
                            .font(.system(size: 8))
                            .foregroundColor(wsClient.isConnected ? .green : .red)
                        
                        Text(wsClient.isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                    }
                }
            }
            .onAppear {
                wsClient.connect(config: config, sessionId: session.id)
            }
            .onDisappear {
                wsClient.disconnect()
            }
        }
    }
    
    private func sendCommand() {
        guard !commandInput.isEmpty else { return }
        
        let command = commandInput
        commandInput = ""
        
        // Add command to messages immediately for better UX
        let commandMessage = TerminalMessage(
            type: .command,
            sessionId: session.id,
            data: "$ \(command)",
            timestamp: Date()
        )
        wsClient.messages.append(commandMessage)
        
        // Execute command on laptop
        Task {
            let apiClient = APIClient(config: config)
            do {
                let output = try await apiClient.executeCommand(sessionId: session.id, command: command)
                // Output will come via WebSocket, but we can also show it immediately
                print("✅ Command executed: \(command)")
            } catch {
                print("❌ Error executing command: \(error)")
            }
        }
    }
}

struct TerminalMessageRow: View {
    let message: TerminalMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(message.timestamp, style: .time)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 60, alignment: .leading)
            
            // Message content
            Text(message.data)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(messageColor)
                .textSelection(.enabled)
        }
    }
    
    private var messageColor: Color {
        switch message.type {
        case .command:
            return .cyan
        case .error:
            return .red
        case .output:
            return .white
        case .status:
            return .yellow
        }
    }
}
