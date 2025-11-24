//
//  APIClient.swift
//  EchoShell Watch App
//
//  Created for Voice-Controlled Terminal Management System
//  Handles HTTP communication with laptop app
//

import Foundation

class APIClient: ObservableObject {
    @Published var isConnected = false
    
    private let config: TunnelConfig
    private let deviceId: String
    private var currentKeys: KeyResponse.Keys?
    
    init(config: TunnelConfig) {
        self.config = config
        // Use Watch-specific device identifier
        self.deviceId = UserDefaults.standard.string(forKey: "watchDeviceId") ?? {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: "watchDeviceId")
            return id
        }()
    }
    
    // Helper to add auth header to requests
    private func addAuthHeader(to request: inout URLRequest) {
        request.setValue(config.authKey, forHTTPHeaderField: "X-Laptop-Auth-Key")
    }
    
    // MARK: - Key Management
    
    func requestKeys() async throws -> KeyResponse {
        let url = URL(string: "\(config.keyEndpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        
        let body: [String: Any] = [
            "device_id": deviceId,
            "tunnel_id": config.tunnelId,
            "duration_seconds": 3600,
            "permissions": ["stt", "tts"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if let urlError = error as? URLError {
                print("❌ APIClient: Network error - \(urlError.localizedDescription)")
                if urlError.code == .cannotConnectToHost || urlError.code == .networkConnectionLost {
                    throw APIError.connectionRefused
                }
            }
            throw APIError.networkError
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ APIClient: Invalid response type")
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ APIClient: Request failed with status \(httpResponse.statusCode)")
            print("   Response: \(responseBody)")
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
        addAuthHeader(to: &request)
        
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
        addAuthHeader(to: &request)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct SessionsResponse: Codable {
            let sessions: [SessionInfo]?
            struct SessionInfo: Codable {
                let session_id: String
                let working_dir: String
                let terminal_type: String?
                let name: String?
            }
        }
        
        guard let response = try? JSONDecoder().decode(SessionsResponse.self, from: data),
              let sessions = response.sessions else {
            print("ℹ️ No sessions found or invalid response, returning empty list")
            return []
        }
        
        return sessions.map { info in
            let terminalType = TerminalType(rawValue: info.terminal_type ?? "regular") ?? .regular
            return TerminalSession(
                id: info.session_id,
                workingDir: info.working_dir,
                isActive: true,
                lastOutput: "",
                lastUpdate: Date(),
                terminalType: terminalType,
                name: info.name,
                cursorAgentWorkingDir: terminalType == .cursorAgent ? info.working_dir : nil
            )
        }
    }
    
    func createSession(
        terminalType: TerminalType = .regular,
        workingDir: String? = nil,
        name: String? = nil
    ) async throws -> TerminalSession {
        let url = URL(string: "\(config.apiBaseUrl)/terminal/create")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        addAuthHeader(to: &request)
        
        var body: [String: Any] = [
            "terminal_type": terminalType.rawValue
        ]
        if let workingDir = workingDir {
            body["working_dir"] = workingDir
        }
        if let name = name {
            body["name"] = name
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct CreateResponse: Codable {
            let session_id: String
            let working_dir: String
            let terminal_type: String?
            let name: String?
            let status: String
        }
        
        let response = try JSONDecoder().decode(CreateResponse.self, from: data)
        let responseTerminalType = TerminalType(rawValue: response.terminal_type ?? "regular") ?? .regular
        
        return TerminalSession(
            id: response.session_id,
            workingDir: response.working_dir,
            isActive: true,
            lastOutput: "",
            lastUpdate: Date(),
            terminalType: responseTerminalType,
            name: response.name,
            cursorAgentWorkingDir: responseTerminalType == .cursorAgent ? response.working_dir : nil
        )
    }
    
    func getHistory(sessionId: String) async throws -> String {
        let url = URL(string: "\(config.apiBaseUrl)/terminal/\(sessionId)/history")!
        var request = URLRequest(url: url)
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        addAuthHeader(to: &request)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct HistoryResponse: Codable {
            let session_id: String
            let history: String
        }
        
        let response = try JSONDecoder().decode(HistoryResponse.self, from: data)
        return response.history
    }
    
    func executeCommand(sessionId: String, command: String) async throws -> String {
        let url = URL(string: "\(config.apiBaseUrl)/terminal/\(sessionId)/execute")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        addAuthHeader(to: &request)
        
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
    
    func resizeTerminal(sessionId: String, cols: Int, rows: Int) async throws {
        let url = URL(string: "\(config.apiBaseUrl)/terminal/\(sessionId)/resize")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        addAuthHeader(to: &request)
        
        let body: [String: Any] = [
            "cols": cols,
            "rows": rows
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }
    
    func deleteSession(sessionId: String) async throws {
        let url = URL(string: "\(config.apiBaseUrl)/terminal/\(sessionId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        addAuthHeader(to: &request)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }
    
    func renameSession(sessionId: String, name: String) async throws {
        let url = URL(string: "\(config.apiBaseUrl)/terminal/\(sessionId)/rename")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        addAuthHeader(to: &request)
        
        let body: [String: Any] = [
            "name": name
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }
    
    func executeAgentCommand(sessionId: String, command: String) async throws -> String {
        let url = URL(string: "\(config.apiBaseUrl)/agent/execute")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        addAuthHeader(to: &request)
        
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
    case connectionRefused
    
    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Request failed - check if laptop app is running"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError:
            return "Network error occurred - check your connection"
        case .connectionRefused:
            return "Connection refused - check PUBLIC_HOST in tunnel-server/.env"
        }
    }
}

