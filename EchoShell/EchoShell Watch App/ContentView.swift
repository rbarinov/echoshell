//
//  ContentView.swift
//  EchoShell Watch App
//
//  Created by Roman Barinov on 2025.11.20.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @ObservedObject private var watchConnectivity = WatchConnectivityManager.shared
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        } else {
            audioRecorder.startRecording()
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Статус подключения к iPhone (компактный)
                if !watchConnectivity.isPhoneConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 10))
                        Text("Standalone")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.orange)
                    .padding(.top, 5)
                    .padding(.bottom, 5)
                } else if watchConnectivity.apiKey.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("Setup on iPhone")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.red)
                    .padding(.top, 5)
                    .padding(.bottom, 5)
                }
                
                Spacer()
                    .frame(height: 10)
                
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
                            .frame(width: 100, height: 100)
                            .shadow(color: audioRecorder.isRecording 
                                ? Color.red.opacity(0.6) 
                                : Color.blue.opacity(0.5), 
                                radius: 15, x: 0, y: 8)
                        
                        // Внутренний круг
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 88, height: 88)
                        
                        // Иконка
                        Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.white)
                            .symbolEffect(.pulse, isActive: audioRecorder.isRecording)
                    }
                }
                .buttonStyle(.plain)
                .disabled(audioRecorder.isTranscribing)
                .scaleEffect(audioRecorder.isRecording ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: audioRecorder.isRecording)
                .padding(.bottom, 15)
                
                // Индикатор распознавания
                if audioRecorder.isTranscribing {
                    VStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Transcribing...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 10)
                }
                
                // Отображение последней транскрипции и статистики
                if !audioRecorder.recognizedText.isEmpty && !audioRecorder.isTranscribing {
                    VStack(alignment: .leading, spacing: 6) {
                        // Транскрипция
                        Text(audioRecorder.recognizedText)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(nil)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        
                        // Статистика
                        if audioRecorder.lastRecordingDuration > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                // Первая строка: длительность, стоимость, время обработки
                                HStack(spacing: 6) {
                                    // Длительность записи
                                    HStack(spacing: 2) {
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(.blue)
                                        Text(String(format: "%.1fs", audioRecorder.lastRecordingDuration))
                                            .font(.system(size: 9))
                                    }
                                    
                                    // Стоимость
                                    if audioRecorder.lastTranscriptionCost > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: "dollarsign.circle")
                                                .font(.system(size: 8))
                                                .foregroundColor(.green)
                                            Text(String(format: "$%.4f", audioRecorder.lastTranscriptionCost))
                                                .font(.system(size: 9))
                                        }
                                    }
                                    
                                    // Время обработки
                                    if audioRecorder.lastTranscriptionDuration > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: "hourglass")
                                                .font(.system(size: 8))
                                                .foregroundColor(.orange)
                                            Text(String(format: "%.1fs", audioRecorder.lastTranscriptionDuration))
                                                .font(.system(size: 9))
                                        }
                                    }
                                }
                                
                                // Вторая строка: сетевой трафик
                                if audioRecorder.lastNetworkUsage.sent > 0 || audioRecorder.lastNetworkUsage.received > 0 {
                                    HStack(spacing: 6) {
                                        // Отправлено
                                        if audioRecorder.lastNetworkUsage.sent > 0 {
                                            HStack(spacing: 2) {
                                                Image(systemName: "arrow.up.circle")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.purple)
                                                Text(formatBytes(audioRecorder.lastNetworkUsage.sent))
                                                    .font(.system(size: 9))
                                            }
                                        }
                                        
                                        // Получено
                                        if audioRecorder.lastNetworkUsage.received > 0 {
                                            HStack(spacing: 2) {
                                                Image(systemName: "arrow.down.circle")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.purple)
                                                Text(formatBytes(audioRecorder.lastNetworkUsage.received))
                                                    .font(.system(size: 9))
                                            }
                                        }
                                    }
                                }
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
                
                Spacer()
                    .frame(height: 10)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
        }
        .onLongPressGesture(minimumDuration: 0.2) {
            // Длительное нажатие на экран переключает запись
            toggleRecording()
        }
    }
    
    // Форматирование байтов в читаемый формат
    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1.0 {
            return "\(bytes)B"
        } else if kb < 1024.0 {
            return String(format: "%.0fKB", kb)
        } else {
            let mb = kb / 1024.0
            return String(format: "%.2fMB", mb)
        }
    }
}

#Preview {
    ContentView()
}
