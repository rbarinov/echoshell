# Unified WebSocket Protocol Specification

## Version: 2.0
## Status: Draft
## Date: 2024-11-28

---

## 1. Overview

This document specifies the unified WebSocket-based communication protocol for:
- **Agent Mode** (main screen) - Global AI agent for terminal management
- **Headless Terminals** (cursor/claude) - AI-powered terminal sessions
- **Regular Terminals** - Traditional PTY-based terminal access (unchanged)

### 1.1 Goals

1. **Unified Protocol**: Same WebSocket message format for Agent Mode and Headless Terminals
2. **Server-Side Processing**: STT transcription and TTS synthesis happen on laptop-app
3. **Streaming Responses**: Real-time chat message streaming during command execution
4. **Context Preservation**: Agent maintains conversation context across multiple commands
5. **Clean Architecture**: Remove all legacy HTTP proxy code

### 1.2 Out of Scope

- Regular Terminals: Keep existing PTY-based functionality unchanged
- Watch App: Will be updated in a separate iteration

---

## 2. Architecture

### 2.1 High-Level Flow

```
┌─────────────────┐                    ┌─────────────────┐
│   iOS App       │                    │   Laptop App    │
│                 │                    │                 │
│  ┌───────────┐  │   WebSocket        │  ┌───────────┐  │
│  │ Agent UI  │──┼────────────────────┼─→│ AIAgent   │  │
│  └───────────┘  │   execute_audio    │  │ (context) │  │
│                 │   or execute       │  └───────────┘  │
│  ┌───────────┐  │                    │                 │
│  │ Headless  │──┼────────────────────┼─→│ Cursor/   │  │
│  │ Terminal  │  │                    │  │ Claude CLI│  │
│  └───────────┘  │                    │  └───────────┘  │
│                 │                    │                 │
│  ┌───────────┐  │   ← chat_message   │                 │
│  │ Chat View │←─┼────────────────────┼── Streaming     │
│  └───────────┘  │   ← tts_audio      │    Response     │
│                 │                    │                 │
└─────────────────┘                    └─────────────────┘
```

### 2.2 Session Types

| Type | Session ID Format | Backend | Context |
|------|------------------|---------|---------|
| Agent | `agent-{timestamp}` | AIAgent (LangChain) | Preserved until reset |
| Cursor | `session-{timestamp}` | cursor-agent CLI | CLI session_id |
| Claude | `session-{timestamp}` | claude CLI | CLI session_id |
| Regular | `session-{timestamp}` | PTY shell | Shell environment |

---

## 3. WebSocket Protocol

### 3.1 Connection

**Endpoint**: `wss://{tunnel_url}/api/{tunnel_id}/terminal/{session_id}/stream`

**Headers**:
```
X-Device-ID: {device_uuid}
```

### 3.2 Client → Server Messages

#### 3.2.1 Execute Text Command

```json
{
  "type": "execute",
  "command": "Create a new terminal in workspace my-project",
  "tts_enabled": true,
  "tts_speed": 1.0,
  "language": "en"
}
```

#### 3.2.2 Execute Audio Command

```json
{
  "type": "execute_audio",
  "audio": "{base64_encoded_audio}",
  "audio_format": "audio/m4a",
  "tts_enabled": true,
  "tts_speed": 1.0,
  "language": "ru"
}
```

#### 3.2.3 Terminal Input (Regular terminals only)

```json
{
  "type": "input",
  "data": "ls -la\r"
}
```

#### 3.2.4 Reset Context (Agent mode only)

```json
{
  "type": "reset_context"
}
```

### 3.3 Server → Client Messages

#### 3.3.1 Transcription Result

```json
{
  "type": "transcription",
  "session_id": "agent-123456",
  "text": "Create a new terminal",
  "timestamp": 1732816800000
}
```

#### 3.3.2 Chat Message (Streaming)

```json
{
  "type": "chat_message",
  "session_id": "agent-123456",
  "message": {
    "id": "msg-uuid-123",
    "timestamp": 1732816800000,
    "type": "assistant",
    "content": "I'll create a new terminal for you...",
    "metadata": {
      "toolName": "createTerminal",
      "toolInput": "{...}",
      "completion": false
    }
  }
}
```

**Message Types**:
- `user` - User's command (from transcription or text input)
- `assistant` - Agent/CLI response
- `tool` - Tool execution details
- `system` - System messages (completion, errors)
- `error` - Error messages

#### 3.3.3 TTS Audio

```json
{
  "type": "tts_audio",
  "session_id": "agent-123456",
  "audio": "{base64_encoded_mp3}",
  "format": "audio/mpeg",
  "text": "Terminal created successfully",
  "timestamp": 1732816800000
}
```

#### 3.3.4 Completion Signal

```json
{
  "type": "chat_message",
  "session_id": "agent-123456",
  "message": {
    "id": "msg-uuid-completion",
    "timestamp": 1732816800000,
    "type": "system",
    "content": "Command completed",
    "metadata": {
      "completion": true
    }
  }
}
```

#### 3.3.5 Context Reset Confirmation (Agent only)

```json
{
  "type": "context_reset",
  "session_id": "agent-123456",
  "timestamp": 1732816800000
}
```

### 3.4 Terminal Output (Regular terminals only)

```json
{
  "type": "output",
  "session_id": "session-123456",
  "data": "total 48\ndrwxr-xr-x  12 user  staff   384 Nov 28 12:00 .",
  "timestamp": 1732816800000
}
```

---

## 4. iOS App Requirements

### 4.1 Main Screen (Agent Mode)

#### 4.1.1 UI Components

1. **Chat View** (same as Headless Terminal)
   - Scrollable chat history
   - Message bubbles (user, assistant, system, error)
   - Voice message bubbles (tts_audio)
   - Auto-scroll to bottom on new messages

2. **Recording Button**
   - Mic icon when idle
   - Stop icon when recording
   - Hourglass when processing
   - Waveform when playing TTS

3. **Context Reset Button** (NEW)
   - Small button in header/toolbar
   - Shows confirmation dialog before reset
   - Clears chat history and resets agent context

4. **Connection Status**
   - Shows WebSocket connection state
   - Reconnects automatically on disconnect

#### 4.1.2 State Management

```swift
class AgentChatViewModel: ObservableObject {
    @Published var chatHistory: [ChatMessage] = []
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var isPlaying: Bool = false
    @Published var isConnected: Bool = false
    
    private var agentSessionId: String?
    private let wsClient = WebSocketClient()
    
    func resetContext() async { /* ... */ }
    func startRecording() { /* ... */ }
    func stopRecording() { /* ... */ }
    func sendTextCommand(_ text: String) { /* ... */ }
}
```

### 4.2 Headless Terminal Screen

Same as Agent Mode but:
- Uses terminal session ID instead of agent session
- No "Reset Context" button (context is CLI-managed)
- Shows terminal working directory in header

### 4.3 Regular Terminal Screen

**UNCHANGED** - Keep existing implementation:
- PTY output display
- Keyboard input
- No chat interface
- No TTS

### 4.4 Files to REMOVE (Legacy Code)

```
EchoShell/
├── Services/
│   ├── TranscriptionService.swift      # DELETE - replaced by WebSocket
│   ├── LocalTTSHandler.swift           # DELETE - replaced by WebSocket
│   └── RecordingStreamClient.swift     # DELETE - replaced by WebSocket
├── ViewModels/
│   └── TerminalAgentViewModel.swift    # DELETE - merge into unified ViewModel
└── Views/
    └── TerminalSessionAgentView.swift  # DELETE - replace with ChatTerminalView
```

### 4.5 Files to MODIFY

```
EchoShell/
├── RecordingView.swift                 # Refactor to use ChatView
├── ViewModels/
│   └── AgentViewModel.swift            # Refactor for chat interface
├── Services/
│   ├── WebSocketClient.swift           # Add reset_context support
│   └── TTSService.swift                # Simplify - only playback, no synthesis
└── AudioRecorder.swift                 # Keep WebSocket mode only
```

---

## 5. Laptop App Requirements

### 5.1 Agent Session Management

#### 5.1.1 Context Preservation

```typescript
// AgentExecutor.ts
class AgentExecutor {
  private conversationHistory: ChatMessage[] = [];
  private aiAgent: AIAgent;
  
  async execute(prompt: string): Promise<void> {
    // Add user message to history
    this.conversationHistory.push(userMessage);
    
    // Execute with full context
    const result = await this.aiAgent.executeWithContext(
      prompt,
      this.conversationHistory
    );
    
    // Add assistant response to history
    this.conversationHistory.push(assistantMessage);
  }
  
  resetContext(): void {
    this.conversationHistory = [];
    console.log('Agent context reset');
  }
}
```

#### 5.1.2 AIAgent Context Support

```typescript
// AIAgent.ts
class AIAgent {
  async executeWithContext(
    prompt: string,
    history: ChatMessage[]
  ): Promise<AgentResult> {
    // Build context from history
    const contextPrompt = this.buildContextPrompt(history, prompt);
    
    // Execute with context
    return this.execute(contextPrompt);
  }
  
  private buildContextPrompt(history: ChatMessage[], newPrompt: string): string {
    // Format conversation history for LLM context
    const historyText = history
      .filter(m => m.type === 'user' || m.type === 'assistant')
      .map(m => `${m.type}: ${m.content}`)
      .join('\n');
    
    return `Previous conversation:\n${historyText}\n\nNew request: ${newPrompt}`;
  }
}
```

### 5.2 WebSocket Handler Updates

```typescript
// terminalWebSocket.ts
case 'reset_context':
  await handleResetContext(sessionId, terminalManager, ws);
  break;

async function handleResetContext(
  sessionId: string,
  terminalManager: TerminalManager,
  ws: WebSocket
): Promise<void> {
  const session = terminalManager.getSession(sessionId);
  
  if (session?.agentExecutor) {
    session.agentExecutor.resetContext();
    
    // Clear chat history in database
    terminalManager.clearChatHistory(sessionId);
    
    // Send confirmation
    ws.send(JSON.stringify({
      type: 'context_reset',
      session_id: sessionId,
      timestamp: Date.now()
    }));
  }
}
```

### 5.3 Files to REMOVE (Legacy Code)

```
laptop-app/src/
├── handlers/
│   └── proxyHandler.ts                 # DELETE - STT/TTS proxy no longer needed
├── proxy/
│   ├── STTProxy.ts                     # KEEP - used by WebSocket handler
│   └── TTSProxy.ts                     # KEEP - used by WebSocket handler
├── output/
│   └── RecordingStreamManager.ts       # DELETE - replaced by WebSocket streaming
└── routes/
    └── proxy.ts                        # DELETE - HTTP proxy routes
```

### 5.4 Files to MODIFY

```
laptop-app/src/
├── index.ts                            # Remove proxy routes
├── terminal/
│   ├── TerminalManager.ts              # Add clearChatHistory()
│   └── AgentExecutor.ts                # Add conversation history
├── agent/
│   └── AIAgent.ts                      # Add executeWithContext()
└── websocket/
    └── terminalWebSocket.ts            # Add reset_context handler
```

---

## 6. Tunnel Server Requirements

### 6.1 Proxy Updates

No changes needed - tunnel server just forwards WebSocket messages.

### 6.2 Files to REMOVE (Legacy Code)

```
tunnel-server/src/
├── websocket/handlers/
│   └── streamManager.ts                # Review - may have unused recording stream code
└── routes/
    └── proxy.ts                        # DELETE if exists
```

---

## 7. Testing Requirements

### 7.1 Unit Tests

#### iOS Tests
```swift
// AgentChatViewModelTests.swift
func testSendTextCommand() async { }
func testSendAudioCommand() async { }
func testReceiveTranscription() { }
func testReceiveChatMessage() { }
func testReceiveTTSAudio() { }
func testResetContext() async { }
func testReconnection() async { }
```

#### Laptop App Tests
```typescript
// AgentExecutor.test.ts
describe('AgentExecutor', () => {
  it('should preserve conversation history', async () => });
  it('should reset context on request', () => });
  it('should send chat messages during execution', async () => });
});

// terminalWebSocket.test.ts
describe('WebSocket Handler', () => {
  it('should handle execute message', async () => });
  it('should handle execute_audio message', async () => });
  it('should handle reset_context message', async () => });
  it('should stream chat messages', async () => });
  it('should send tts_audio on completion', async () => });
});
```

### 7.2 Integration Tests

```typescript
// integration/agent-flow.test.ts
describe('Agent Flow', () => {
  it('should complete full voice command cycle', async () => {
    // 1. Send execute_audio
    // 2. Receive transcription
    // 3. Receive streaming chat_messages
    // 4. Receive tts_audio
    // 5. Receive completion
  });
  
  it('should preserve context across commands', async () => {
    // 1. Send first command
    // 2. Wait for completion
    // 3. Send follow-up command referencing first
    // 4. Verify context is used
  });
});
```

### 7.3 Regular Terminal Tests (MUST PASS)

```typescript
// Existing tests must continue to pass
describe('Regular Terminal', () => {
  it('should create PTY session', async () => });
  it('should execute commands', async () => });
  it('should stream output', async () => });
  it('should handle resize', async () => });
});
```

---

## 8. Migration Plan

### Phase 1: Laptop App (Day 1)
1. Update AgentExecutor with conversation history
2. Update AIAgent with executeWithContext
3. Add reset_context WebSocket handler
4. Remove unused proxy handlers
5. Run tests

### Phase 2: iOS App (Day 2)
1. Create unified chat view for Agent mode
2. Add reset context button and functionality
3. Remove legacy TranscriptionService
4. Remove legacy LocalTTSHandler
5. Simplify TTSService (playback only)
6. Run tests

### Phase 3: Cleanup (Day 3)
1. Remove all unused files
2. Update documentation
3. Full integration testing
4. Performance testing

---

## 9. Success Criteria

1. ✅ Agent mode uses chat interface (like Headless terminals)
2. ✅ Agent preserves context across multiple commands
3. ✅ Reset context button works with confirmation
4. ✅ No HTTP proxy calls for STT/TTS
5. ✅ All communication via WebSocket
6. ✅ Streaming responses work correctly
7. ✅ TTS audio plays on command completion
8. ✅ Regular terminals work unchanged
9. ✅ All tests pass
10. ✅ No legacy code remains

---

## 10. Appendix: Message Examples

### A. Full Agent Interaction

```
iOS → Server: execute_audio (voice recording)
Server → iOS: transcription ("Create new terminal")
Server → iOS: chat_message (user: "Create new terminal")
Server → iOS: chat_message (assistant: "Creating terminal...")
Server → iOS: chat_message (tool: createTerminal execution)
Server → iOS: chat_message (assistant: "Terminal created: session-123")
Server → iOS: chat_message (system: completion=true)
Server → iOS: tts_audio (synthesized response)
```

### B. Context Reset

```
iOS → Server: reset_context
Server: Clear conversation history
Server: Clear database chat history
Server → iOS: context_reset confirmation
iOS: Clear chat UI
```

### C. Follow-up Command (with context)

```
// Previous: "Create terminal in workspace my-project"
// Now: "Now run npm install in it"

iOS → Server: execute ("Now run npm install in it")
Server: AIAgent uses context to know which terminal
Server → iOS: chat_message (assistant: "Running npm install in session-123...")
...
```

