//
//  APIClient.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Handles HTTP communication with laptop app
//

import Foundation
import UIKit

class APIClient: ObservableObject {
    @Published var isConnected = false
    
    private let config: TunnelConfig
    private let deviceId: String
    private var currentKeys: KeyResponse.Keys?
    
    init(config: TunnelConfig) {
        self.config = config
        self.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
    
    // MARK: - Key Management
    
    func requestKeys() async throws -> KeyResponse {
        let url = URL(string: "\(config.keyEndpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "device_id": deviceId,
            "tunnel_id": config.tunnelId,
            "duration_seconds": 3600,
            "permissions": ["stt", "tts"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
        
        let keyResponse = try JSONDecoder().decode(KeyResponse.self, from: data)
        currentKeys = keyResponse.keys
        
        print("✅ Ephemeral keys received")
        print("   Expires in: \(keyResponse.expiresIn)s")
        
        return keyResponse
    }
    
    func refreshKeys() async throws {
        let url = URL(string: "\(config.apiBaseUrl)/keys/refresh")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "device_id": deviceId,
            "tunnel_id": config.tunnelId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(RefreshResponse.self, from: data)
        
        print("🔄 Keys refreshed, new expiration: \(response.expiresAt)")
    }
    
    // MARK: - Terminal Management
    
    func listSessions() async throws -> [TerminalSession] {
        let url = URL(string: "\(config.apiBaseUrl)/terminal/list")!
        var request = URLRequest(url: url)
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct SessionsResponse: Codable {
            let sessions: [SessionInfo]
            struct SessionInfo: Codable {
                let session_id: String
                let working_dir: String
            }
        }
        
        let response = try JSONDecoder().decode(SessionsResponse.self, from: data)
        
        return response.sessions.map { info in
            TerminalSession(
                id: info.session_id,
                workingDir: info.working_dir,
                isActive: true,
                lastOutput: "",
                lastUpdate: Date()
            )
        }
    }
    
    func createSession(workingDir: String? = nil) async throws -> TerminalSession {
        let url = URL(string: "\(config.apiBaseUrl)/terminal/create")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        
        var body: [String: Any] = [:]
        if let workingDir = workingDir {
            body["working_dir"] = workingDir
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct CreateResponse: Codable {
            let session_id: String
            let working_dir: String
            let status: String
        }
        
        let response = try JSONDecoder().decode(CreateResponse.self, from: data)
        
        return TerminalSession(
            id: response.session_id,
            workingDir: response.working_dir,
            isActive: true,
            lastOutput: "",
            lastUpdate: Date()
        )
    }
    
    func executeCommand(sessionId: String, command: String) async throws -> String {
        let url = URL(string: "\(config.apiBaseUrl)/terminal/\(sessionId)/execute")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        
        let body: [String: Any] = [
            "command": command
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct ExecuteResponse: Codable {
            let output: String
        }
        
        let response = try JSONDecoder().decode(ExecuteResponse.self, from: data)
        return response.output
    }
    
    func executeAgentCommand(sessionId: String, command: String) async throws -> String {
        let url = URL(string: "\(config.apiBaseUrl)/agent/execute")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        
        let body: [String: Any] = [
            "command": command,
            "session_id": sessionId,
            "use_agent": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct AgentResponse: Codable {
            let result: String
            let type: String
        }
        
        let response = try JSONDecoder().decode(AgentResponse.self, from: data)
        return response.result
    }
}

// MARK: - Supporting Types

struct RefreshResponse: Codable {
    let status: String
    let expiresAt: Int
    let expiresIn: Int
    
    enum CodingKeys: String, CodingKey {
        case status
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
    }
}

enum APIError: Error, LocalizedError {
    case requestFailed
    case invalidResponse
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Request failed"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError:
            return "Network error occurred"
        }
    }
}
