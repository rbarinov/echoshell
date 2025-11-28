# Headless Terminal Refactoring: Implementation Plan

## Document Info
- **Created**: 2025-01-27
- **Status**: Planning → Ready for Implementation
- **Based on**: `HEADLESS_TERMINAL_REFACTORING.md`
- **Version**: 1.0

---

## Executive Summary

This plan outlines the step-by-step implementation of refactoring headless terminals from PTY-based execution to direct subprocess execution, with an IDE-style chat interface replacing the terminal view.

### Key Changes
1. **Backend**: Replace PTY with direct subprocess for headless terminals (`cursor`, `claude`)
2. **Data Model**: Add structured chat history with message types (user, assistant, tool, system, error)
3. **WebSocket**: Update message format from raw `output` to structured `chat_message` events
4. **iOS**: Replace terminal view with chat interface for headless terminals
5. **View Modes**: Implement Agent Mode (current execution) and History Mode (full conversation)

### Estimated Timeline
- **Phase 1 (Backend)**: 2-3 days
- **Phase 2 (iOS)**: 3-4 days
- **Phase 3 (Testing)**: 2-3 days
- **Total**: 7-10 days

**Note**: WatchOS implementation is deferred to a separate effort. The Watch app codebase is significantly behind the iOS app and will be updated separately to match the new architecture.

---

## Phase 1: Backend Refactoring (Laptop App)

### 1.1 Create Data Models

**Task**: Define TypeScript interfaces for chat messages and history

**Files to create/modify**:
- `laptop-app/src/terminal/types.ts` (new file or extend existing)

**Implementation**:
```typescript
export interface ChatMessage {
  id: string; // UUID
  timestamp: number;
  type: 'user' | 'assistant' | 'tool' | 'system' | 'error';
  content: string;
  metadata?: {
    toolName?: string;
    toolInput?: string;
    toolOutput?: string;
    thinking?: string;
    errorCode?: string;
    stackTrace?: string;
  };
}

export interface ChatHistory {
  sessionId: string;
  messages: ChatMessage[];
  createdAt: number;
  updatedAt: number;
}
```

**Dependencies**: None
**Estimated Time**: 30 minutes

---

### 1.2 Create HeadlessExecutor Class

**Task**: Implement subprocess management for headless terminals

**Files to create**:
- `laptop-app/src/terminal/HeadlessExecutor.ts` (new file)

**Key Responsibilities**:
- Spawn subprocess with proper args (`cursor-agent` or `claude`)
- Capture stdout/stderr streams
- Handle process lifecycle (start, stop, error)
- Extract `session_id` from output
- Build command with `--resume` or `--session-id` flags

**Implementation Outline**:
```typescript
export class HeadlessExecutor {
  private subprocess: ChildProcess | null = null;
  private cliSessionId: string | null = null;
  private workingDir: string;
  private terminalType: 'cursor' | 'claude';
  
  async execute(command: string, prompt: string): Promise<void>;
  kill(): void;
  onStdout(callback: (data: string) => void): void;
  onStderr(callback: (data: string) => void): void;
  onExit(callback: (code: number | null) => void): void;
}
```

**Dependencies**: None
**Estimated Time**: 4-6 hours

**Key Considerations**:
- Handle command building for both `cursor-agent` and `claude`
- Proper working directory via `cwd` option
- Environment variable setup
- Error handling for spawn failures

---

### 1.3 Create JSON Stream Parser

**Task**: Parse JSON stream output and convert to ChatMessage objects

**Files to create**:
- `laptop-app/src/output/AgentOutputParser.ts` (new file)

**Key Responsibilities**:
- Parse JSON lines from stdout
- Extract `session_id` from any message
- Map JSON types to ChatMessage types:
  - `user` → `ChatMessage` with type `'user'`
  - `assistant` → `ChatMessage` with type `'assistant'`
  - `tool` → `ChatMessage` with type `'tool'` with metadata
  - `system/*` → `ChatMessage` with type `'system'`
  - `result` → Completion indicator (not a message)
- Handle malformed JSON gracefully

**Implementation Outline**:
```typescript
export class AgentOutputParser {
  parseLine(jsonLine: string): {
    message: ChatMessage | null;
    sessionId: string | null;
    isComplete: boolean; // true if result message
  };
  
  private mapToChatMessage(payload: any): ChatMessage | null;
  private extractSessionId(payload: any): string | null;
}
```

**Dependencies**: 1.1 (ChatMessage interface)
**Estimated Time**: 3-4 hours

**Test Cases**:
- Valid JSON with all message types
- Malformed JSON (should skip gracefully)
- Missing fields (should handle gracefully)
- Both cursor-agent and claude formats

---

### 1.4 Refactor TerminalManager

**Task**: Update TerminalManager to use HeadlessExecutor for headless terminals

**Files to modify**:
- `laptop-app/src/terminal/TerminalManager.ts`

**Key Changes**:
1. **Remove PTY creation for headless terminals**:
   - Keep `createPTY()` only for `regular` terminals
   - Remove headless-specific PTY logic

2. **Update TerminalSession interface**:
   ```typescript
   interface TerminalSession {
     // ... existing fields ...
     
     // For regular terminals
     pty?: IPty;
     outputBuffer?: string[];
     
     // For headless terminals (NEW)
     executor?: HeadlessExecutor;
     chatHistory?: ChatHistory;
     currentExecution?: {
       isRunning: boolean;
       cliSessionId?: string;
       startedAt: number;
       currentMessages: ChatMessage[];
     };
   }
   ```

3. **Update `createSession()` method**:
   - For `regular`: Create PTY (existing logic)
   - For `cursor`/`claude`: Create HeadlessExecutor, initialize chatHistory

4. **Update `executeCommand()` method**:
   - For `regular`: Write to PTY (existing logic)
   - For `cursor`/`claude`: Use HeadlessExecutor.execute()

5. **Update output handling**:
   - For `regular`: Keep existing PTY output handling
   - For `cursor`/`claude`: Parse JSON → ChatMessage → update chatHistory

**Dependencies**: 1.2 (HeadlessExecutor), 1.3 (AgentOutputParser)
**Estimated Time**: 6-8 hours

**Breaking Changes**:
- Remove `headless` object structure (replaced with `currentExecution`)
- Remove PTY-based headless execution

---

### 1.5 Update OutputRouter for Chat Messages

**Task**: Modify OutputRouter to handle chat messages for headless terminals

**Files to modify**:
- `laptop-app/src/output/OutputRouter.ts`

**Key Changes**:
1. Add method to send chat messages:
   ```typescript
   sendChatMessage(sessionId: string, message: ChatMessage): void;
   ```

2. Keep existing `sendOutput()` for regular terminals

3. Update routing logic:
   - Regular terminals → `sendOutput()` (raw text)
   - Headless terminals → `sendChatMessage()` (structured)

**Dependencies**: 1.1 (ChatMessage interface)
**Estimated Time**: 2-3 hours

---

### 1.6 Update WebSocket Server

**Task**: Update WebSocket message format for headless terminals

**Files to modify**:
- `laptop-app/src/websocket/terminalWebSocket.ts`

**Key Changes**:
1. Update message format:
   ```typescript
   // Old format (for regular terminals)
   {
     type: 'output',
     session_id: string,
     data: string,
     timestamp: number
   }
   
   // New format (for headless terminals)
   {
     type: 'chat_message',
     session_id: string,
     message: ChatMessage,
     timestamp: number
   }
   ```

2. Detect terminal type and send appropriate format:
   - Regular → `output` format
   - Headless → `chat_message` format

**Dependencies**: 1.1 (ChatMessage interface), 1.5 (OutputRouter)
**Estimated Time**: 2-3 hours

---

### 1.7 Update RecordingStreamManager

**Task**: Accumulate assistant messages and send on completion

**Files to modify**:
- `laptop-app/src/output/RecordingStreamManager.ts`

**Key Changes**:
1. **For headless terminals**:
   - Accumulate all `assistant` type messages during execution
   - Extract text-only content (no code blocks, no tool outputs)
   - Send single `tts_ready` event when execution completes

2. **Message format**:
   ```typescript
   {
     type: 'tts_ready',
     session_id: string,
     text: string, // Combined assistant response text
     timestamp: number
   }
   ```

3. **Trigger on completion**:
   - Listen for `result` message from AgentOutputParser
   - Or timeout (60 seconds)

**Dependencies**: 1.3 (AgentOutputParser), 1.4 (TerminalManager)
**Estimated Time**: 3-4 hours

**Key Considerations**:
- Only accumulate `assistant` messages (skip `tool`, `system`, `user`)
- Extract plain text (remove markdown code blocks, formatting)
- Handle empty responses gracefully

---

### 1.8 Update API Endpoints

**Task**: Ensure API endpoints work with new subprocess approach

**Files to modify**:
- `laptop-app/src/handlers/terminalHandler.ts`
- `laptop-app/src/routes/terminal.ts`

**Key Changes**:
1. **POST /terminal/create**:
   - No changes needed (already supports terminal types)

2. **POST /terminal/{id}/execute**:
   - No changes needed (uses TerminalManager.executeCommand())

3. **GET /terminal/list**:
   - Optionally include chat history metadata (message count, last message time)

**Dependencies**: 1.4 (TerminalManager)
**Estimated Time**: 1-2 hours

---

### Phase 1 Summary

**Total Estimated Time**: 2-3 days

**Deliverables**:
- ✅ ChatMessage and ChatHistory data models
- ✅ HeadlessExecutor class for subprocess management
- ✅ AgentOutputParser for JSON stream parsing
- ✅ Refactored TerminalManager (no PTY for headless)
- ✅ Updated WebSocket message format
- ✅ RecordingStreamManager with accumulation logic

**Testing Checklist**:
- [ ] HeadlessExecutor spawns subprocess correctly
- [ ] JSON parsing handles all message types
- [ ] Session ID extraction and reuse works
- [ ] Chat history accumulates correctly
- [ ] WebSocket sends chat_message format for headless
- [ ] Recording stream sends tts_ready on completion
- [ ] Regular terminals still work (PTY unchanged)

---

## Phase 2: iOS Chat Interface

### 2.1 Create ChatMessage Model

**Task**: Create Swift model matching TypeScript interface

**Files to create**:
- `EchoShell/EchoShell/Models/ChatMessage.swift`

**Implementation**:
```swift
struct ChatMessage: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: Int64
    let type: MessageType
    let content: String
    let metadata: Metadata?
    
    enum MessageType: String, Codable {
        case user
        case assistant
        case tool
        case system
        case error
    }
    
    struct Metadata: Codable, Equatable {
        let toolName: String?
        let toolInput: String?
        let toolOutput: String?
        let thinking: String?
        let errorCode: String?
        let stackTrace: String?
    }
}
```

**Dependencies**: None
**Estimated Time**: 30 minutes

---

### 2.2 Create ChatHistoryView Component

**Task**: Build IDE-style chat interface component

**Files to create**:
- `EchoShell/EchoShell/Views/ChatHistoryView.swift`

**Key Features**:
- Chat bubble layout (user left, assistant right)
- Tool messages with expandable details
- System/error messages with distinct styling
- Auto-scroll to bottom on new messages
- Timestamp display
- Monospace font for tool outputs

**Implementation Outline**:
```swift
struct ChatHistoryView: View {
    let messages: [ChatMessage]
    let isAgentMode: Bool // true = current execution, false = full history
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubbleView(message: message)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                // Auto-scroll to bottom
            }
        }
    }
}
```

**Dependencies**: 2.1 (ChatMessage model)
**Estimated Time**: 4-6 hours

**UI Components Needed**:
- `ChatBubbleView`: Individual message bubble
- `ToolMessageView`: Expandable tool output
- `TimestampView`: Formatted timestamp

---

### 2.3 Update TerminalViewModel

**Task**: Add chat history state management

**Files to modify**:
- `EchoShell/EchoShell/ViewModels/TerminalViewModel.swift`

**Key Changes**:
1. Add chat history state:
   ```swift
   @Published var chatHistory: [ChatMessage] = []
   @Published var currentExecutionMessages: [ChatMessage] = []
   ```

2. Add view mode state:
   ```swift
   @Published var viewMode: ChatViewMode = .agent // .agent or .history
   ```

3. Update WebSocket message handling:
   - Handle `chat_message` events
   - Update `currentExecutionMessages` in real-time
   - Append to `chatHistory` on completion

4. Handle `tts_ready` event:
   - Trigger TTS synthesis
   - Only in Agent Mode

**Dependencies**: 2.1 (ChatMessage model), 2.2 (ChatHistoryView)
**Estimated Time**: 3-4 hours

---

### 2.4 Update WebSocketClient

**Task**: Handle new chat_message WebSocket events

**Files to modify**:
- `EchoShell/EchoShell/Services/WebSocketClient.swift`

**Key Changes**:
1. Add message type handling:
   ```swift
   enum WebSocketMessageType: String, Codable {
       case output // For regular terminals
       case chat_message // For headless terminals
   }
   ```

2. Parse `chat_message` events:
   ```swift
   struct ChatMessageEvent: Codable {
       let type: String
       let session_id: String
       let message: ChatMessage
       let timestamp: Int64
   }
   ```

3. Notify ViewModel on chat_message events

**Dependencies**: 2.1 (ChatMessage model)
**Estimated Time**: 2-3 hours

---

### 2.5 Update RecordingStreamClient

**Task**: Handle tts_ready event for accumulated TTS

**Files to modify**:
- `EchoShell/EchoShell/Services/RecordingStreamClient.swift`

**Key Changes**:
1. Add `tts_ready` event handling:
   ```swift
   struct TTSReadyEvent: Codable {
       let type: String
       let session_id: String
       let text: String
       let timestamp: Int64
   }
   ```

2. Trigger TTS synthesis on `tts_ready`:
   - Only in Agent Mode
   - Use TTSService for synthesis
   - Play audio via AudioPlayer

3. Remove incremental TTS updates (old behavior)

**Dependencies**: 2.3 (TerminalViewModel)
**Estimated Time**: 2-3 hours

---

### 2.6 Update TerminalDetailView

**Task**: Add view mode toggle and integrate chat interface

**Files to modify**:
- `EchoShell/EchoShell/Views/TerminalDetailView.swift`

**Key Changes**:
1. **Add view mode toggle**:
   - Button at top (below header)
   - Toggle between "Agent" and "History"
   - Update SessionStateManager

2. **Conditional rendering**:
   ```swift
   if session.terminalType == .regular {
       // Show PTY terminal view (unchanged)
   } else {
       // Show chat interface
       if viewMode == .agent {
           ChatHistoryView(messages: currentExecutionMessages, isAgentMode: true)
       } else {
           ChatHistoryView(messages: chatHistory, isAgentMode: false)
       }
   }
   ```

3. **Remove terminal view for headless**:
   - Hide SwiftTermTerminalView for `cursor`/`claude` types
   - Show ChatHistoryView instead

**Dependencies**: 2.2 (ChatHistoryView), 2.3 (TerminalViewModel)
**Estimated Time**: 4-5 hours

---

### Phase 2 Summary

**Total Estimated Time**: 3-4 days

**Deliverables**:
- ✅ ChatMessage Swift model
- ✅ ChatHistoryView component
- ✅ Updated TerminalViewModel with chat state
- ✅ WebSocketClient handles chat_message events
- ✅ RecordingStreamClient handles tts_ready
- ✅ TerminalDetailView with mode toggle

**Testing Checklist**:
- [ ] Chat messages display correctly in Agent Mode
- [ ] Chat history displays correctly in History Mode
- [ ] View mode toggle works smoothly
- [ ] TTS triggers on tts_ready event (Agent Mode only)
- [ ] Regular terminals still show terminal view
- [ ] Auto-scroll works in chat interface
- [ ] Tool messages expand/collapse correctly

---

## Phase 3: Testing & Validation

### 3.1 Unit Tests

**Task**: Write unit tests for new components

**Files to create**:
- `laptop-app/src/terminal/__tests__/HeadlessExecutor.test.ts`
- `laptop-app/src/output/__tests__/AgentOutputParser.test.ts`
- `EchoShell/EchoShellTests/ChatMessageTests.swift`
- `EchoShell/EchoShellTests/ChatHistoryViewTests.swift`

**Test Coverage**:
- HeadlessExecutor: subprocess spawning, command building, lifecycle
- AgentOutputParser: JSON parsing, message mapping, error handling
- ChatMessage: Codable conformance, equality
- ChatHistoryView: message rendering, scrolling

**Estimated Time**: 1-2 days

---

### 3.2 Integration Tests

**Task**: End-to-end testing of full flow

**Test Scenarios**:
1. **Voice command → agent response → TTS**:
   - Record voice → transcribe → send to laptop
   - Laptop executes via subprocess
   - Chat messages stream to iOS
   - TTS plays on completion

2. **View mode switching**:
   - Switch between Agent and History modes
   - Verify state preservation
   - Verify TTS only in Agent Mode

3. **Session context preservation**:
   - Execute multiple commands
   - Verify session_id reuse
   - Verify context continuity

4. **Error handling**:
   - Failed commands
   - Timeout scenarios
   - Malformed JSON

**Estimated Time**: 1 day

---

### 3.3 Manual Testing

**Task**: Manual testing on physical devices

**Test Checklist**:
- [ ] iPhone: Voice command execution
- [ ] iPhone: Chat interface display
- [ ] iPhone: View mode toggle
- [ ] iPhone: TTS playback
- [ ] Laptop: Multiple concurrent sessions
- [ ] Laptop: Regular terminals still work
- [ ] Error scenarios (network issues, timeouts)

**Estimated Time**: 1 day

---

### Phase 3 Summary

**Total Estimated Time**: 2-3 days

**Deliverables**:
- ✅ Unit tests for all new components
- ✅ Integration tests for full flow
- ✅ Manual testing on devices
- ✅ Bug fixes and refinements

---

## Risk Assessment & Mitigation

### High Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Subprocess management complexity** | High | Use battle-tested Node.js `child_process` API, comprehensive error handling |
| **Breaking existing functionality** | High | Keep regular terminals unchanged, thorough testing before merge |
| **JSON parsing errors** | Medium | Robust error handling, fallback to system messages, skip malformed lines |

### Medium Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Memory leaks (unbounded history)** | Medium | Monitor memory usage, add LRU eviction if needed (future enhancement) |
| **iOS UI performance (long histories)** | Low | Use SwiftUI List with lazy loading, pagination if needed |
| **TTS timing issues** | Medium | Clear completion detection, timeout fallback |

### Low Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Loss of debugging capability** | Low | Add verbose logging for development mode |

---

## Dependencies & Prerequisites

### Backend Dependencies
- Node.js 20+ (already required)
- `child_process` module (built-in)
- Existing WebSocket infrastructure
- Existing OutputRouter system

### iOS Dependencies
- iOS 17+ (already required)
- SwiftUI (already used)
- Existing WebSocketClient
- Existing TTSService

### Testing Dependencies
- Jest (already configured)
- XCTest (already configured)
- Physical devices for manual testing

---

## Migration Strategy

### Backward Compatibility
- **None required**: Full migration approach
- Existing PTY-based headless terminals will be replaced
- No migration path for old sessions (history not preserved)

### Rollout Plan
1. **Development branch**: Implement all changes
2. **Local testing**: Test on MacBook + iPhone
3. **Feature flag** (optional): Add `USE_SUBPROCESS_HEADLESS` env var for gradual rollout
4. **Merge to main**: Deploy when stable

**Note**: WatchOS app will be updated separately in a future effort to align with the new architecture.

### Rollback Plan
- Keep old code in git history
- Can revert to PTY-based approach if needed
- No database migration needed (in-memory only)

---

## Success Criteria

### Functional
- ✅ Voice command executes via subprocess (no PTY)
- ✅ Chat history displays in IDE-style interface
- ✅ Agent/History mode toggle works seamlessly
- ✅ TTS plays accumulated assistant responses after execution
- ✅ Session context preserved across commands (session_id reuse)
- ✅ Regular terminals still work with PTY (unchanged)

### Performance
- ✅ Command execution starts within 1 second
- ✅ Chat messages update in real-time (< 500ms latency)
- ✅ View mode switching is instant (< 100ms)
- ✅ TTS generation starts within 2 seconds of completion

### UX
- ✅ Chat interface is intuitive and readable
- ✅ Tool outputs are clearly distinguished from text responses
- ✅ Error messages are user-friendly
- ✅ No visual glitches during streaming updates

---

## Open Questions

### Resolved
- ✅ Display mode: Full execution log (user, assistant, tool, system)
- ✅ View switching: Toggle button (Agent/History)
- ✅ Debug mode: Remove raw JSON (simplify UI)
- ✅ Persistence: In-memory only (acceptable for MVP)
- ✅ Migration: Full migration (no backward compatibility needed)
- ✅ iOS UI: IDE chat style (developer-focused)
- ✅ TTS: Accumulate and play on completion

### To Be Decided
- [ ] Should we add pagination for very long chat histories (e.g., 1000+ messages)?
- [ ] Should we allow clearing chat history manually (button to reset)?
- [ ] Should we add search/filter in History Mode?
- [ ] Should we support exporting chat history (e.g., to markdown file)?

---

## Next Steps

1. **Review this plan** with team/stakeholders
2. **Start Phase 1**: Backend refactoring
3. **Daily standups**: Track progress, identify blockers
4. **Incremental testing**: Test each phase before moving to next
5. **Documentation**: Update API docs, user guides as needed

## WatchOS Note

**WatchOS implementation is deferred**: The Watch app codebase is significantly behind the iOS app after recent iOS updates. WatchOS support for the new chat interface will be implemented in a separate effort to:
- Align Watch app architecture with iOS app
- Update Watch app to match current iOS patterns
- Implement chat interface for WatchOS
- Sync chat messages via WatchConnectivity

This refactoring focuses on **Backend (laptop-app)** and **iOS app** only.

---

**END OF IMPLEMENTATION PLAN**
