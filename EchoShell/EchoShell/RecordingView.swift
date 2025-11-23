//
//  RecordingView.swift
//  EchoShell
//
//  Created by Roman Barinov on 2025.11.21.
//

import SwiftUI
import AVFoundation

struct RecordingView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @EnvironmentObject var settingsManager: SettingsManager
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        } else {
            audioRecorder.startRecording()
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // NEW: Mode indicator
                HStack {
                    Image(systemName: settingsManager.operationMode.icon)
                        .foregroundColor(.blue)
                    Text(settingsManager.operationMode == .standalone ? "Standalone Mode" : "Laptop Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if settingsManager.isLaptopMode {
                        if settingsManager.laptopConfig != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                    .frame(height: 20)
                
                // Main Record Button
                Button(action: {
                    toggleRecording()
                }) {
                    ZStack {
                        // Внешний круг с градиентом
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: audioRecorder.isRecording 
                                        ? [Color.red, Color.pink] 
                                        : [Color.blue, Color.cyan]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 160, height: 160)
                            .shadow(color: audioRecorder.isRecording 
                                ? Color.red.opacity(0.6) 
                                : Color.blue.opacity(0.5), 
                                radius: 20, x: 0, y: 10)
                        
                        // Внутренний круг
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 140, height: 140)
                        
                        // Иконка
                        Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 55, weight: .medium))
                            .foregroundColor(.white)
                            .symbolEffect(.pulse, isActive: audioRecorder.isRecording)
                    }
                }
                .buttonStyle(.plain)
                .disabled(audioRecorder.isTranscribing || settingsManager.apiKey.isEmpty)
                .scaleEffect(audioRecorder.isRecording ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: audioRecorder.isRecording)
                .padding(.horizontal, 30)
                    
                    // Status text
                    if audioRecorder.isRecording {
                        Text("Recording...")
                            .font(.title3)
                            .foregroundColor(.red)
                            .fontWeight(.semibold)
                    } else if settingsManager.apiKey.isEmpty {
                        Text("Please configure API key in Settings")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    } else {
                        Text("Tap to Record")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                        .frame(height: 20)
                    
                    // Индикатор распознавания
                    if audioRecorder.isTranscribing {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Transcribing...")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)
                    }
                    
                    // Отображение последней транскрипции и статистики
                    if !audioRecorder.recognizedText.isEmpty && !audioRecorder.isTranscribing {
                        VStack(alignment: .leading, spacing: 16) {
                            // Header
                            HStack {
                                Image(systemName: "text.bubble.fill")
                                    .foregroundColor(.blue)
                                Text("Last Transcription")
                                    .font(.headline)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            
                            // Transcription text
                            Text(audioRecorder.recognizedText)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineLimit(nil)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(12)
                                .padding(.horizontal, 20)
                            
                            // Статистика
                            if audioRecorder.lastRecordingDuration > 0 {
                                VStack(spacing: 12) {
                                    Divider()
                                        .padding(.horizontal, 20)
                                    
                                    // Первая строка: длительность, стоимость, время обработки
                                    HStack(spacing: 16) {
                                        // Длительность записи
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "mic.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                                Text("Recording")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Text(String(format: "%.1f s", audioRecorder.lastRecordingDuration))
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                        }
                                        
                                        Spacer()
                                        
                                        // Стоимость
                                        if audioRecorder.lastTranscriptionCost > 0 {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "dollarsign.circle")
                                                        .font(.caption)
                                                        .foregroundColor(.green)
                                                    Text("Cost")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Text(String(format: "$%.4f", audioRecorder.lastTranscriptionCost))
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        // Время обработки
                                        if audioRecorder.lastTranscriptionDuration > 0 {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "hourglass")
                                                        .font(.caption)
                                                        .foregroundColor(.orange)
                                                    Text("Processing")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Text(String(format: "%.1f s", audioRecorder.lastTranscriptionDuration))
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    
                                    // Вторая строка: сетевой трафик
                                    if audioRecorder.lastNetworkUsage.sent > 0 || audioRecorder.lastNetworkUsage.received > 0 {
                                        HStack(spacing: 16) {
                                            // Отправлено
                                            if audioRecorder.lastNetworkUsage.sent > 0 {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "arrow.up.circle")
                                                            .font(.caption)
                                                            .foregroundColor(.purple)
                                                        Text("Upload")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Text(formatBytes(audioRecorder.lastNetworkUsage.sent))
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            // Получено
                                            if audioRecorder.lastNetworkUsage.received > 0 {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "arrow.down.circle")
                                                            .font(.caption)
                                                            .foregroundColor(.purple)
                                                        Text("Download")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Text(formatBytes(audioRecorder.lastNetworkUsage.received))
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                }
                                            }
                                            
                                            Spacer()
                                        }
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                    
                Spacer()
                    .frame(height: 30)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .onAppear {
            // Configure AudioRecorder with settings
            audioRecorder.configure(with: settingsManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TranscriptionStatsUpdated"))) { notification in
            print("📱 iOS RecordingView: Received TranscriptionStatsUpdated notification")
            if let userInfo = notification.userInfo {
                print("   📊 Updating RecordingView with new transcription:")
                print("      Text length: \((userInfo["text"] as? String ?? "").count) chars")
                
                // Update AudioRecorder with stats from Watch
                audioRecorder.recognizedText = userInfo["text"] as? String ?? ""
                audioRecorder.lastRecordingDuration = userInfo["recordingDuration"] as? TimeInterval ?? 0
                audioRecorder.lastTranscriptionCost = userInfo["transcriptionCost"] as? Double ?? 0
                audioRecorder.lastTranscriptionDuration = userInfo["processingTime"] as? TimeInterval ?? 0
                audioRecorder.lastNetworkUsage = (
                    sent: userInfo["uploadSize"] as? Int64 ?? 0,
                    received: userInfo["downloadSize"] as? Int64 ?? 0
                )
                
                print("   ✅ RecordingView updated successfully")
            }
        }
    }
    
    // Форматирование байтов в читаемый формат
    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1.0 {
            return "\(bytes) B"
        } else if kb < 1024.0 {
            return String(format: "%.0f KB", kb)
        } else {
            let mb = kb / 1024.0
            return String(format: "%.2f MB", mb)
        }
    }
}

#Preview {
    RecordingView()
        .environmentObject(SettingsManager())
}

