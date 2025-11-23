//
//  SettingsView.swift
//  EchoShell
//
//  Created by Roman Barinov on 2025.11.21.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var watchManager = WatchConnectivityManager.shared
    @State private var showingApiKey = false
    @State private var showingQRScanner = false
    @State private var scannedConfig: TunnelConfig?
    
    var body: some View {
        Form {
            // NEW SECTION: Operation Mode
            Section(header: Text("Operation Mode")) {
                Picker("Mode", selection: $settingsManager.operationMode) {
                    ForEach(OperationMode.allCases) { mode in
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.inline)
                
                if settingsManager.operationMode == .standalone {
                    Text("Connect directly to OpenAI for transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Connect to laptop for terminal control and AI commands")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // NEW SECTION: Laptop Connection (only in laptop mode)
            if settingsManager.operationMode == .laptop {
                Section(header: Text("Laptop Connection")) {
                    if let config = settingsManager.laptopConfig {
                        // Connected
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Connected to Laptop")
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tunnel ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(config.tunnelId)
                                .font(.footnote)
                                .fontDesign(.monospaced)
                        }
                        
                        if let expiresAt = settingsManager.keyExpiresAt {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.blue)
                                Text("Keys expire")
                                Spacer()
                                Text(expiresAt, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Button(role: .destructive) {
                            settingsManager.laptopConfig = nil
                            settingsManager.ephemeralKeys = nil
                        } label: {
                            Label("Disconnect from Laptop", systemImage: "xmark.circle")
                        }
                    } else {
                        // Not connected
                        Button {
                            showingQRScanner = true
                        } label: {
                            Label("Scan QR Code from Laptop", systemImage: "qrcode.viewfinder")
                        }
                        
                        Text("Open the laptop app and scan the QR code to connect")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // EXISTING SECTION: Watch Connection
            Section(header: Text("Watch Connection")) {
                    HStack {
                        Image(systemName: "applewatch")
                            .foregroundColor(watchManager.isWatchConnected ? .green : .gray)
                        Text("Apple Watch")
                        Spacer()
                        Text(watchManager.isWatchConnected ? "Connected" : "Not Connected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if watchManager.isWatchAppInstalled {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Watch app installed")
                                .font(.caption)
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Watch app not installed")
                                .font(.caption)
                        }
                    }
                }
                
                // MODIFIED: Only show API key in standalone mode
                if settingsManager.operationMode == .standalone {
                    Section(header: Text("OpenAI Settings")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            if showingApiKey {
                                TextField("Enter your OpenAI API key", text: $settingsManager.apiKey)
                                    .textContentType(.password)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            } else {
                                SecureField("Enter your OpenAI API key", text: $settingsManager.apiKey)
                                    .textContentType(.password)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            
                            Button(action: {
                                showingApiKey.toggle()
                            }) {
                                Image(systemName: showingApiKey ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.blue)
                            Text("Get API Key")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }
                }
                }
                
                Section(header: Text("Transcription Language"),
                       footer: Text("Select language for better accuracy. Auto mode supports English, Russian, and Georgian.")) {
                    Picker("Language", selection: $settingsManager.transcriptionLanguage) {
                        ForEach(TranscriptionLanguage.allCases) { language in
                            HStack {
                                Text(language.flag)
                                Text(language.displayName)
                            }
                            .tag(language)
                        }
                    }
                    .pickerStyle(.inline)
                }
                
                Section(header: Text("Audio Quality")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundColor(.blue)
                            Text("Sample Rate")
                            Spacer()
                            Text("16 kHz")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Image(systemName: "music.note")
                                .foregroundColor(.blue)
                            Text("Bit Rate")
                            Spacer()
                            Text("32 kbps")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.blue)
                            Text("File Size")
                            Spacer()
                            Text("~240 KB/min")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.subheadline)
                    
                    Text("Optimized for speech recognition. Reduces network usage by 75% compared to CD quality.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Model")
                        Spacer()
                        Text("OpenAI Whisper")
                            .foregroundColor(.secondary)
                    }
                    
                    // NEW: Add current mode
                    HStack {
                        Text("Current Mode")
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: settingsManager.operationMode.icon)
                            Text(settingsManager.operationMode == .standalone ? "Standalone" : "Laptop")
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Current Language")
                        Spacer()
                        HStack(spacing: 4) {
                            Text(settingsManager.transcriptionLanguage.flag)
                            Text(settingsManager.transcriptionLanguage.displayName)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showingQRScanner) {
                QRScannerView(scannedConfig: $scannedConfig)
            }
            .onChange(of: scannedConfig) { config in
                if let config = config {
                    print("📱 QR Code scanned successfully")
                    print("   Tunnel ID: \(config.tunnelId)")
                    
                    // Save config
                    settingsManager.laptopConfig = config
                    
                    // Request ephemeral keys from laptop
                    Task {
                        await requestEphemeralKeys(config: config, manager: settingsManager)
                    }
                }
            }
        }
    }
    
    private func requestEphemeralKeys(config: TunnelConfig, manager: SettingsManager) async {
        print("🔑 Requesting ephemeral keys from laptop...")
        
        let apiClient = APIClient(config: config)
        do {
            let keyResponse = try await apiClient.requestKeys()
            
            // Save keys and expiration
            await MainActor.run {
                manager.ephemeralKeys = keyResponse.keys
                manager.keyExpiresAt = Date(timeIntervalSince1970: TimeInterval(keyResponse.expiresAt))
                print("✅ Ephemeral keys saved successfully")
            }
        } catch {
            print("❌ Error requesting keys: \(error.localizedDescription)")
        }
    }

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}

