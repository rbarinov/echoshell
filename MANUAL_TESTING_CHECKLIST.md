# Manual Testing Checklist

## Phase 1: Backend Testing (Laptop App)

### 1.1 Headless Terminal Creation
- [ ] Create cursor terminal session
- [ ] Create claude terminal session
- [ ] Verify HeadlessExecutor is created (not PTY)
- [ ] Verify chatHistory is initialized
- [ ] Verify currentExecution is initialized

### 1.2 Command Execution
- [ ] Execute command in cursor terminal
- [ ] Execute command in claude terminal
- [ ] Verify subprocess is spawned (not PTY)
- [ ] Verify command is sent with correct flags
- [ ] Verify session_id is extracted and stored
- [ ] Verify subsequent commands use --resume/--session-id

### 1.3 Chat Message Parsing
- [ ] Verify user messages are created and added to history
- [ ] Verify assistant messages are parsed correctly
- [ ] Verify tool messages are parsed with metadata
- [ ] Verify system messages are handled
- [ ] Verify error messages are created on failures
- [ ] Verify completion detection works (result message)

### 1.4 WebSocket Streaming
- [ ] Connect to terminal WebSocket
- [ ] Verify chat_message events are received
- [ ] Verify message format is correct
- [ ] Verify regular terminals still send output format

### 1.5 Recording Stream (TTS)
- [ ] Connect to recording stream
- [ ] Verify assistant messages are accumulated
- [ ] Verify tts_ready event is sent on completion
- [ ] Verify text is cleaned (no code blocks, markdown)

### 1.6 Multiple Sessions
- [ ] Create multiple headless terminals
- [ ] Execute commands in parallel
- [ ] Verify sessions are isolated
- [ ] Verify chat history is per-session

### 1.7 Error Handling
- [ ] Test command timeout (60 seconds)
- [ ] Test subprocess failure
- [ ] Test malformed JSON handling
- [ ] Test network disconnection
- [ ] Verify error messages are added to chat

---

## Phase 2: iOS App Testing

### 2.1 Chat Interface Display
- [ ] Open headless terminal (cursor/claude)
- [ ] Verify ChatHistoryView is shown (not terminal view)
- [ ] Verify chat bubbles display correctly
- [ ] Verify user messages on right, assistant on left
- [ ] Verify tool messages with expandable details
- [ ] Verify system/error messages with distinct styling

### 2.2 View Mode Toggle
- [ ] Toggle between Agent and History modes
- [ ] Verify Agent mode shows current execution only
- [ ] Verify History mode shows full conversation
- [ ] Verify toggle button works smoothly
- [ ] Verify mode persists when switching terminals

### 2.3 Real-time Updates
- [ ] Execute voice command
- [ ] Verify chat messages appear in real-time
- [ ] Verify auto-scroll to bottom works
- [ ] Verify messages update as agent responds
- [ ] Verify tool messages can be expanded/collapsed

### 2.4 Voice Command Flow
- [ ] Record voice command
- [ ] Verify transcription appears
- [ ] Verify command is sent to terminal
- [ ] Verify user message appears in chat
- [ ] Verify assistant messages stream in
- [ ] Verify TTS plays on completion (Agent mode only)

### 2.5 TTS Playback
- [ ] Verify TTS only triggers in Agent mode
- [ ] Verify TTS doesn't trigger in History mode
- [ ] Verify TTS uses accumulated assistant text
- [ ] Verify TTS text is cleaned (no code blocks)
- [ ] Verify TTS plays after execution completes

### 2.6 Regular Terminals
- [ ] Open regular terminal
- [ ] Verify terminal view is shown (not chat)
- [ ] Verify PTY mode works as before
- [ ] Verify no chat interface appears

### 2.7 Session Switching
- [ ] Switch between multiple terminals
- [ ] Verify chat history is preserved per session
- [ ] Verify view mode is preserved per session
- [ ] Verify WebSocket reconnects correctly

### 2.8 Error Scenarios
- [ ] Test network disconnection
- [ ] Test command execution failure
- [ ] Test timeout scenarios
- [ ] Verify error messages appear in chat
- [ ] Verify app doesn't crash

---

## Phase 3: Integration Testing

### 3.1 End-to-End Flow
- [ ] Voice command → transcription → execution → chat messages → TTS
- [ ] Verify complete flow works without errors
- [ ] Verify timing is acceptable (< 2s for TTS)
- [ ] Verify all messages appear in correct order

### 3.2 Session Context Preservation
- [ ] Execute first command: "What is 2+2?"
- [ ] Execute second command: "Multiply by 3"
- [ ] Verify second command uses session_id from first
- [ ] Verify context is preserved between commands

### 3.3 Multiple Commands
- [ ] Execute 5+ commands in sequence
- [ ] Verify chat history accumulates correctly
- [ ] Verify current execution clears between commands
- [ ] Verify History mode shows all commands

### 3.4 View Mode Persistence
- [ ] Set view mode to History
- [ ] Close and reopen terminal
- [ ] Verify mode is restored
- [ ] Switch between terminals
- [ ] Verify each terminal remembers its mode

### 3.5 Concurrent Sessions
- [ ] Create 3 headless terminals
- [ ] Execute commands in each simultaneously
- [ ] Verify messages don't mix between sessions
- [ ] Verify each session has its own chat history

---

## Performance Testing

### P.1 Latency
- [ ] Command execution starts within 1 second
- [ ] Chat messages update within 500ms
- [ ] View mode switching is instant (< 100ms)
- [ ] TTS generation starts within 2 seconds of completion

### P.2 Memory
- [ ] Monitor memory usage with long chat histories
- [ ] Verify no memory leaks
- [ ] Verify app handles 100+ messages smoothly

### P.3 UI Responsiveness
- [ ] Verify UI remains responsive during streaming
- [ ] Verify scrolling is smooth with many messages
- [ ] Verify no lag when toggling view modes

---

## Edge Cases

### E.1 Empty Responses
- [ ] Test command with no assistant response
- [ ] Verify no TTS is triggered
- [ ] Verify error message appears if needed

### E.2 Very Long Messages
- [ ] Test command that generates very long response
- [ ] Verify chat interface handles it correctly
- [ ] Verify scrolling works properly

### E.3 Special Characters
- [ ] Test commands with special characters
- [ ] Test responses with code blocks
- [ ] Test responses with markdown
- [ ] Verify all display correctly

### E.4 Rapid Commands
- [ ] Send commands rapidly (one after another)
- [ ] Verify each command is processed
- [ ] Verify chat history is correct
- [ ] Verify no race conditions

---

## Regression Testing

### R.1 Regular Terminals
- [ ] Verify regular terminals still work
- [ ] Verify PTY mode unchanged
- [ ] Verify terminal output streaming works

### R.2 Existing Features
- [ ] Verify voice recording still works
- [ ] Verify transcription still works
- [ ] Verify TTS still works for global agent
- [ ] Verify session management still works

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

## Notes

- Test on physical iPhone device (not just simulator)
- Test with real voice commands (not just text)
- Test with actual cursor-agent and claude CLI tools
- Monitor console logs for errors
- Check memory usage in Instruments
- Test with poor network conditions
