//
//  SessionStateManagerTests.swift
//  EchoShellTests
//
//  Created for Voice-Controlled Terminal Management System
//  Unit tests for SessionStateManager using Dependency Injection
//

import Testing
import Foundation
@testable import EchoShell

struct SessionStateManagerTests {
    
    // Create isolated test instance (not singleton)
    private func createTestManager(prefix: String = "") async -> SessionStateManager {
        return await SessionStateManager(testPrefix: "test_\(prefix)_")
    }
    
    // MARK: - Initial State Tests
    
    @Test("activeSessionId starts as nil")
    func testActiveSessionId_InitialState_IsNil() async throws {
        let manager = await createTestManager(prefix: "test1")
        #expect(await manager.activeSessionId == nil)
    }
    
    @Test("activeViewMode starts as pty")
    func testActiveViewMode_InitialState_IsPty() async throws {
        let manager = await createTestManager(prefix: "test2")
        let viewMode = await manager.activeViewMode
        #expect(viewMode == .pty)
    }
    
    // MARK: - setActiveSession Tests
    
    @Test("setActiveSession sets activeSessionId")
    func testSetActiveSession_SetsActiveSessionId() async throws {
        let manager = await createTestManager(prefix: "test3")
        await manager.setActiveSession("test-session-1", name: "Test Session", defaultMode: .agent)
        let sessionId = await manager.activeSessionId
        #expect(sessionId == "test-session-1")
    }
    
    @Test("setActiveSession sets activeViewMode to default")
    func testSetActiveSession_SetsActiveViewModeToDefault() async throws {
        let manager = await createTestManager(prefix: "test4")
        await manager.setActiveSession("test-session-2", name: "Test Session", defaultMode: .agent)
        let viewMode = await manager.activeViewMode
        #expect(viewMode == .agent)
    }
    
    @Test("setActiveSession restores saved view mode")
    func testSetActiveSession_RestoresSavedViewMode() async throws {
        let manager = await createTestManager(prefix: "test5")
        let sessionId = "test-session-3"
        
        // Set mode for session (before activating)
        await manager.setViewMode(.agent, for: sessionId)
        
        // Activate session with different default
        await manager.setActiveSession(sessionId, name: "Test", defaultMode: .pty)
        
        // Should restore saved mode (agent), not default (pty)
        let viewMode = await manager.activeViewMode
        #expect(viewMode == .agent)
    }
    
    // MARK: - clearActiveSession Tests
    
    @Test("clearActiveSession clears activeSessionId")
    func testClearActiveSession_ClearsActiveSessionId() async throws {
        let manager = await createTestManager(prefix: "test6")
        await manager.setActiveSession("test-session-4", name: "Test", defaultMode: .pty)
        await manager.clearActiveSession()
        let sessionId = await manager.activeSessionId
        #expect(sessionId == nil)
    }
    
    @Test("clearActiveSession resets activeViewMode to pty")
    func testClearActiveSession_ResetsActiveViewMode() async throws {
        let manager = await createTestManager(prefix: "test7")
        await manager.setActiveSession("test-session-5", name: "Test", defaultMode: .agent)
        await manager.clearActiveSession()
        let viewMode = await manager.activeViewMode
        #expect(viewMode == .pty)
    }
    
    // MARK: - setViewMode Tests
    
    @Test("setViewMode sets mode for session")
    func testSetViewMode_SetsModeForSession() async throws {
        let manager = await createTestManager(prefix: "test8")
        let sessionId = "test-session-6"
        await manager.setViewMode(.agent, for: sessionId)
        let mode = await manager.getViewMode(for: sessionId)
        #expect(mode == .agent)
    }
    
    @Test("setViewMode updates activeViewMode if session is active")
    func testSetViewMode_UpdatesActiveViewModeIfActive() async throws {
        let manager = await createTestManager(prefix: "test9")
        let sessionId = "test-session-7"
        await manager.setActiveSession(sessionId, name: "Test", defaultMode: .pty)
        await manager.setViewMode(.agent, for: sessionId)
        let viewMode = await manager.activeViewMode
        #expect(viewMode == .agent)
    }
    
    @Test("setViewMode does not update activeViewMode if session is not active")
    func testSetViewMode_DoesNotUpdateActiveViewModeIfNotActive() async throws {
        let manager = await createTestManager(prefix: "test10")
        let sessionId1 = "test-session-8"
        let sessionId2 = "test-session-9"
        await manager.setActiveSession(sessionId1, name: "Test 1", defaultMode: .pty)
        await manager.setViewMode(.agent, for: sessionId2)
        
        // Active view mode should still be pty (for sessionId1)
        let activeMode = await manager.activeViewMode
        #expect(activeMode == .pty)
        
        // But sessionId2 should have agent mode
        let mode2 = await manager.getViewMode(for: sessionId2)
        #expect(mode2 == .agent)
    }
    
    // MARK: - getViewMode Tests
    
    @Test("getViewMode returns saved mode")
    func testGetViewMode_ReturnsSavedMode() async throws {
        let manager = await createTestManager(prefix: "test11")
        let sessionId = "test-session-10"
        await manager.setViewMode(.agent, for: sessionId)
        let mode = await manager.getViewMode(for: sessionId)
        #expect(mode == .agent)
    }
    
    @Test("getViewMode returns pty as default")
    func testGetViewMode_ReturnsPtyAsDefault() async throws {
        let manager = await createTestManager(prefix: "test12")
        let sessionId = "test-session-11"
        // Don't set mode, should default to pty
        let mode = await manager.getViewMode(for: sessionId)
        #expect(mode == .pty)
    }
    
    // MARK: - toggleViewMode Tests
    
    @Test("toggleViewMode toggles from pty to agent")
    func testToggleViewMode_TogglesFromPtyToAgent() async throws {
        let manager = await createTestManager(prefix: "test13")
        let sessionId = "test-session-12"
        await manager.setActiveSession(sessionId, name: "Test", defaultMode: .pty)
        await manager.toggleViewMode()
        let viewMode = await manager.activeViewMode
        #expect(viewMode == .agent)
    }
    
    @Test("toggleViewMode toggles from agent to pty")
    func testToggleViewMode_TogglesFromAgentToPty() async throws {
        let manager = await createTestManager(prefix: "test14")
        let sessionId = "test-session-13"
        await manager.setActiveSession(sessionId, name: "Test", defaultMode: .agent)
        await manager.toggleViewMode()
        let viewMode = await manager.activeViewMode
        #expect(viewMode == .pty)
    }
    
    @Test("toggleViewMode does nothing when no active session")
    func testToggleViewMode_NoActiveSession_DoesNothing() async throws {
        let manager = await createTestManager(prefix: "test15")
        let initialMode = await manager.activeViewMode
        await manager.toggleViewMode()
        // Should remain unchanged (pty)
        let finalMode = await manager.activeViewMode
        #expect(finalMode == .pty)
    }
    
    // MARK: - supportsAgentMode Tests
    
    @Test("supportsAgentMode returns true for cursorCLI")
    func testSupportsAgentMode_CursorCLI_ReturnsTrue() async throws {
        let manager = await createTestManager(prefix: "test16")
        let result = await manager.supportsAgentMode(terminalType: .cursorCLI)
        #expect(result == true)
    }
    
    @Test("supportsAgentMode returns true for claudeCLI")
    func testSupportsAgentMode_ClaudeCLI_ReturnsTrue() async throws {
        let manager = await createTestManager(prefix: "test17")
        let result = await manager.supportsAgentMode(terminalType: .claudeCLI)
        #expect(result == true)
    }
    
    @Test("supportsAgentMode returns true for cursorAgent")
    func testSupportsAgentMode_CursorAgent_ReturnsTrue() async throws {
        let manager = await createTestManager(prefix: "test18")
        let result = await manager.supportsAgentMode(terminalType: .cursorAgent)
        #expect(result == true)
    }
    
    @Test("supportsAgentMode returns false for regular")
    func testSupportsAgentMode_Regular_ReturnsFalse() async throws {
        let manager = await createTestManager(prefix: "test19")
        let result = await manager.supportsAgentMode(terminalType: .regular)
        #expect(result == false)
    }
    
    // MARK: - Multiple Sessions Tests
    
    @Test("multiple sessions have isolated view modes")
    func testMultipleSessions_IsolatedViewModes() async throws {
        let manager = await createTestManager(prefix: "test20")
        let sessionId1 = "test-session-14"
        let sessionId2 = "test-session-15"
        await manager.setViewMode(.agent, for: sessionId1)
        await manager.setViewMode(.pty, for: sessionId2)
        let mode1 = await manager.getViewMode(for: sessionId1)
        let mode2 = await manager.getViewMode(for: sessionId2)
        #expect(mode1 == .agent)
        #expect(mode2 == .pty)
    }
}
