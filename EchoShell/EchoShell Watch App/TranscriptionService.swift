//
//  TranscriptionService.swift
//  EchoShell Watch App
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
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
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
                completion(.success((text: result.text, networkUsage: (sent: sentBytes, received: receivedBytes))))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - Models

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

