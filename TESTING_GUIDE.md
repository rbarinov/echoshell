# Testing Guide: Headless Terminal Refactoring

## Overview

This guide describes how to test the refactored headless terminal architecture.

---

## Test Structure

### Backend Tests (TypeScript/Jest)

**Location**: `laptop-app/src/**/__tests__/`

**Key Test Files**:
- `terminal/__tests__/HeadlessExecutor.test.ts` - Subprocess management
- `output/__tests__/AgentOutputParser.test.ts` - JSON parsing and ChatMessage conversion
- `output/__tests__/HeadlessOutputProcessor.test.ts` - Legacy processor (still used)

**Running Tests**:
```bash
cd laptop-app
npm test
```

### iOS Tests (Swift/Testing Framework)

**Location**: `EchoShell/EchoShellTests/`

**Key Test Files**:
- `ChatMessageTests.swift` - ChatMessage model tests
- `ChatViewModelTests.swift` - Chat state management tests
- `IntegrationTests.swift` - End-to-end flow tests

**Running Tests**:
```bash
# In Xcode: Cmd+U
# Or via command line:
xcodebuild test -scheme EchoShell -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## Test Scenarios

### 1. Backend: HeadlessExecutor

**Test**: Subprocess spawning and lifecycle
```typescript
// Should spawn cursor-agent with correct flags
// Should include --resume when session_id exists
// Should handle stdout/stderr callbacks
// Should kill subprocess gracefully
```

### 2. Backend: AgentOutputParser

**Test**: JSON stream parsing
```typescript
// Should parse user messages
// Should parse assistant messages
// Should parse tool messages with metadata
// Should extract session_id
// Should detect completion (result messages)
// Should handle malformed JSON gracefully
```

### 3. Backend: TerminalManager

**Test**: Session creation and command execution
```typescript
// Should create HeadlessExecutor for headless terminals
// Should create PTY for regular terminals
// Should initialize chatHistory for headless
// Should execute commands via subprocess for headless
// Should preserve session_id across commands
```

### 4. iOS: ChatMessage

**Test**: Model serialization
```swift
// Should encode/decode correctly
// Should handle all message types
// Should preserve metadata
```

### 5. iOS: ChatViewModel

**Test**: State management
```swift
// Should accumulate messages in history
// Should separate current execution from history
// Should toggle view modes correctly
```

### 6. Integration: Full Flow

**Test**: End-to-end command execution
```swift
// Voice command → transcription → execution → chat messages → TTS
// Verify all messages appear in correct order
// Verify TTS triggers on completion
```

---

## Manual Testing

See `MANUAL_TESTING_CHECKLIST.md` for comprehensive manual testing scenarios.

---

## Test Coverage Goals

- **Backend**: ~70% coverage for new components
- **iOS**: ~60% coverage for chat interface components
- **Integration**: All critical paths covered

---

## Known Test Issues

### HeadlessExecutor Tests

Some tests may need mock fixes for subprocess spawning. The structure is correct, but mocks may need adjustment based on actual Node.js child_process behavior.

**Status**: Tests created, may need minor fixes during execution.

---

**Last Updated**: 2025-01-27
