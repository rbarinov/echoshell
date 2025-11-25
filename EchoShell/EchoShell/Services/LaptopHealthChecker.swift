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
    
    // Health check endpoint - check tunnel connection status on tunnel server
    private var healthCheckURL: URL? {
        guard let config = config else { return nil }
        // Use apiBaseUrl to check tunnel status endpoint
        // Endpoint: /api/:tunnelId/tunnel-status (defined before proxy to avoid interception)
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
        guard let url = healthCheckURL else {
            Task { @MainActor in
                self.connectionState = .disconnected
                self.lastError = "No configuration available"
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Tunnel status endpoint doesn't require auth key - it's a public endpoint
        // that just checks if tunnel is connected
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
                    // Success - tunnel is connected to laptop
                    // Parse response to verify connection status
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let connected = json["connected"] as? Bool {
                        if connected {
                            if self.connectionState != .connected {
                                print("✅ LaptopHealthChecker: Tunnel is connected to laptop")
                            }
                            self.connectionState = .connected
                            self.lastError = nil
                        } else {
                            // Tunnel exists but not connected
                            self.connectionState = .disconnected
                            self.lastError = json["reason"] as? String ?? "Tunnel not connected"
                            print("⚠️ LaptopHealthChecker: Tunnel exists but not connected - \(self.lastError ?? "Unknown")")
                        }
                    } else {
                        // Response format unexpected, but got 200, assume connected
                        self.connectionState = .connected
                        self.lastError = nil
                    }
                } else if httpResponse.statusCode == 404 {
                    // Tunnel not found - laptop definitely not connected
                    self.connectionState = .disconnected
                    self.lastError = "Tunnel not found"
                    print("❌ LaptopHealthChecker: Tunnel not found (404) - laptop not connected")
                } else if httpResponse.statusCode == 503 {
                    // Tunnel exists but unhealthy (WebSocket closed or no pong)
                    self.connectionState = .disconnected
                    self.lastError = "Tunnel unhealthy"
                    print("⚠️ LaptopHealthChecker: Tunnel unhealthy (503) - laptop disconnected")
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

