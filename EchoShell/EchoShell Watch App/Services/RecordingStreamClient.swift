//
//  RecordingStreamClient.swift
//  EchoShell Watch App
//

import Foundation

struct RecordingStreamMessage: Codable {
    let type: String
    let session_id: String
    let text: String
    let delta: String?
    let raw: String?
    let timestamp: TimeInterval?
}

class RecordingStreamClient: NSObject, ObservableObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    @Published var isConnected = false
    @Published var connectionError: String?
    @Published var connectionState: ConnectionState = .disconnected
    
    private var urlSession: URLSession?
    private var dataTask: URLSessionDataTask?
    private var buffer = Data()
    private var onMessageCallback: ((RecordingStreamMessage) -> Void)?
    private let delimiter = "\n\n".data(using: .utf8)!
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    
    // Connection health monitoring (SSE doesn't support ping/pong, so we monitor data reception)
    private let dataTimeout: TimeInterval = 60.0 // 60 seconds without data = dead
    private var lastDataReceived: Date = Date()
    private var healthCheckTimer: Timer?
    private var config: TunnelConfig?
    private var sessionId: String?
    
    func connect(config: TunnelConfig, sessionId: String, onMessage: @escaping (RecordingStreamMessage) -> Void) {
        disconnect()
        
        self.onMessageCallback = onMessage
        self.config = config
        self.sessionId = sessionId
        
        let sseUrlString = "\(config.apiBaseUrl)/recording/\(sessionId)/events"
        guard let url = URL(string: sseUrlString) else {
            Task { @MainActor in
                self.connectionError = "Invalid recording stream URL"
                self.connectionState = .disconnected
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(config.authKey, forHTTPHeaderField: "X-Laptop-Auth-Key")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.urlSession = session
        self.dataTask = session.dataTask(with: request)
        self.dataTask?.resume()
        
        reconnectAttempts = 0
        lastDataReceived = Date()
        
        Task { @MainActor in
            self.isConnected = true
            self.connectionState = .connecting
        }
        
        setupHealthCheck()
    }
    
    func disconnect() {
        cleanupHealthCheck()
        dataTask?.cancel()
        urlSession?.invalidateAndCancel()
        dataTask = nil
        urlSession = nil
        buffer.removeAll()
        Task { @MainActor in
            self.isConnected = false
            self.connectionState = .disconnected
        }
    }
    
    // MARK: - URLSessionDataDelegate
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Update last data received timestamp (indicates connection is alive)
        lastDataReceived = Date()
        if connectionState == .dead {
            Task { @MainActor in
                connectionState = .connected
            }
        }
        
        buffer.append(data)
        processBuffer()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        cleanupHealthCheck()
        
        if let error = error {
            print("❌ Recording stream SSE error: \(error.localizedDescription)")
            Task { @MainActor in
                self.connectionError = error.localizedDescription
                self.isConnected = false
                self.connectionState = .disconnected
            }
            attemptReconnect()
        } else {
            Task { @MainActor in
                self.isConnected = false
                self.connectionState = .disconnected
            }
            // SSE connection closed normally, attempt reconnect
            attemptReconnect()
        }
    }
    
    // MARK: - SSE parsing
    private func processBuffer() {
        while let range = buffer.range(of: delimiter) {
            let chunk = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            handleEventChunk(chunk)
        }
    }
    
    private func handleEventChunk(_ chunk: Data) {
        guard let text = String(data: chunk, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n")
        var dataPayload = ""
        
        for line in lines {
            if line.hasPrefix("data:") {
                let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                dataPayload.append(value)
            }
        }
        
        guard !dataPayload.isEmpty,
              let jsonData = dataPayload.data(using: .utf8),
              let message = try? JSONDecoder().decode(RecordingStreamMessage.self, from: jsonData) else {
            return
        }
        
        DispatchQueue.main.async {
            self.onMessageCallback?(message)
        }
    }
    
    // MARK: - Connection Health Monitoring
    private func setupHealthCheck() {
        cleanupHealthCheck()
        
        // Check for dead connections (no data received within timeout)
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: dataTimeout, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let timeSinceLastData = Date().timeIntervalSince(self.lastDataReceived)
            if timeSinceLastData > self.dataTimeout {
                print("⚠️ Recording stream SSE appears dead (no data for \(timeSinceLastData)s)")
                Task { @MainActor in
                    self.connectionState = .dead
                    self.isConnected = false
                }
                self.cleanupHealthCheck()
                self.dataTask?.cancel()
                self.attemptReconnect()
            }
        }
    }
    
    private func cleanupHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }
    
    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("❌ Max reconnect attempts reached for recording stream SSE")
            Task { @MainActor in
                self.connectionState = .disconnected
            }
            return
        }
        
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Exponential backoff, max 30s
        
        print("🔄 Attempting recording stream SSE reconnect #\(reconnectAttempts) in \(delay)s...")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.connectionState = .reconnecting
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let config = self.config,
                  let sessionId = self.sessionId,
                  let callback = self.onMessageCallback else {
                return
            }
            
            self.connect(config: config, sessionId: sessionId, onMessage: callback)
        }
    }
}

