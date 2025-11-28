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
    @StateObject private var laptopHealthChecker = LaptopHealthChecker()
    @State private var showingQRScanner = false
    @State private var scannedConfig: TunnelConfig?
    @State private var hasProcessedScan = false // Prevent processing the same scan multiple times
    @State private var showingDisconnectConfirmation = false
    @State private var showingMagicLinkInput = false
    @State private var magicLinkInput = ""
    
    var body: some View {
        Form {
            // Laptop Connection Section
            Section(header: Text("Laptop Connection")) {
                    if let config = settingsManager.laptopConfig {
                        // Connected
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tunnel ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(config.tunnelId)
                                .font(.footnote)
                                .fontDesign(.monospaced)
                        }
                        
                        Button(role: .destructive) {
                            showingDisconnectConfirmation = true
                        } label: {
                            Text("Disconnect from Laptop")
                        }
                        .confirmationDialog("Disconnect from Laptop", isPresented: $showingDisconnectConfirmation, titleVisibility: .visible) {
                            Button("Disconnect", role: .destructive) {
                                // Clear all connection state
                                settingsManager.laptopConfig = nil
                                // Reset scan state to allow re-scanning
                                hasProcessedScan = false
                                scannedConfig = nil
                                print("📱 Disconnected from laptop, ready for new scan")
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Are you sure you want to disconnect from your laptop? You will need to scan the QR code again to reconnect.")
                        }
                    } else {
                        // Not connected
                        Button {
                            showingQRScanner = true
                        } label: {
                            Label("Scan QR Code from Laptop", systemImage: "qrcode.viewfinder")
                        }
                        
                        Button {
                            showingMagicLinkInput = true
                        } label: {
                            Label("Enter Magic Link", systemImage: "link")
                        }
                        
                        Text("Open the laptop app and scan the QR code or paste the magic link to connect")
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
                       footer: Text("Select language for better accuracy. Auto mode supports English and Russian.")) {
                    Picker("Language", selection: $settingsManager.transcriptionLanguage) {
                        ForEach(TranscriptionLanguage.allCases.filter { $0 != .georgian }) { language in
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
                       footer: Text("Voice responses are synthesized on your laptop and streamed to your device. Adjust the playback speed (0.7x to 1.2x).")) {
                    Toggle(isOn: $settingsManager.ttsEnabled) {
                        HStack {
                            Image(systemName: settingsManager.ttsEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill")
                                .foregroundColor(settingsManager.ttsEnabled ? .green : .gray)
                            Text("Voice Responses")
                        }
                    }
                    
                    if settingsManager.ttsEnabled {
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
                            
                            Slider(value: $settingsManager.ttsSpeed, in: 0.7...1.2, step: 0.1) {
                                Text("Speed")
                            } minimumValueLabel: {
                                Text("0.7x")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("1.2x")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
        }
        .sheet(isPresented: $showingQRScanner) {
            QRScannerView(scannedConfig: $scannedConfig)
        }
        .sheet(isPresented: $showingMagicLinkInput) {
            MagicLinkInputView(
                magicLink: $magicLinkInput,
                onConnect: { link in
                    // Parse magic link and create config
                    if let config = parseMagicLink(link) {
                        scannedConfig = config
                        showingMagicLinkInput = false
                        magicLinkInput = ""
                    }
                }
            )
        }
        .task {
            if let config = settingsManager.laptopConfig {
                laptopHealthChecker.start(config: config)
            }
        }
        .onChange(of: settingsManager.laptopConfig) { oldValue, newValue in
            if let config = newValue {
                laptopHealthChecker.start(config: config)
            } else {
                laptopHealthChecker.stop()
            }
        }
        .onDisappear {
            laptopHealthChecker.stop()
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
    
    // Parse magic link: echoshell://connect?tunnelId=...&tunnelUrl=...&keyEndpoint=...&authKey=...
    private func parseMagicLink(_ link: String) -> TunnelConfig? {
        guard let url = URL(string: link),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            print("❌ Invalid magic link format")
            return nil
        }
        
        var tunnelId: String?
        var tunnelUrl: String?
        var wsUrl: String?
        var keyEndpoint: String?
        var authKey: String?
        
        for item in queryItems {
            switch item.name {
            case "tunnelId":
                tunnelId = item.value
            case "tunnelUrl":
                tunnelUrl = item.value
            case "wsUrl":
                wsUrl = item.value
            case "keyEndpoint":
                keyEndpoint = item.value
            case "authKey":
                authKey = item.value
            default:
                break
            }
        }
        
        guard let tid = tunnelId,
              let turl = tunnelUrl,
              let wurl = wsUrl,
              let kep = keyEndpoint,
              let akey = authKey else {
            print("❌ Missing required parameters in magic link")
            return nil
        }
        
        let config = TunnelConfig(
            tunnelId: tid,
            tunnelUrl: turl,
            wsUrl: wurl,
            keyEndpoint: kep,
            authKey: akey
        )
        
        print("✅ Parsed magic link successfully")
        print("   Tunnel ID: \(tid)")
        print("   Tunnel URL: \(turl)")
        
        return config
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}

