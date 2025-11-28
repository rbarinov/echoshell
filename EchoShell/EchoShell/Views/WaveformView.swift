//
//  WaveformView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Waveform visualization component for audio messages (Telegram-style)
//

import SwiftUI

struct WaveformView: View {
    let barCount: Int
    let isPlaying: Bool
    let progress: Double // 0.0 to 1.0
    let color: Color
    let height: CGFloat
    
    @State private var animationPhase: Double = 0
    
    init(
        barCount: Int = 12,
        isPlaying: Bool = false,
        progress: Double = 0.0,
        color: Color = .primary,
        height: CGFloat = 20
    ) {
        self.barCount = barCount
        self.isPlaying = isPlaying
        self.progress = progress
        self.color = color
        self.height = height
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(
                        width: 2,
                        height: barHeight(for: index)
                    )
                    .opacity(barOpacity(for: index))
            }
        }
        .frame(height: height)
        .onAppear {
            if isPlaying {
                startAnimation()
            }
        }
        .onChange(of: isPlaying) { oldValue, newValue in
            if newValue {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        
        if isPlaying {
            // Animated waveform - bars pulse at different rates
            let phase = (animationPhase + Double(index) * 0.3).truncatingRemainder(dividingBy: 2 * .pi)
            let amplitude = sin(phase) * 0.5 + 0.5 // 0.0 to 1.0
            return baseHeight + (height - baseHeight) * amplitude
        } else {
            // Static waveform - bars show progress
            let progressPosition = Double(index) / Double(barCount)
            if progressPosition <= progress {
                // Bars before progress point have random heights
                let randomSeed = sin(Double(index) * 0.5) * 0.5 + 0.5
                return baseHeight + (height - baseHeight) * randomSeed
            } else {
                // Bars after progress point are minimal
                return baseHeight
            }
        }
    }
    
    private func barOpacity(for index: Int) -> Double {
        if isPlaying {
            // All bars visible when playing
            return 0.8
        } else {
            // Bars before progress are visible, after are dimmed
            let progressPosition = Double(index) / Double(barCount)
            return progressPosition <= progress ? 0.8 : 0.3
        }
    }
    
    private func startAnimation() {
        withAnimation(
            .linear(duration: 1.0)
            .repeatForever(autoreverses: false)
        ) {
            animationPhase = 2 * .pi
        }
    }
    
    private func stopAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            animationPhase = 0
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        WaveformView(isPlaying: true, color: .blue)
        WaveformView(isPlaying: false, progress: 0.5, color: .blue)
        WaveformView(isPlaying: false, progress: 1.0, color: .purple)
    }
    .padding()
}

