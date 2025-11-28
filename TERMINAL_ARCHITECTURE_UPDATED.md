# Terminal Architecture: Updated Documentation

## Overview

This document describes the **updated terminal architecture** after the headless terminal refactoring (2025-01-27).

---

## Terminal Types

### 1. Regular Terminals

**Type**: `regular`

**Execution**:
- Uses PTY (pseudo-terminal) with interactive shell
- Direct shell access (bash/zsh)
- Full terminal emulation

**Display**:
- Traditional terminal view with scrollback
- ANSI color support
- Real-time output streaming

**Use Case**:
- Manual shell commands
- Interactive programs (vim, top, etc.)
- System administration
- Debugging

**Architecture**:
```
User Input → PTY → Shell → Command → Output → PTY → WebSocket → iOS Terminal View
```

---

### 2. Headless Terminals (Refactored)

**Types**: `cursor`, `claude`

**Execution**:
- Uses direct subprocess execution (no PTY, no shell)
- HeadlessExecutor spawns CLI tools directly
- No shell emulation overhead

**Display**:
- IDE-style chat interface (ChatHistoryView)
- Structured ChatMessage objects
- Two view modes: Agent (current) / History (full)

**Use Case**:
- Voice-controlled AI agent commands
- Natural language interaction
- Code generation and execution

**Architecture**:
```
User Voice → Transcription → Command → HeadlessExecutor → Subprocess (cursor-agent/claude)
                                                                  ↓
                                                          JSON Output Stream
                                                                  ↓
                                                          AgentOutputParser
                                                                  ↓
                                                          ChatMessage Objects
                                                                  ↓
                                                          ChatHistoryView (iOS)
```

---

## Data Flow Comparison

### Regular Terminal Flow

```
iPhone → WebSocket → Tunnel → Laptop
                              ↓
                         TerminalManager
                              ↓
                         PTY (bash/zsh)
                              ↓
                         Command Execution
                              ↓
                         PTY Output
                              ↓
                         WebSocket → Tunnel → iPhone
                              ↓
                         Terminal View (SwiftTerm)
```

### Headless Terminal Flow (New)

```
iPhone → Voice → Transcription → Command → API
                                          ↓
                                    TerminalManager
                                          ↓
                                    HeadlessExecutor
                                          ↓
                                    Subprocess (cursor-agent/claude)
                                          ↓
                                    JSON Output Stream
                                          ↓
                                    AgentOutputParser
                                          ↓
                                    ChatMessage Objects
                                          ↓
                                    OutputRouter.sendChatMessage()
                                          ↓
                                    WebSocket (chat_message format)
                                          ↓
                                    Tunnel Server (recognizes format)
                                          ↓
                                    iPhone WebSocketClient
                                          ↓
                                    ChatViewModel.addMessage()
                                          ↓
                                    ChatHistoryView (display)
```

---

## Key Components

### Backend (Laptop App)

1. **HeadlessExecutor** (`laptop-app/src/terminal/HeadlessExecutor.ts`)
   - Manages subprocess lifecycle
   - Handles command building with proper flags
   - Manages session_id for context preservation

2. **AgentOutputParser** (`laptop-app/src/output/AgentOutputParser.ts`)
   - Parses JSON stream from CLI tools
   - Converts to ChatMessage objects
   - Extracts session_id and detects completion

3. **TerminalManager** (`laptop-app/src/terminal/TerminalManager.ts`)
   - Creates HeadlessExecutor for headless terminals
   - Creates PTY for regular terminals
   - Manages chat history and current execution state

4. **OutputRouter** (`laptop-app/src/output/OutputRouter.ts`)
   - Routes output based on terminal type
   - Sends chat_message format for headless
   - Sends output format for regular

5. **RecordingStreamManager** (`laptop-app/src/output/RecordingStreamManager.ts`)
   - Accumulates assistant messages
   - Sends tts_ready event on completion
   - Cleans text (removes markdown, code blocks)

### iOS App

1. **ChatMessage** (`EchoShell/EchoShell/Models/ChatMessage.swift`)
   - Structured message model
   - Supports all message types (user, assistant, tool, system, error)
   - Metadata for tool messages

2. **ChatHistoryView** (`EchoShell/EchoShell/Views/ChatHistoryView.swift`)
   - IDE-style chat interface
   - Message grouping by conversation turns
   - Timestamps, copy buttons, code blocks
   - Auto-scroll, expandable tool messages

3. **ChatTerminalView** (`EchoShell/EchoShell/Views/ChatTerminalView.swift`)
   - Wrapper for headless terminal chat interface
   - View mode toggle (Agent/History)
   - Voice recording integration
   - WebSocket and recording stream setup

4. **ChatViewModel** (`EchoShell/EchoShell/ViewModels/ChatViewModel.swift`)
   - Manages chat history state
   - Current execution messages
   - View mode management

5. **WebSocketClient** (`EchoShell/EchoShell/Services/WebSocketClient.swift`)
   - Handles chat_message events
   - Parses ChatMessage objects
   - Backward compatible with output format

6. **RecordingStreamClient** (`EchoShell/EchoShell/Services/RecordingStreamClient.swift`)
   - Handles tts_ready events
   - Triggers TTS synthesis
   - Backward compatible with legacy format

### Tunnel Server

**Updated**: `tunnel-server/src/websocket/handlers/tunnelHandler.ts`

- Recognizes when `data` contains JSON with `chat_message` type
- Forwards chat_message directly without wrapping
- Maintains backward compatibility for regular terminal output

---

## Message Formats

### Regular Terminal Output

```json
{
  "type": "output",
  "session_id": "session-123",
  "data": "terminal output text",
  "timestamp": 1234567890
}
```

### Headless Terminal Chat Message

```json
{
  "type": "chat_message",
  "session_id": "session-123",
  "message": {
    "id": "msg-uuid",
    "timestamp": 1234567890,
    "type": "assistant",
    "content": "Here is the result...",
    "metadata": {
      "toolName": "bash",
      "toolInput": "ls -la",
      "toolOutput": "file1.txt\nfile2.py"
    }
  },
  "timestamp": 1234567890
}
```

### TTS Ready Event

```json
{
  "type": "tts_ready",
  "session_id": "session-123",
  "text": "Combined assistant response text for TTS",
  "timestamp": 1234567890
}
```

---

## Session State

### Regular Terminal Session

```typescript
{
  sessionId: "session-123",
  terminalType: "regular",
  pty: IPty, // Active PTY instance
  pid: 12345,
  processGroupId: 12345,
  outputBuffer: ["output line 1", "output line 2"],
  inputBuffer: ["command1", "command2"],
  workingDir: "/Users/user/projects",
  createdAt: 1234567890
}
```

### Headless Terminal Session

```typescript
{
  sessionId: "session-123",
  terminalType: "cursor", // or "claude"
  executor: HeadlessExecutor, // Subprocess manager
  chatHistory: {
    sessionId: "session-123",
    messages: [ChatMessage, ...],
    createdAt: 1234567890,
    updatedAt: 1234567891
  },
  currentExecution: {
    isRunning: false,
    cliSessionId: "cli-session-abc",
    startedAt: 1234567890,
    currentMessages: [ChatMessage, ...]
  },
  inputBuffer: ["command1", "command2"],
  workingDir: "/Users/user/projects",
  createdAt: 1234567890
}
```

---

## Migration Notes

### Breaking Changes

1. **TerminalSession Interface**: Removed `headless` object, added `executor`, `chatHistory`, `currentExecution`
2. **Headless Execution**: No longer uses PTY, uses direct subprocess
3. **WebSocket Format**: Headless terminals send `chat_message` instead of `output`
4. **iOS Display**: Headless terminals show chat interface instead of terminal view

### Backward Compatibility

- **Regular terminals**: Fully backward compatible (unchanged)
- **Tunnel server**: Backward compatible (recognizes both formats)
- **iOS app**: Handles both `output` and `chat_message` formats

---

## Testing

### Unit Tests

- ✅ HeadlessExecutor tests
- ✅ AgentOutputParser tests
- ✅ ChatMessage tests (Swift)
- ✅ ChatViewModel tests (Swift)

### Integration Tests

- ✅ Chat interface message accumulation
- ✅ View mode toggle
- ✅ Tool message metadata

### Manual Testing

See `MANUAL_TESTING_CHECKLIST.md` for comprehensive testing scenarios.

---

## Related Documentation

- `HEADLESS_TERMINAL_REFACTORING.md` - Original specification
- `HEADLESS_TERMINAL_REFACTORING_PLAN.md` - Implementation plan
- `REFACTORING_COMPLETE_SUMMARY.md` - Completion summary
- `CLAUDE.md` - Main technical specification (updated)
- `TERMINAL_SESSION_ARCHITECTURE.md` - Terminal architecture (this file)

---

**Last Updated**: 2025-01-27
**Status**: ✅ Implementation Complete
