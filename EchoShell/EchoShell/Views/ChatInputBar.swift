//
//  ChatInputBar.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Telegram-style input bar with text field and audio recording button
//

import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let onSendText: (String) -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let isRecording: Bool
    let isProcessing: Bool
    let isEnabled: Bool
    
    @FocusState private var isTextFieldFocused: Bool
    @State private var inputHeight: CGFloat = 44
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Text input field
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Type a message...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .lineLimit(1...5)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        sendText()
                    }
                    .disabled(isProcessing || isRecording)
                
                // Send button (appears when text is not empty)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: {
                        sendText()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                    }
                    .disabled(isProcessing || isRecording)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            
            // Audio recording button (right)
            Button(action: {
                if isRecording {
                    onStopRecording()
                } else {
                    onStartRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(isRecording ? Color.red : Color.blue)
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .disabled(!isEnabled || isProcessing)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.bottom, 8) // Extra bottom padding for safe area
    }
    
    private func sendText() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        onSendText(trimmedText)
        text = ""
        isTextFieldFocused = false
    }
}

#Preview {
    VStack {
        Spacer()
        ChatInputBar(
            text: .constant(""),
            onSendText: { _ in },
            onStartRecording: {},
            onStopRecording: {},
            isRecording: false,
            isProcessing: false,
            isEnabled: true
        )
    }
    .background(Color(.systemGray5))
}

