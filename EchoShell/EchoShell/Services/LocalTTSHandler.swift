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
    private let endpoint: String
    
    init(apiKey: String, endpoint: String) {
        self.apiKey = apiKey
        self.endpoint = endpoint
    }
    
    func synthesize(text: String, voice: String = "alloy", speed: Double = 1.0, language: String? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Laptop-Auth-Key")
        
        var body: [String: Any] = [
            "text": text,
            "voice": voice,
            "speed": speed
        ]
        
        // Add language if provided (for voice selection hints)
        if let lang = language {
            body["language"] = lang
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TTSError.requestFailed
        }
        
        // Parse response - should contain base64 audio
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let audioBase64 = json["audio"] as? String,
           let audioData = Data(base64Encoded: audioBase64) {
            print("✅ TTS audio generated, size: \(audioData.count) bytes")
            return audioData
        } else {
            throw TTSError.requestFailed
        }
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
