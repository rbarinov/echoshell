//
//  TerminalViewModel.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  ViewModel for managing terminal sessions
//

import Foundation

@MainActor
class TerminalViewModel: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private var apiClient: APIClient?
    
    func loadSessions(config: TunnelConfig) async {
        isLoading = true
        defer { isLoading = false }
        
        if apiClient == nil {
            apiClient = APIClient(config: config)
        }
        
        do {
            sessions = try await apiClient!.listSessions()
            print("✅ Loaded \(sessions.count) sessions")
        } catch {
            self.error = error.localizedDescription
            print("❌ Error loading sessions: \(error)")
        }
    }
    
    func refreshSessions(config: TunnelConfig) async {
        await loadSessions(config: config)
    }
    
    func createNewSession(config: TunnelConfig, workingDir: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        
        if apiClient == nil {
            apiClient = APIClient(config: config)
        }
        
        do {
            let newSession = try await apiClient!.createSession(workingDir: workingDir)
            sessions.append(newSession)
            print("✅ Created new session: \(newSession.id)")
        } catch {
            self.error = error.localizedDescription
            print("❌ Error creating session: \(error)")
        }
    }
}
