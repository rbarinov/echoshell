# Headless Terminal Refactoring: Agent Chat Interface

## Document Info
- **Created**: 2025-11-28
- **Status**: ✅ COMPLETED (2025-01-27)
- **Author**: System Architect
- **Version**: 2.0

---

## 1. Overview

### 1.1 Current State
- Headless terminals (`cursor`, `claude`) use PTY (pseudo-terminal) emulation
- Shell is visible in terminal view (shows raw command execution)
- JSON output is parsed and filtered for recording stream (TTS)
- Terminal displays raw shell output (duplicated information)
- History is only available through terminal scrollback

### 1.2 Proposed State
- Headless terminals use direct subprocess execution (no PTY/shell emulation)
- Agent output is parsed and stored as structured chat history
- Two view modes: **Agent Mode** (current execution) and **History Mode** (past conversations)
- IDE-style chat interface replaces terminal view for headless terminals
- Regular terminals remain unchanged (still use PTY)

### 1.3 Goals
- **Eliminate redundancy**: No need to show shell when we only care about agent conversation
- **Better UX**: Chat-like interface is more intuitive for AI agent interaction
- **Cleaner output**: Structured messages instead of raw JSON/shell output
- **Simplified architecture**: Direct subprocess management instead of PTY wrapper

---

## 2. Architecture Changes

### 2.1 Terminal Types

#### 2.1.1 Regular Terminal (Unchanged)
- **Type**: `regular`
- **Execution**: PTY with interactive shell
- **Display**: Traditional terminal view with scrollback
- **Use Case**: Manual shell commands, debugging, system administration

#### 2.1.2 Headless Agent Terminal (Refactored)
- **Type**: `cursor` | `claude` (possibly more in future)
- **Execution**: Direct subprocess (no PTY, no shell emulation)
- **Display**: IDE-style chat interface
- **View Modes**:
  - **Agent Mode**: Current execution (real-time updates)
  - **History Mode**: Full conversation history
- **Use Case**: Voice-controlled AI agent commands

### 2.2 Subprocess Management

#### 2.2.1 Command Execution Flow
```typescript
// Old (PTY-based)
pty = spawn(shell, [], { cwd, env });
pty.write(`cursor-agent --output-format stream-json "prompt"\n`);
pty.onData(data => parseJsonStream(data));

// New (Direct subprocess)
subprocess = spawn('cursor-agent', [
  '--output-format', 'stream-json',
  '--print',
  '--resume', sessionId,
  'prompt'
], { cwd, env });

subprocess.stdout.on('data', data => parseJsonStream(data));
subprocess.stderr.on('data', data => handleError(data));
subprocess.on('exit', (code) => handleCompletion(code));
```

#### 2.2.2 Working Directory Management
- Each headless terminal has its own `workingDir` property
- Commands are executed in that directory via `cwd` option
- No need to `cd` in shell - subprocess handles it directly

#### 2.2.3 Session Context Preservation
- Extract `session_id` from agent output (JSON stream)
- Store `session_id` in terminal session state
- Pass `--resume <session_id>` (cursor) or `--session-id <session_id>` (claude) for subsequent commands
- **In-memory only**: Session context cleared on laptop app restart

### 2.3 Data Model Changes

#### 2.3.1 Chat Message Structure
```typescript
interface ChatMessage {
  id: string; // UUID for message
  timestamp: number; // Unix timestamp
  type: 'user' | 'assistant' | 'tool' | 'system' | 'error';
  content: string; // Main message text
  metadata?: {
    // For 'tool' type messages
    toolName?: string;
    toolInput?: string;
    toolOutput?: string;

    // For 'assistant' type messages
    thinking?: string; // Internal reasoning (if available)

    // For 'error' type messages
    errorCode?: string;
    stackTrace?: string;
  };
}

interface ChatHistory {
  sessionId: string;
  messages: ChatMessage[];
  createdAt: number;
  updatedAt: number;
}
```

#### 2.3.2 Terminal Session Model (Updated)
```typescript
interface TerminalSession {
  sessionId: string;
  terminalType: 'regular' | 'cursor' | 'claude';
  workingDir: string;
  createdAt: number;

  // For regular terminals
  pty?: IPty;
  outputBuffer?: string[];

  // For headless terminals
  subprocess?: ChildProcess;
  chatHistory?: ChatHistory;
  currentExecution?: {
    isRunning: boolean;
    cliSessionId?: string; // Session ID from CLI
    startedAt: number;
    currentMessages: ChatMessage[]; // Messages from current execution
  };
}
```

### 2.4 Output Processing

#### 2.4.1 JSON Stream Parsing
```typescript
// Parse stream-json output from cursor-agent / claude
function parseAgentOutput(jsonLine: string): ChatMessage | null {
  const parsed = JSON.parse(jsonLine);

  // Extract session_id for context preservation
  if (parsed.session_id) {
    session.currentExecution.cliSessionId = parsed.session_id;
  }

  // Map to ChatMessage type
  switch (parsed.type) {
    case 'user':
      return { type: 'user', content: parsed.content, ... };

    case 'assistant':
      return { type: 'assistant', content: parsed.content, ... };

    case 'tool':
      return {
        type: 'tool',
        content: `Tool: ${parsed.tool_name}`,
        metadata: {
          toolName: parsed.tool_name,
          toolInput: parsed.input,
          toolOutput: parsed.output
        },
        ...
      };

    case 'system/init':
    case 'system/...':
      // Optionally include system messages
      return { type: 'system', content: parsed.message, ... };

    default:
      return null;
  }
}
```

#### 2.4.2 History Storage
- **In-memory storage**: `chatHistory` stored in `TerminalSession` object
- **No persistence**: History cleared when laptop app restarts
- **Capacity**: Unlimited (until restart) - can add LRU eviction later if needed

### 2.5 WebSocket Streams

#### 2.5.1 Terminal Stream (Updated)
```typescript
// WebSocket: /terminal/{session_id}/stream

// Old format (raw PTY output)
{
  type: 'output',
  session_id: 'dev-session',
  data: '\x1b[32mSome text\x1b[0m',
  timestamp: 1234567890
}

// New format (chat messages for headless terminals)
{
  type: 'chat_message',
  session_id: 'dev-session',
  message: {
    id: 'msg-uuid',
    type: 'assistant',
    content: 'Here is the result...',
    timestamp: 1234567890
  }
}

// Regular terminals still use old format
```

#### 2.5.2 Recording Stream (Simplified)
```typescript
// WebSocket: /recording/{session_id}/stream

// Purpose: TTS generation for Agent Mode
// Behavior: Accumulate all assistant messages during current execution
// Output: Send accumulated text when execution completes

{
  type: 'tts_ready',
  session_id: 'dev-session',
  text: 'Combined assistant response text for TTS',
  timestamp: 1234567890
}
```

**Key Changes**:
- Recording stream only fires when command execution completes
- Accumulates all `assistant` type messages from current execution
- Extracts text-only content (no code blocks, no tool outputs)
- iOS app receives single TTS payload instead of incremental updates

---

## 3. UI/UX Changes

### 3.1 iOS/WatchOS Terminal View

#### 3.1.1 View Mode Toggle
- **Location**: Top of terminal detail view (below header)
- **States**:
  - **Agent Mode** (default): Shows current execution
  - **History Mode**: Shows full chat history
- **Visual**: Button with icons (e.g., "Current" ⚡ / "History" 📜)

#### 3.1.2 Agent Mode (Current Execution)
**Layout** (IDE chat style):
```
┌─────────────────────────────────────┐
│ Terminal: dev-session      [History]│ ← Toggle button
├─────────────────────────────────────┤
│                                     │
│ 👤 User                             │
│ List files in current directory     │
│                                     │
│ 🤖 Assistant                        │
│ I'll list the files for you.        │
│                                     │
│ 🔧 Tool: bash                       │
│ $ ls -la                            │
│ Output: file1.txt, file2.py...      │
│                                     │
│ 🤖 Assistant                        │
│ Here are the files in the directory.│
│ [Currently typing...]               │ ← Real-time update
│                                     │
└─────────────────────────────────────┘
```

**Features**:
- Displays only messages from **current execution**
- Real-time updates as agent responds
- Monospace font for tool outputs
- Expandable/collapsible tool details
- Auto-scroll to bottom as new messages arrive
- TTS triggered **after execution completes**

#### 3.1.3 History Mode (Full Conversation)
**Layout**:
```
┌─────────────────────────────────────┐
│ Terminal: dev-session      [Current]│ ← Toggle button
├─────────────────────────────────────┤
│ Conversation History                │
│                                     │
│ 👤 10:23 AM                         │
│ Show git status                     │
│                                     │
│ 🤖 10:23 AM                         │
│ On branch main. Nothing to commit.  │
│                                     │
│ ─────────────────────────────       │ ← Separator
│                                     │
│ 👤 10:25 AM                         │
│ List files in current directory     │
│                                     │
│ 🤖 10:25 AM                         │
│ Here are the files...               │
│                                     │
│ [Scroll to see more]                │
└─────────────────────────────────────┘
```

**Features**:
- Displays **all messages** from session start (until restart)
- Grouped by execution (separated by lines)
- Timestamps for each message
- Scrollable view (oldest at top)
- Read-only (no interaction)
- **No TTS playback** in this mode

### 3.2 Laptop Web Interface (Optional)
- Same view modes: Agent / History
- IDE-style chat layout (similar to iOS)
- Syntax highlighting for code blocks
- Copy button for tool outputs

---

## 4. Implementation Plan

### 4.1 Phase 1: Backend Refactoring (Laptop App)
**Estimated effort**: 2-3 days

#### Tasks:
1. **Remove PTY logic for headless terminals**
   - Delete PTY spawn code for `cursor`/`claude` types
   - Keep PTY only for `regular` terminals

2. **Implement subprocess management**
   - Create `HeadlessExecutor` class
   - Spawn subprocess with proper args and working directory
   - Capture stdout/stderr streams
   - Handle process lifecycle (start, stop, error)

3. **Update JSON parser**
   - Extract `session_id` and store in session state
   - Map JSON output to `ChatMessage` objects
   - Build `chatHistory` array in memory

4. **Refactor WebSocket streams**
   - Send `chat_message` events instead of raw `output`
   - Update recording stream to accumulate and send on completion

5. **Update API endpoints**
   - `/terminal/create`: Support headless without PTY
   - `/terminal/{id}/execute`: Use subprocess instead of PTY write

#### Files to modify:
- `laptop-app/src/services/terminal-manager.ts` (major refactoring)
- `laptop-app/src/services/stream-manager.ts` (recording stream logic)
- `laptop-app/src/services/websocket-server.ts` (message format)

### 4.2 Phase 2: iOS Chat Interface (Mobile App)
**Estimated effort**: 3-4 days

#### Tasks:
1. **Create ChatMessage model**
   - Swift struct matching TypeScript interface
   - Codable for WebSocket serialization

2. **Build chat history view**
   - SwiftUI chat bubble component
   - Message grouping and timestamps
   - Tool output expansion
   - Scrollable container

3. **Implement view mode toggle**
   - State management for Agent/History modes
   - Smooth transition between views

4. **Update WebSocket client**
   - Handle `chat_message` events
   - Update `chatHistory` array in ViewModel
   - Trigger TTS on `tts_ready` event (Agent Mode only)

5. **Remove terminal output view for headless**
   - Keep terminal view only for `regular` type
   - Show chat interface for `cursor`/`claude` types

#### Files to modify:
- `ios-app/Sources/Models/ChatMessage.swift` (new file)
- `ios-app/Sources/Views/TerminalDetailView.swift` (add mode toggle)
- `ios-app/Sources/Views/ChatHistoryView.swift` (new file)
- `ios-app/Sources/ViewModels/TerminalViewModel.swift` (chat state)
- `ios-app/Sources/Services/WebSocketClient.swift` (message handling)

### 4.3 Phase 3: WatchOS Simplification
**Estimated effort**: 1-2 days

#### Tasks:
1. **Update Watch UI**
   - Replace terminal output with chat bubbles (compact)
   - Agent/History toggle (simplified for small screen)

2. **Sync with iPhone**
   - Receive chat messages via WatchConnectivity
   - Display in compact chat format

#### Files to modify:
- `watchos-app/Sources/Views/ContentView.swift`
- `watchos-app/Sources/Services/WatchConnectivityManager.swift`

### 4.4 Phase 4: Testing & Validation
**Estimated effort**: 2-3 days

#### Tasks:
1. **Unit tests**
   - HeadlessExecutor subprocess management
   - JSON parser message extraction
   - Chat history accumulation

2. **Integration tests**
   - End-to-end command execution
   - WebSocket message flow
   - TTS triggering on completion

3. **Manual testing**
   - Voice command → agent response → TTS playback
   - View mode switching
   - Session context preservation
   - Error handling (failed commands, timeouts)

---

## 5. Edge Cases & Error Handling

### 5.1 Subprocess Failures
- **Scenario**: Agent CLI crashes or exits with error
- **Handling**:
  - Capture stderr output
  - Add error message to chat history
  - Display in chat as red error message
  - Set `currentExecution.isRunning = false`

### 5.2 JSON Parse Errors
- **Scenario**: Malformed JSON from CLI tool
- **Handling**:
  - Log error to console
  - Add system message to chat: "Failed to parse agent output"
  - Continue processing next lines

### 5.3 Session ID Not Found
- **Scenario**: CLI doesn't return `session_id` in output
- **Handling**:
  - Use previous `session_id` if available
  - If no previous ID, start fresh session (no resume flag)
  - Log warning

### 5.4 Execution Timeout
- **Scenario**: Command runs for > 60 seconds
- **Handling**:
  - Kill subprocess
  - Add timeout message to chat history
  - Allow user to retry

### 5.5 TTS Failures
- **Scenario**: Recording stream doesn't receive assistant messages
- **Handling**:
  - Check if execution completed successfully
  - If no assistant messages, don't trigger TTS
  - Log warning for debugging

---

## 6. Migration Strategy

### 6.1 Backward Compatibility
- **None required**: Full migration approach
- Existing PTY-based headless terminals will be replaced
- No migration path for old sessions (history not preserved)

### 6.2 Rollout Plan
1. **Development branch**: Implement all changes
2. **Local testing**: Test on MacBook + iPhone/Watch
3. **Feature flag** (optional): Add `USE_SUBPROCESS_HEADLESS` env var for gradual rollout
4. **Merge to main**: Deploy when stable

---

## 7. Future Enhancements

### 7.1 Persistent History
- Store chat history in SQLite or JSON files
- Load on laptop app restart
- Export conversation history

### 7.2 Multi-Agent Support
- Add more agent types (Gemini, custom agents)
- Unified chat interface for all agents
- Agent switching within session

### 7.3 Chat Interactions
- Retry failed commands
- Edit previous prompts
- Branch conversations (fork from history point)

### 7.4 Rich Media
- Display images from agent (if supported)
- Render markdown/code blocks with syntax highlighting
- Interactive code execution buttons

---

## 8. Technical Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Subprocess vs PTY** | Direct subprocess | No need for shell emulation, cleaner output |
| **Display mode** | Full execution log | User wants to see thinking + tool calls |
| **View switching** | Toggle button | Simple on/off for Agent/History modes |
| **Raw JSON debug** | Remove completely | Simplifies UI, reduces clutter |
| **History persistence** | In-memory only | Simpler implementation, acceptable for MVP |
| **iOS UI style** | IDE chat style | Developer-focused, familiar from Cursor/VSCode |
| **TTS source** | Accumulate on completion | Cleaner UX, single playback per command |
| **Migration** | Full migration | No need to support old PTY approach |

---

## 9. Open Questions

### 9.1 Resolved
- ✅ Display mode: Full execution log
- ✅ View switching: Toggle button
- ✅ Debug mode: Remove raw JSON
- ✅ Persistence: In-memory only
- ✅ Migration: Full migration
- ✅ iOS UI: IDE chat style
- ✅ TTS: Accumulate and play on completion

### 9.2 To Be Decided
- [ ] Should we add pagination for very long chat histories (e.g., 1000+ messages)?
- [ ] Should we allow clearing chat history manually (button to reset)?
- [ ] Should we add search/filter in History Mode?
- [ ] Should we support exporting chat history (e.g., to markdown file)?

---

## 10. Success Criteria

### 10.1 Functional
- ✅ Voice command executes via subprocess (no PTY)
- ✅ Chat history displays in IDE-style interface
- ✅ Agent/History mode toggle works seamlessly
- ✅ TTS plays accumulated assistant responses after execution
- ✅ Session context preserved across commands (session_id reuse)
- ✅ Regular terminals still work with PTY (unchanged)

### 10.2 Performance
- ✅ Command execution starts within 1 second
- ✅ Chat messages update in real-time (< 500ms latency)
- ✅ View mode switching is instant (< 100ms)
- ✅ TTS generation starts within 2 seconds of completion

### 10.3 UX
- ✅ Chat interface is intuitive and readable
- ✅ Tool outputs are clearly distinguished from text responses
- ✅ Error messages are user-friendly
- ✅ No visual glitches during streaming updates

---

## 11. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Subprocess management complexity | High | Use battle-tested Node.js `child_process` API |
| JSON parsing errors | Medium | Robust error handling, fallback to system messages |
| Memory leaks (unbounded history) | Medium | Monitor memory usage, add LRU eviction if needed |
| iOS UI performance (long histories) | Low | Use SwiftUI List with lazy loading |
| Loss of debugging capability | Low | Add verbose logging for development mode |

---

## 12. Appendices

### Appendix A: Example JSON Stream

**Cursor Agent Output** (`--output-format stream-json --print`):
```json
{"type":"system/init","session_id":"abc123","timestamp":1234567890}
{"type":"user","content":"List files","timestamp":1234567891}
{"type":"assistant","content":"I'll list the files for you.","timestamp":1234567892}
{"type":"tool","tool_name":"bash","input":"ls -la","output":"file1.txt\nfile2.py","timestamp":1234567893}
{"type":"assistant","content":"Here are the files in the directory.","timestamp":1234567894}
{"type":"result","success":true,"timestamp":1234567895}
```

**Claude CLI Output** (`--output-format json-stream`):
```json
{"type":"session_start","session_id":"xyz789"}
{"type":"message","role":"user","content":"List files"}
{"type":"message","role":"assistant","content":"I'll help you list files."}
{"type":"tool_use","name":"bash","input":"ls -la"}
{"type":"tool_result","output":"file1.txt\nfile2.py"}
{"type":"message","role":"assistant","content":"Files listed above."}
{"type":"session_end"}
```

### Appendix B: Chat Message Examples

**User Message**:
```json
{
  "id": "msg-001",
  "timestamp": 1701234567890,
  "type": "user",
  "content": "List files in current directory"
}
```

**Assistant Message**:
```json
{
  "id": "msg-002",
  "timestamp": 1701234567892,
  "type": "assistant",
  "content": "I'll list the files for you using the ls command.",
  "metadata": {
    "thinking": "User wants directory listing. I'll use ls -la for detailed output."
  }
}
```

**Tool Message**:
```json
{
  "id": "msg-003",
  "timestamp": 1701234567893,
  "type": "tool",
  "content": "bash: ls -la",
  "metadata": {
    "toolName": "bash",
    "toolInput": "ls -la",
    "toolOutput": "total 24\ndrwxr-xr-x  5 user staff  160 Nov 28 10:00 .\ndrwxr-xr-x 10 user staff  320 Nov 27 15:30 ..\n-rw-r--r--  1 user staff 1234 Nov 28 09:45 file1.txt\n-rw-r--r--  1 user staff 5678 Nov 28 09:50 file2.py"
  }
}
```

**Error Message**:
```json
{
  "id": "msg-004",
  "timestamp": 1701234567895,
  "type": "error",
  "content": "Command execution failed: Permission denied",
  "metadata": {
    "errorCode": "EACCES",
    "stackTrace": "Error: spawn EACCES\n    at ..."
  }
}
```

---

---

## Implementation Status

### ✅ COMPLETED (2025-01-27)

All phases have been successfully implemented:

- ✅ **Phase 1**: Backend refactoring (HeadlessExecutor, AgentOutputParser, TerminalManager)
- ✅ **Phase 2**: iOS chat interface (ChatHistoryView, ChatTerminalView, ChatViewModel)
- ✅ **Phase 3**: Testing infrastructure (unit tests, integration tests, manual checklist)

### Key Changes Implemented

1. **Backend**: Headless terminals now use direct subprocess instead of PTY
2. **Data Model**: Structured ChatMessage objects replace raw output
3. **WebSocket**: chat_message format for headless terminals
4. **iOS**: IDE-style chat interface with Agent/History mode toggle
5. **TTS**: Accumulated assistant messages sent as single tts_ready event

### Files Created/Modified

See `REFACTORING_COMPLETE_SUMMARY.md` for complete list of changes.

---

**END OF SPECIFICATION**
