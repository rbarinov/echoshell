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
        
        // Создаем multipart/form-data запрос
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Добавляем файл
        if let audioData = try? Data(contentsOf: audioFileURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Добавляем модель
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Добавляем язык (если указан и не "auto")
        if let lang = language, lang != "auto", !lang.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(lang)\r\n".data(using: .utf8)!)
            print("📝 iOS TranscriptionService: Using language: \(lang)")
        } else {
            print("📝 iOS TranscriptionService: Using auto language detection")
        }
        
        // Закрываем boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        let sentBytes = Int64(body.count)
        
        // Отправляем запрос
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
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
                // Если не удалось декодировать, выводим сырой ответ для отладки
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Raw response: \(responseString)")
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

