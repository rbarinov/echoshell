//
//  LaptopHealthChecker.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Health check service for laptop connection status
//

import Foundation
import Combine

class LaptopHealthChecker: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastCheckTime: Date?
    @Published var lastError: String?
    
    private var config: TunnelConfig?
    private var healthCheckTimer: Timer?
    private let checkInterval: TimeInterval = 10.0 // Check every 10 seconds
    private let timeout: TimeInterval = 5.0 // 5 second timeout
    
    // Health check endpoint - check tunnel connection status via laptop app
    private var healthCheckURL: URL? {
        guard let config = config else { return nil }
        // Use apiBaseUrl to check tunnel status endpoint
        // Endpoint: /api/:tunnelId/tunnel-status (proxied to laptop app)
        return URL(string: "\(config.apiBaseUrl)/tunnel-status")
    }
    
    func start(config: TunnelConfig) {
        self.config = config
        stop() // Stop any existing timer
        
        // Perform initial check immediately
        performHealthCheck()
        
        // Schedule periodic checks on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Create timer on main thread
            self.healthCheckTimer = Timer.scheduledTimer(withTimeInterval: self.checkInterval, repeats: true) { [weak self] _ in
                self?.performHealthCheck()
            }
            // Add timer to RunLoop to keep it running
            if let timer = self.healthCheckTimer {
                RunLoop.current.add(timer, forMode: .common)
            }
            print("🏥 LaptopHealthChecker: Started health checks (interval: \(self.checkInterval)s)")
        }
    }
    
    func stop() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        config = nil
        connectionState = .disconnected
        lastCheckTime = nil
        lastError = nil
        print("🏥 LaptopHealthChecker: Stopped health checks")
    }
    
    private func performHealthCheck() {
        guard let url = healthCheckURL,
              let config = config else {
            Task { @MainActor in
                self.connectionState = .disconnected
                self.lastError = "No configuration available"
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Tunnel status endpoint requires X-Laptop-Auth-Key header
        // Request is proxied to laptop app which validates the auth key
        request.setValue(config.authKey, forHTTPHeaderField: "X-Laptop-Auth-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.lastCheckTime = Date()
                
                if let error = error {
                    // Network error
                    if let urlError = error as? URLError {
                        switch urlError.code {
                        case .timedOut:
                            self.connectionState = .dead
                            self.lastError = "Request timeout"
                        case .cannotConnectToHost, .networkConnectionLost:
                            self.connectionState = .disconnected
                            self.lastError = "Cannot connect to host"
                        case .notConnectedToInternet:
                            self.connectionState = .disconnected
                            self.lastError = "No internet connection"
                        default:
                            self.connectionState = .disconnected
                            self.lastError = urlError.localizedDescription
                        }
                    } else {
                        self.connectionState = .disconnected
                        self.lastError = error.localizedDescription
                    }
                    print("❌ LaptopHealthChecker: Health check failed - \(self.lastError ?? "Unknown error")")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.connectionState = .disconnected
                    self.lastError = "Invalid response type"
                    print("❌ LaptopHealthChecker: Invalid response type")
                    return
                }
                
                // Check HTTP status code
                if httpResponse.statusCode == 200 {
                    // Success - laptop is connected and responding
                    // Parse response to verify connection status
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let connected = json["connected"] as? Bool {
                        if connected {
                            if self.connectionState != .connected {
                                print("✅ LaptopHealthChecker: Laptop is connected and responding")
                            }
                            self.connectionState = .connected
                            self.lastError = nil
                        } else {
                            // Laptop responded but reports not connected
                            self.connectionState = .disconnected
                            self.lastError = json["reason"] as? String ?? "Not connected"
                            print("⚠️ LaptopHealthChecker: Laptop reports not connected - \(self.lastError ?? "Unknown")")
                        }
                    } else {
                        // Response format unexpected, but got 200, assume connected
                        self.connectionState = .connected
                        self.lastError = nil
                    }
                } else if httpResponse.statusCode == 401 {
                    // Unauthorized - auth key invalid
                    self.connectionState = .disconnected
                    self.lastError = "Authentication failed"
                    print("⚠️ LaptopHealthChecker: Authentication failed (401)")
                } else if httpResponse.statusCode == 404 {
                    // Endpoint not found or tunnel not found
                    self.connectionState = .disconnected
                    self.lastError = "Not found"
                    print("❌ LaptopHealthChecker: Not found (404) - laptop may not be connected")
                } else if httpResponse.statusCode == 503 {
                    // Service unavailable
                    self.connectionState = .disconnected
                    self.lastError = "Service unavailable"
                    print("⚠️ LaptopHealthChecker: Service unavailable (503)")
                } else {
                    // Other HTTP errors
                    self.connectionState = .disconnected
                    self.lastError = "HTTP \(httpResponse.statusCode)"
                    print("❌ LaptopHealthChecker: HTTP error \(httpResponse.statusCode)")
                }
            }
        }
        
        task.resume()
    }
    
    deinit {
        stop()
    }
}

