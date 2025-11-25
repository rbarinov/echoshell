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
    @State private var showingQRScanner = false
    @State private var scannedConfig: TunnelConfig?
    @State private var hasProcessedScan = false // Prevent processing the same scan multiple times
    
    var body: some View {
        Form {
            // Laptop Connection Section
            Section(header: Text("Laptop Connection"),
                   footer: Text("Connect to your laptop for terminal control and AI commands")) {
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
                            // Clear all connection state
                            settingsManager.laptopConfig = nil
                            settingsManager.ephemeralKeys = nil
                            // Reset scan state to allow re-scanning
                            hasProcessedScan = false
                            scannedConfig = nil
                            print("📱 Disconnected from laptop, ready for new scan")
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
            
            // Watch Connection Section
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
                
            Section(header: Text("Text-to-Speech"),
                       footer: Text("Adjust the playback speed for voice responses. Range: 0.8x to 2.0x")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.blue)
                            Text("Playback Speed")
                            Spacer()
                            Text(String(format: "%.1fx", settingsManager.ttsSpeed))
                                .foregroundColor(.secondary)
                                .font(.body)
                                .monospacedDigit()
                        }
                        
                        Slider(value: $settingsManager.ttsSpeed, in: 0.8...2.0, step: 0.1) {
                            Text("Speed")
                        } minimumValueLabel: {
                            Text("0.8x")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } maximumValueLabel: {
                            Text("2.0x")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
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
            .onChange(of: scannedConfig) { oldValue, newValue in
                // Only process if we have a new config and haven't processed it yet
                guard let config = newValue else {
                    // If config is cleared (nil), reset the processing flag
                    if newValue == nil && oldValue != nil {
                        hasProcessedScan = false
                        print("📱 Scanned config cleared, ready for new scan")
                    }
                    return
                }
                
                // Prevent processing the same scan multiple times
                guard !hasProcessedScan else {
                    print("ℹ️ QR Code: Already processed this scan, skipping")
                    return
                }
                
                // Always process new scan, even if same tunnel ID
                // This allows reconnecting to the same laptop after disconnection
                hasProcessedScan = true
                print("📱 QR Code scanned successfully")
                print("   Tunnel ID: \(config.tunnelId)")
                print("   Tunnel URL: \(config.tunnelUrl)")
                print("   Key endpoint: \(config.keyEndpoint)")
                
                // Save config (this will replace any existing config)
                settingsManager.laptopConfig = config
                
                // Request ephemeral keys from laptop
                Task {
                    await requestEphemeralKeys(config: config, manager: settingsManager)
                }
            }
            .onChange(of: settingsManager.laptopConfig) { oldValue, newValue in
                // When config is cleared (disconnected), reset scan state
                if newValue == nil && oldValue != nil {
                    hasProcessedScan = false
                    scannedConfig = nil
                    print("📱 Laptop config cleared, scan state reset")
                }
            }
            .onChange(of: showingQRScanner) { oldValue, newValue in
                if newValue {
                    // Scanner is opening - reset all scan state
                    hasProcessedScan = false
                    scannedConfig = nil
                    print("📱 QR Scanner opened, state reset")
                } else {
                    // Scanner is closing - clear scanned config if it wasn't processed
                    // This allows re-scanning if the user didn't complete the connection
                    if scannedConfig != nil && !hasProcessedScan {
                        scannedConfig = nil
                        print("📱 QR Scanner closed, cleared unprocessed scan")
                    }
                }
            }
        }
    }
    
    private func requestEphemeralKeys(config: TunnelConfig, manager: SettingsManager) async {
        print("🔑 Requesting ephemeral keys from laptop...")
        print("   Tunnel URL: \(config.tunnelUrl)")
        print("   Key endpoint: \(config.keyEndpoint)")
        
        let apiClient = APIClient(config: config)
        do {
            let keyResponse = try await apiClient.requestKeys()
            
            // Save keys, endpoints, config and expiration
            await MainActor.run {
                manager.ephemeralKeys = keyResponse.keys
                manager.providerEndpoints = keyResponse.endpoints
                manager.providerConfig = keyResponse.config
                manager.keyExpiresAt = Date(timeIntervalSince1970: TimeInterval(keyResponse.expiresAt))
                print("✅ Ephemeral keys saved successfully")
                print("   Keys expire in: \(keyResponse.expiresIn) seconds")
                if let endpoints = keyResponse.endpoints {
                    print("   STT endpoint: \(endpoints.stt)")
                    print("   TTS endpoint: \(endpoints.tts)")
                }
            }
        } catch {
            print("❌ Error requesting keys: \(error.localizedDescription)")
            print("   Make sure the laptop app and tunnel server are running")
            print("   Check that PUBLIC_HOST in tunnel-server/.env matches your network IP")
            
            // Don't clear the config on key request failure - user might fix the issue
            // The config is still valid, just the keys couldn't be retrieved yet
        }
    }

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}

