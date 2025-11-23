//
//  LocalTTSHandler.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Handles local TTS synthesis using OpenAI API with ephemeral keys
//

import Foundation
import AVFoundation

class LocalTTSHandler {
    private let apiKey: String
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func synthesize(text: String, voice: String = "alloy", speed: Double = 1.0) async throws -> Data {
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "tts-1-hd",
            "input": text,
            "voice": voice,
            "speed": speed
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TTSError.requestFailed
        }
        
        print("✅ TTS audio generated, size: \(data.count) bytes")
        
        return data
    }
}

enum TTSError: Error, LocalizedError {
    case requestFailed
    case invalidKey
    
    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "TTS request failed"
        case .invalidKey:
            return "Invalid API key"
        }
    }
}
