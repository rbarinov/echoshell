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
    
    var apiClient: APIClient?
    
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
    
    func createNewSession(
        config: TunnelConfig,
        terminalType: TerminalType = .regular,
        workingDir: String? = nil,
        name: String? = nil
    ) async {
        isLoading = true
        defer { isLoading = false }
        
        if apiClient == nil {
            apiClient = APIClient(config: config)
        }
        
        do {
            let newSession = try await apiClient!.createSession(
                terminalType: terminalType,
                workingDir: workingDir,
                name: name
            )
            sessions.append(newSession)
            print("✅ Created new session: \(newSession.id) (type: \(terminalType.rawValue))")
        } catch {
            self.error = error.localizedDescription
            print("❌ Error creating session: \(error)")
        }
    }
    
    func renameSession(_ session: TerminalSession, name: String, config: TunnelConfig) async {
        if apiClient == nil {
            apiClient = APIClient(config: config)
        }
        
        do {
            try await apiClient!.renameSession(sessionId: session.id, name: name)
            // Note: TerminalSession has immutable properties, so we need to refresh the list
            await refreshSessions(config: config)
            print("✅ Renamed session: \(session.id) to \(name)")
        } catch {
            self.error = error.localizedDescription
            print("❌ Error renaming session: \(error)")
        }
    }
    
    func deleteSession(_ session: TerminalSession, config: TunnelConfig) async {
        if apiClient == nil {
            apiClient = APIClient(config: config)
        }
        
        do {
            try await apiClient!.deleteSession(sessionId: session.id)
            // Remove from local list
            sessions.removeAll { $0.id == session.id }
            print("✅ Deleted session: \(session.id)")
        } catch {
            self.error = error.localizedDescription
            print("❌ Error deleting session: \(error)")
        }
    }
}
