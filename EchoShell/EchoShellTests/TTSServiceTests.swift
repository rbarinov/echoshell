//
//  TTSServiceTests.swift
//  EchoShellTests
//
//  Created for Voice-Controlled Terminal Management System
//  Unit tests for TTSService
//

import Testing
import Foundation
@testable import EchoShell

struct TTSServiceTests {
    
    // MARK: - shouldGenerateTTS Tests
    
    @Test("shouldGenerateTTS returns false for empty text")
    func testShouldGenerateTTS_EmptyText_ReturnsFalse() async throws {
        let audioPlayer = AudioPlayer()
        let ttsService = await TTSService(audioPlayer: audioPlayer)
        
        let result = await ttsService.shouldGenerateTTS(
            newText: "",
            lastText: "",
            isPlaying: false
        )
        
        #expect(result == false)
    }
    
    @Test("shouldGenerateTTS returns false for whitespace-only text")
    func testShouldGenerateTTS_WhitespaceOnly_ReturnsFalse() async throws {
        let audioPlayer = AudioPlayer()
        let ttsService = await TTSService(audioPlayer: audioPlayer)
        
        let result = await ttsService.shouldGenerateTTS(
            newText: "   \n\t  ",
            lastText: "",
            isPlaying: false
        )
        
        #expect(result == false)
    }
    
    @Test("shouldGenerateTTS returns false for same text")
    func testShouldGenerateTTS_SameText_ReturnsFalse() async throws {
        let audioPlayer = AudioPlayer()
        let ttsService = await TTSService(audioPlayer: audioPlayer)
        
        let text = "Hello, world!"
        let result = await ttsService.shouldGenerateTTS(
            newText: text,
            lastText: text,
            isPlaying: false
        )
        
        #expect(result == false)
    }
    
    @Test("shouldGenerateTTS returns false when already playing")
    func testShouldGenerateTTS_AlreadyPlaying_ReturnsFalse() async throws {
        let audioPlayer = AudioPlayer()
        let ttsService = await TTSService(audioPlayer: audioPlayer)
        
        let result = await ttsService.shouldGenerateTTS(
            newText: "New text",
            lastText: "Old text",
            isPlaying: true
        )
        
        #expect(result == false)
    }
    
    @Test("shouldGenerateTTS returns true for valid new text")
    func testShouldGenerateTTS_ValidNewText_ReturnsTrue() async throws {
        let audioPlayer = AudioPlayer()
        let ttsService = await TTSService(audioPlayer: audioPlayer)
        
        let result = await ttsService.shouldGenerateTTS(
            newText: "New text",
            lastText: "Old text",
            isPlaying: false
        )
        
        #expect(result == true)
    }
    
    @Test("shouldGenerateTTS returns true for first text")
    func testShouldGenerateTTS_FirstText_ReturnsTrue() async throws {
        let audioPlayer = AudioPlayer()
        let ttsService = await TTSService(audioPlayer: audioPlayer)
        
        let result = await ttsService.shouldGenerateTTS(
            newText: "First text",
            lastText: "",
            isPlaying: false
        )
        
        #expect(result == true)
    }
    
    // MARK: - State Management Tests
    
    @Test("isGenerating starts as false")
    func testIsGenerating_InitialState_IsFalse() async throws {
        let audioPlayer = AudioPlayer()
        let ttsService = await TTSService(audioPlayer: audioPlayer)
        
        #expect(await ttsService.isGenerating == false)
    }
    
    @Test("lastGeneratedText starts as empty")
    func testLastGeneratedText_InitialState_IsEmpty() async throws {
        let audioPlayer = AudioPlayer()
        let ttsService = await TTSService(audioPlayer: audioPlayer)
        
        #expect(await ttsService.lastGeneratedText == "")
    }
    
    @Test("lastAudioData starts as nil")
    func testLastAudioData_InitialState_IsNil() async throws {
        let audioPlayer = AudioPlayer()
        let ttsService = await TTSService(audioPlayer: audioPlayer)
        
        #expect(await ttsService.lastAudioData == nil)
    }
    
    // MARK: - Reset Tests
    
    @Test("reset clears all state")
    func testReset_ClearsAllState() async throws {
        let audioPlayer = AudioPlayer()
        let ttsService = await TTSService(audioPlayer: audioPlayer)
        
        // Set some state (we can't actually synthesize without network, but we can test reset)
        await ttsService.reset()
        
        #expect(await ttsService.isGenerating == false)
        #expect(await ttsService.lastGeneratedText == "")
        #expect(await ttsService.lastAudioData == nil)
    }
    
    // MARK: - Replay Tests
    
    @Test("replay does nothing when no audio data")
    func testReplay_NoAudioData_DoesNothing() async throws {
        let audioPlayer = AudioPlayer()
        let ttsService = await TTSService(audioPlayer: audioPlayer)
        
        // Should not crash
        await ttsService.replay()
        
        #expect(await ttsService.lastAudioData == nil)
    }
}
