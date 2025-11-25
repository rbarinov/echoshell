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
        print("🏥 LaptopHealthChecker: Starting with config (tunnelId: \(config.tunnelId), apiBaseUrl: \(config.apiBaseUrl))")
        
        // Stop any existing timer first (but don't clear config yet)
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        
        // Set new config AFTER stopping timer
        self.config = config
        print("🏥 LaptopHealthChecker: Config set (tunnelId: \(self.config?.tunnelId ?? "nil"))")
        
        // Perform initial check immediately
        print("🏥 LaptopHealthChecker: Performing initial health check...")
        performHealthCheck()
        
        // Schedule periodic checks on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Create timer on main thread
            self.healthCheckTimer = Timer.scheduledTimer(withTimeInterval: self.checkInterval, repeats: true) { [weak self] _ in
                print("🏥 LaptopHealthChecker: Timer triggered, performing health check...")
                self?.performHealthCheck()
            }
            // Add timer to RunLoop to keep it running
            if let timer = self.healthCheckTimer {
                RunLoop.current.add(timer, forMode: .common)
            }
            print("🏥 LaptopHealthChecker: Started health checks (interval: \(self.checkInterval)s)")
            print("🏥 LaptopHealthChecker: Config after timer setup: \(self.config?.tunnelId ?? "nil")")
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
        // Check config first
        guard let currentConfig = config else {
            print("❌ LaptopHealthChecker: Cannot perform health check - config is nil")
            print("   Attempting to stop timer to prevent further errors...")
            healthCheckTimer?.invalidate()
            healthCheckTimer = nil
            Task { @MainActor in
                self.connectionState = .disconnected
                self.lastError = "No configuration available"
            }
            return
        }
        
        guard let url = healthCheckURL else {
            print("❌ LaptopHealthChecker: Cannot perform health check - healthCheckURL is nil")
            print("   Config exists (tunnelId: \(currentConfig.tunnelId), apiBaseUrl: \(currentConfig.apiBaseUrl))")
            Task { @MainActor in
                self.connectionState = .disconnected
                self.lastError = "Invalid URL"
            }
            return
        }
        
        print("🏥 LaptopHealthChecker: Performing health check to \(url.absoluteString)")
        print("   Auth key length: \(currentConfig.authKey.count) chars")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Tunnel status endpoint requires X-Laptop-Auth-Key header
        // Request is proxied to laptop app which validates the auth key
        request.setValue(currentConfig.authKey, forHTTPHeaderField: "X-Laptop-Auth-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        
        print("🏥 LaptopHealthChecker: Sending request with headers:")
        print("   X-Laptop-Auth-Key: \(String(currentConfig.authKey.prefix(8)))...")
        print("   Accept: application/json")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.lastCheckTime = Date()
                print("🏥 LaptopHealthChecker: Received response at \(self.lastCheckTime?.description ?? "unknown time")")
                
                if let error = error {
                    print("❌ LaptopHealthChecker: Request error: \(error.localizedDescription)")
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
                    print("❌ LaptopHealthChecker: Invalid response type (not HTTPURLResponse)")
                    return
                }
                
                print("🏥 LaptopHealthChecker: HTTP Status: \(httpResponse.statusCode)")
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("🏥 LaptopHealthChecker: Response body: \(responseString.prefix(200))")
                } else {
                    print("🏥 LaptopHealthChecker: No response body or unable to decode")
                }
                
                // Check HTTP status code
                if httpResponse.statusCode == 200 {
                    // Success - laptop is connected and responding
                    // Parse response to verify connection status
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("🏥 LaptopHealthChecker: Parsed JSON: \(json)")
                        if let connected = json["connected"] as? Bool {
                            if connected {
                                let oldState = self.connectionState
                                self.connectionState = .connected
                                self.lastError = nil
                                if oldState != .connected {
                                    print("✅ LaptopHealthChecker: State changed to CONNECTED (was: \(oldState))")
                                } else {
                                    print("✅ LaptopHealthChecker: Laptop is connected and responding (state unchanged)")
                                }
                            } else {
                                // Laptop responded but reports not connected
                                let oldState = self.connectionState
                                self.connectionState = .disconnected
                                self.lastError = json["reason"] as? String ?? "Not connected"
                                print("⚠️ LaptopHealthChecker: Laptop reports not connected - \(self.lastError ?? "Unknown") (state: \(oldState) -> disconnected)")
                            }
                        } else {
                            print("⚠️ LaptopHealthChecker: Response missing 'connected' field, assuming connected")
                            // Response format unexpected, but got 200, assume connected
                            let oldState = self.connectionState
                            self.connectionState = .connected
                            self.lastError = nil
                            if oldState != .connected {
                                print("✅ LaptopHealthChecker: State changed to CONNECTED (was: \(oldState))")
                            }
                        }
                    } else {
                        print("⚠️ LaptopHealthChecker: Failed to parse JSON, but got 200, assuming connected")
                        // Response format unexpected, but got 200, assume connected
                        let oldState = self.connectionState
                        self.connectionState = .connected
                        self.lastError = nil
                        if oldState != .connected {
                            print("✅ LaptopHealthChecker: State changed to CONNECTED (was: \(oldState))")
                        }
                    }
                } else if httpResponse.statusCode == 401 {
                    // Unauthorized - auth key invalid
                    let oldState = self.connectionState
                    self.connectionState = .disconnected
                    self.lastError = "Authentication failed"
                    print("⚠️ LaptopHealthChecker: Authentication failed (401) (state: \(oldState) -> disconnected)")
                } else if httpResponse.statusCode == 404 {
                    // Endpoint not found or tunnel not found
                    let oldState = self.connectionState
                    self.connectionState = .disconnected
                    self.lastError = "Not found"
                    print("❌ LaptopHealthChecker: Not found (404) - laptop may not be connected (state: \(oldState) -> disconnected)")
                } else if httpResponse.statusCode == 503 {
                    // Service unavailable
                    let oldState = self.connectionState
                    self.connectionState = .disconnected
                    self.lastError = "Service unavailable"
                    print("⚠️ LaptopHealthChecker: Service unavailable (503) (state: \(oldState) -> disconnected)")
                } else {
                    // Other HTTP errors
                    let oldState = self.connectionState
                    self.connectionState = .disconnected
                    self.lastError = "HTTP \(httpResponse.statusCode)"
                    print("❌ LaptopHealthChecker: HTTP error \(httpResponse.statusCode) (state: \(oldState) -> disconnected)")
                }
                
                print("🏥 LaptopHealthChecker: Final state: \(self.connectionState), error: \(self.lastError ?? "none")")
            }
        }
        
        task.resume()
    }
    
    deinit {
        stop()
    }
}

