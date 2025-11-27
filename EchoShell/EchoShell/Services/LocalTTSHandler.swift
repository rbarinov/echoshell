//
//  LocalTTSHandler.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Handles remote TTS synthesis via laptop proxy endpoint
//

import Foundation
import AVFoundation

class LocalTTSHandler {
    private let laptopAuthKey: String
    private let endpoint: String
    
    init(laptopAuthKey: String, endpoint: String) {
        self.laptopAuthKey = laptopAuthKey
        self.endpoint = endpoint
    }
    
    func synthesize(text: String, speed: Double = 1.0, language: String? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(laptopAuthKey, forHTTPHeaderField: "X-Laptop-Auth-Key")
        
        var body: [String: Any] = [
            "text": text,
            "speed": speed
        ]
        
        // Add language if provided (for voice selection hints)
        // Note: Voice is controlled by server configuration, not sent from client
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
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("📦 TTS response JSON keys: \(json.keys.joined(separator: ", "))")
            
            if let audioBase64 = json["audio"] as? String {
                print("📦 TTS audio base64 length: \(audioBase64.count) characters")
                
                if let audioData = Data(base64Encoded: audioBase64) {
                    print("✅ TTS audio decoded successfully, size: \(audioData.count) bytes")
                    return audioData
                } else {
                    print("❌ TTS audio base64 decoding failed")
                    // Try to get error message from response
                    if let error = json["error"] as? String {
                        print("❌ TTS error from server: \(error)")
                    }
                    throw TTSError.requestFailed
                }
            } else {
                print("❌ TTS response missing 'audio' field")
                if let error = json["error"] as? String {
                    print("❌ TTS error from server: \(error)")
                }
                throw TTSError.requestFailed
            }
        } else {
            print("❌ TTS response is not valid JSON")
            print("❌ Response data: \(String(data: data, encoding: .utf8)?.prefix(200) ?? "invalid UTF-8")")
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
