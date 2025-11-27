//
//  TranscriptionService.swift
//  EchoShell (iOS)
//
//  Created by Roman Barinov on 2025.11.21.
//

import Foundation

class TranscriptionService {
    private let laptopAuthKey: String
    private let endpoint: String
    
    init(laptopAuthKey: String, endpoint: String) {
        self.laptopAuthKey = laptopAuthKey
        self.endpoint = endpoint
    }
    
    func transcribe(audioFileURL: URL, language: String? = nil, completion: @escaping (Result<(text: String, networkUsage: (sent: Int64, received: Int64)), Error>) -> Void) {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            completion(.failure(TranscriptionError.fileNotFound))
            return
        }
        
        guard let audioData = try? Data(contentsOf: audioFileURL) else {
            completion(.failure(TranscriptionError.fileNotFound))
            return
        }
        
        let audioBase64 = audioData.base64EncodedString()
        let sentBytes = Int64(audioBase64.count)
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(laptopAuthKey, forHTTPHeaderField: "X-Laptop-Auth-Key")
        
        var body: [String: Any] = ["audio": audioBase64]
        if let lang = language, lang != "auto", !lang.isEmpty {
            body["language"] = lang
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // Add timeout configuration for better stability
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        let session = URLSession(configuration: configuration)
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                let errorDescription = error.localizedDescription
                print("❌ iOS TranscriptionService: Network error: \(errorDescription)")
                print("❌ iOS TranscriptionService: Error type: \(type(of: error))")
                
                // Check if this is a timeout or connection error
                if errorDescription.contains("timeout") || 
                   errorDescription.contains("timed out") ||
                   errorDescription.contains("network") ||
                   errorDescription.contains("connection") {
                    print("⚠️ iOS TranscriptionService: Network timeout/connection error - may be transient")
                }
                
                completion(.failure(error))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    let errorMessage = "HTTP \(httpResponse.statusCode)"
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("❌ iOS TranscriptionService: \(errorMessage) - \(errorString.prefix(500))")
                    } else {
                        print("❌ iOS TranscriptionService: \(errorMessage) - No error details")
                    }
                    
                    // Provide more specific error for 5xx errors (server errors - may be transient)
                    if (500...599).contains(httpResponse.statusCode) {
                        print("⚠️ iOS TranscriptionService: Server error \(httpResponse.statusCode) - may be transient")
                    }
                    
                    completion(.failure(TranscriptionError.invalidResponse))
                    return
                }
            }
            
            guard let data = data else {
                completion(.failure(TranscriptionError.noData))
                return
            }
            
            let receivedBytes = Int64(data.count)
            
            do {
                let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
                print("✅ iOS TranscriptionService: Transcription successful: \"\(result.text)\"")
                completion(.success((text: result.text, networkUsage: (sent: sentBytes, received: receivedBytes))))
            } catch {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ iOS TranscriptionService: Failed to decode response")
                    print("   Raw response: \(responseString)")
                }
                completion(.failure(error))
            }
        }.resume()
    }
}

struct TranscriptionResponse: Codable {
    let text: String
}

enum TranscriptionError: Error, LocalizedError {
    case fileNotFound
    case noData
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .noData:
            return "No data received from server"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

