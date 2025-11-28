//
//  MagicLinkInputView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Sheet for entering magic link for laptop connection (emulator debugging)
//

import SwiftUI

struct MagicLinkInputView: View {
    @Binding var magicLink: String
    let onConnect: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Enter Magic Link")
                    .font(.headline)
                    .padding(.top, 20)
                
                Text("Paste the connection link from your laptop app")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Text field for magic link
                TextField("echoshell://connect?...", text: $magicLink, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(3...5)
                    .focused($isTextFieldFocused)
                    .padding(.horizontal)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        connectWithMagicLink()
                    }
                
                // Connect button
                Button(action: {
                    connectWithMagicLink()
                }) {
                    Text("Connect")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(magicLink.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(10)
                }
                .disabled(magicLink.isEmpty)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Auto-focus text field and auto-paste from clipboard
                isTextFieldFocused = true
                
                // Check if clipboard has a link
                if let clipboardString = UIPasteboard.general.string,
                   clipboardString.hasPrefix("echoshell://") {
                    magicLink = clipboardString
                }
            }
        }
    }
    
    private func connectWithMagicLink() {
        guard !magicLink.isEmpty else { return }
        onConnect(magicLink)
        dismiss()
    }
}

#Preview {
    MagicLinkInputView(
        magicLink: .constant(""),
        onConnect: { _ in }
    )
}

