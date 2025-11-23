//
//  TranscriptionService.swift
//  EchoShell (iOS)
//
//  Created by Roman Barinov on 2025.11.21.
//

import Foundation

class TranscriptionService {
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/audio/transcriptions"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func transcribe(audioFileURL: URL, language: String? = nil, completion: @escaping (Result<(text: String, networkUsage: (sent: Int64, received: Int64)), Error>) -> Void) {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            completion(.failure(TranscriptionError.fileNotFound))
            return
        }
        
        // Create multipart/form-data request
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add file
        if let audioData = try? Data(contentsOf: audioFileURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Add model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Add language (if specified and not "auto")
        if let lang = language, lang != "auto", !lang.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(lang)\r\n".data(using: .utf8)!)
            print("📝 iOS TranscriptionService: Using language: \(lang)")
        } else {
            print("📝 iOS TranscriptionService: Using auto language detection")
        }
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        let sentBytes = Int64(body.count)
        
        // Send request
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ iOS TranscriptionService: Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    let errorMessage = "HTTP \(httpResponse.statusCode)"
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("❌ iOS TranscriptionService: \(errorMessage) - \(errorString)")
                    } else {
                        print("❌ iOS TranscriptionService: \(errorMessage)")
                    }
                    completion(.failure(TranscriptionError.invalidResponse))
                    return
                }
            }
            
            guard let data = data else {
                print("❌ iOS TranscriptionService: No data received")
                completion(.failure(TranscriptionError.noData))
                return
            }
            
            let receivedBytes = Int64(data.count)
            print("📱 iOS TranscriptionService: Received \(receivedBytes) bytes")
            
            do {
                let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
                print("✅ iOS TranscriptionService: Transcription successful: \"\(result.text)\"")
                completion(.success((text: result.text, networkUsage: (sent: sentBytes, received: receivedBytes))))
            } catch {
                // If decoding failed, output raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ iOS TranscriptionService: Failed to decode response")
                    print("   Raw response: \(responseString)")
                } else {
                    print("❌ iOS TranscriptionService: Failed to decode response (not UTF-8)")
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

