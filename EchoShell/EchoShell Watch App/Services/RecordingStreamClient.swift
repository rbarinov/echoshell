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
    
    private var urlSession: URLSession?
    private var dataTask: URLSessionDataTask?
    private var buffer = Data()
    private var onMessageCallback: ((RecordingStreamMessage) -> Void)?
    private let delimiter = "\n\n".data(using: .utf8)!
    
    func connect(config: TunnelConfig, sessionId: String, onMessage: @escaping (RecordingStreamMessage) -> Void) {
        disconnect()
        
        self.onMessageCallback = onMessage
        
        let sseUrlString = "\(config.apiBaseUrl)/recording/\(sessionId)/events"
        guard let url = URL(string: sseUrlString) else {
            Task { @MainActor in
                self.connectionError = "Invalid recording stream URL"
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
        
        Task { @MainActor in
            self.isConnected = true
        }
    }
    
    func disconnect() {
        dataTask?.cancel()
        urlSession?.invalidateAndCancel()
        dataTask = nil
        urlSession = nil
        buffer.removeAll()
        Task { @MainActor in
            self.isConnected = false
        }
    }
    
    // MARK: - URLSessionDataDelegate
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        processBuffer()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("❌ Recording stream SSE error: \(error.localizedDescription)")
            Task { @MainActor in
                self.connectionError = error.localizedDescription
                self.isConnected = false
            }
        } else {
            Task { @MainActor in
                self.isConnected = false
            }
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
}

