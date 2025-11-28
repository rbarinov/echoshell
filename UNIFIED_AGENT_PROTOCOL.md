# Unified AgentEvent Protocol

## Overview

This document describes the unified `AgentEvent` protocol that replaces the fragmented communication channels (terminal/stream, recording/stream, agent_request/agent_response) with a single, consistent WebSocket channel for all agent interactions.

## Architecture

```
┌──────────┐                    ┌────────────────┐                    ┌─────────────┐
│   iOS    │  AgentEvent (WS)   │ Tunnel Server  │  AgentEvent (WS)   │ Laptop App  │
│  Client  │ ──────────────────>│    (Proxy)     │──────────────────> │   (Agent)   │
│          │ <──────────────────│                │<────────────────── │             │
└──────────┘                    └────────────────┘                    └─────────────┘
     │                                                                        │
     │                                                                        │
     └────── Unified /agent/ws WebSocket ──────────────────────────────────┘
```

## Event Types

### Client → Server

1. **command_text**: Text command from user
   - Payload: `{ text: string }`

2. **command_voice**: Voice command (audio data)
   - Payload: `{ audio_base64: string, format: string }`

3. **context_reset**: Reset conversation context
   - Payload: `{}`

### Server → Client

4. **transcription**: Voice command transcription result
   - Payload: `{ text: string, confidence?: number }`

5. **assistant_message**: AI agent response (streaming)
   - Payload: `{ content: string, is_final: boolean, metadata?: object }`

6. **tts_audio**: Synthesized audio response
   - Payload: `{ audio_base64: string, format: string, duration_ms: number, transcript: string }`

7. **completion**: Command execution completed
   - Payload: `{ success: boolean, result?: string, error?: string }`

8. **error**: Error occurred
   - Payload: `{ code: string, message: string, details?: object }`

## Base AgentEvent Structure

```typescript
interface AgentEvent {
  type: AgentEventType;
  session_id: string;
  message_id: string;
  parent_id?: string; // Links messages in conversation chain
  timestamp: number;
  payload: Record<string, unknown>;
}
```

## Implementation Status

### ✅ Completed

1. **laptop-app**
   - ✅ AgentEvent TypeScript types (`src/types/AgentEvent.ts`)
   - ✅ AgentEventHandler with STT/TTS services (`src/agent/AgentEventHandler.ts`)
   - ✅ AgentWebSocketHandler for managing connections (`src/tunnel/AgentWebSocketHandler.ts`)
   - ✅ TunnelClient updated to route `agent_event` messages
   - ✅ Compiles successfully

2. **tunnel-server**
   - ✅ AgentEvent types and Zod schemas (`src/types/index.ts`, `src/schemas/tunnelSchemas.ts`)
   - ✅ TunnelHandler.handleAgentEvent() for routing (`src/websocket/handlers/tunnelHandler.ts`)
   - ✅ Broadcasts to agent streams
   - ✅ Compiles successfully

3. **iOS (EchoShell)**
   - ✅ AgentEvent Swift models (`Models/AgentEvent.swift`)
   - ✅ AgentWebSocketClient for unified communication (`Services/AgentWebSocketClient.swift`)
   - ✅ Event type-safe helpers (CommandTextEvent, AgentTranscriptionEvent, etc.)
   - ✅ AnyCodable for dynamic JSON handling
   - ✅ Compiles successfully

### 🔄 Next Steps (Future Work)

1. **iOS ViewModels Integration**
   - Update `SupervisorViewModel` to use `AgentWebSocketClient`
   - Update `HeadlessAgentChatViewModel` to use `AgentWebSocketClient`
   - Remove legacy WebSocket connections (`WebSocketClient`, `RecordingStreamClient`)

2. **laptop-app AI Integration**
   - Replace placeholder response in `AgentEventHandler.executeAgent()` with actual AIAgent.executeStream()
   - Wire up LLMProvider to AgentEventHandler constructor

3. **Legacy Code Cleanup**
   - Remove deprecated `agent_request`/`agent_response` handlers
   - Remove deprecated `/terminal/{session}/stream` and `/recording/{session}/stream` endpoints
   - Remove unused WebSocket client implementations

4. **Testing & Validation**
   - End-to-end test: iOS voice command → laptop execution → TTS response
   - Test reconnection and error handling
   - Test context preservation across commands

## Benefits

1. **Single WebSocket Channel**: One connection per session instead of multiple parallel streams
2. **Type Safety**: Zod validation on server, Codable on iOS, TypeScript types on laptop
3. **Unified Protocol**: Consistent message format across all components
4. **Parent-Child Linking**: `parent_id` field enables conversation threading
5. **Simplified Debugging**: All events flow through one channel with consistent logging
6. **Better State Synchronization**: No race conditions between multiple WebSocket streams

## Migration Path

The new protocol is implemented alongside the legacy system. To migrate:

1. Update iOS ViewModels to use `AgentWebSocketClient`
2. Test thoroughly
3. Remove legacy code paths
4. Update documentation

## Files Created/Modified

### laptop-app
- `src/types/AgentEvent.ts` (new)
- `src/agent/AgentEventHandler.ts` (new)
- `src/services/STTService.ts` (new)
- `src/services/TTSService.ts` (new)
- `src/tunnel/AgentWebSocketHandler.ts` (new)
- `src/tunnel/TunnelClient.ts` (modified)
- `src/index.ts` (modified)

### tunnel-server
- `src/types/index.ts` (modified)
- `src/schemas/tunnelSchemas.ts` (modified)
- `src/websocket/handlers/tunnelHandler.ts` (modified)

### iOS (EchoShell)
- `Models/AgentEvent.swift` (new)
- `Services/AgentWebSocketClient.swift` (new)

## Example Usage (iOS)

```swift
// Create client for session
let client = AgentWebSocketClient(sessionId: "supervisor", tunnelConfig: config)
client.connect()

// Send text command
client.sendTextCommand("List files in current directory")

// Send voice command
client.sendVoiceCommand(audioData: recordedAudio, format: "m4a")

// Listen for events
client.eventPublisher.sink { event in
    switch event.type {
    case .transcription:
        if let transcription = AgentTranscriptionEvent(from: event) {
            print("Transcribed: \(transcription.text)")
        }
    case .assistantMessage:
        if let message = AgentAssistantMessageEvent(from: event) {
            print("Assistant: \(message.content)")
        }
    case .ttsAudio:
        if let audio = AgentTTSAudioEvent(from: event) {
            playAudio(base64: audio.audioBase64)
        }
    default:
        break
    }
}
```

---

**Status**: ✅ Core infrastructure complete, ready for ViewModel integration
**Last Updated**: 2025-11-28
