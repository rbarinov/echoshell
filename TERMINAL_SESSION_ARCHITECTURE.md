# Terminal Session Architecture (No tmux)

## Overview

The terminal sessions now use **direct PTY (pseudo-terminal) connections** instead of tmux. This eliminates:
- ❌ tmux resize issues
- ❌ tmux control sequences appearing in output
- ❌ tmux interference with terminal behavior
- ✅ Clean, direct terminal access from iPhone

## Previous Architecture (With tmux)

```
┌─────────────────┐
│   tmux Session  │ ← Both iPhone and Terminal.app attached
│  echoshell-xxx  │ ← Resize conflicts and control sequences
└─────────────────┘
```

**Problems:**
1. tmux sends Device Attributes responses (`[?65;4;1;2;6;21;22;17;28c`)
2. Resize conflicts when iPhone and Terminal.app have different sizes
3. tmux intercepts and modifies terminal control sequences
4. Complex setup and tmux dependency

## New Architecture (Direct PTY)

```
┌─────────────────────┐
│   Direct PTY        │
│   (bash/zsh)        │
└──────────┬──────────┘
           │
           │ (direct access)
           │
      ┌────▼────┐
      │ iPhone  │
      │  App    │
      └─────────┘

┌─────────────────────┐
│  Terminal.app       │
│  (Info Window)      │ ← Monitoring only
└─────────────────────┘
```

**Benefits:**
1. ✅ No control sequence artifacts
2. ✅ Clean terminal output
3. ✅ Responsive resize (iPhone controls size)
4. ✅ No tmux dependency
5. ✅ Simpler architecture

## How It Works

### Session Creation

```typescript
// Direct shell spawn (no tmux)
const pty = spawn(shell, [], {
  name: 'xterm-256color',
  cols: 80,
  rows: 30,
  cwd: workingDir,
  env: {
    ...process.env,
    TERM: 'xterm-256color',
    TMUX: undefined  // Disable tmux auto-attach
  }
});
```

### iPhone Control

- **Input**: iPhone sends keystrokes → PTY processes → output
- **Output**: PTY output → streamed to iPhone in real-time
- **Resize**: iPhone sends resize → PTY.resize(cols, rows)

### Terminal.app Window

The Terminal.app window is now **informational only**:

```
🖥️  EchoShell Terminal Session
Session ID: session-1763905250392
Working Dir: /Users/username

📱 This session is being controlled from your iPhone
💡 Type commands on your iPhone to see them here
⚠️  Commands typed here will NOT sync to iPhone (direct PTY access only)
```

**Purpose**: Shows you that a session is active, but **not** a mirror.

## Control Sequence Filtering

Even without tmux, some control sequences may appear. We filter them on the iPhone side:

### Filtered Sequences

```swift
// Device Attributes: ESC[?...c
"\\u{001B}\\[\\?[0-9;]+c"

// Secondary Device Attributes: ESC[>...c
"\\u{001B}\\[>[0-9;]+c"

// Device Status Report: ESC[...n
"\\u{001B}\\[[0-9;]+n"

// Partial sequences without ESC
"\\[\\?[0-9;]+c"
"\\[>[0-9;]+c"
```

### Where Filtering Happens

1. **Loading History**: Before displaying buffered output
2. **Real-time Streaming**: Each WebSocket message is cleaned
3. **Result**: Clean terminal display on iPhone

## Terminal Behavior

### TERM Environment

```bash
TERM=xterm-256color
```

- Full 256-color support
- Standard VT100/ANSI escape sequences
- Compatible with SwiftTerm

### Terminal Size

- **Initial**: 80 columns × 30 rows
- **Dynamic**: Resizes when iPhone rotates or SwiftTerm view changes
- **Synchronized**: PTY always matches iPhone terminal size

### Shell Features

All standard shell features work:
- ✅ Colors and ANSI codes
- ✅ Command history (arrow keys)
- ✅ Tab completion
- ✅ Job control (Ctrl+C, Ctrl+Z)
- ✅ Text editors (vim, nano)
- ✅ Interactive programs (top, htop)

## Comparison

| Feature | tmux Architecture | Direct PTY Architecture |
|---------|------------------|------------------------|
| Mirroring | ✅ Full mirror | ❌ Info window only |
| Resize behavior | ❌ Conflicts | ✅ Clean |
| Control sequences | ❌ Artifacts | ✅ Filtered |
| Dependencies | ❌ Requires tmux | ✅ None |
| Setup complexity | ❌ High | ✅ Low |
| iPhone control | ✅ Yes | ✅ Yes |
| Terminal.app typing | ✅ Syncs | ❌ Independent |
| Performance | ⚠️ tmux overhead | ✅ Direct |

## Trade-offs

### What We Lost

- **No True Mirroring**: Terminal.app doesn't show live output
- **No Multi-attach**: Can't have multiple terminals showing same session
- **No Persistence**: Session dies if PTY dies (no detach/reattach)

### What We Gained

- **Clean Output**: No tmux control sequences
- **Better Resize**: PTY directly follows iPhone size
- **Simpler**: No tmux installation or configuration needed
- **Faster**: No tmux processing overhead
- **More Control**: Direct PTY manipulation

## Future: True Mirroring Without tmux

To implement true mirroring without tmux, we would need:

### Option 1: PTY Duplication

```typescript
// Create a second PTY that mirrors the first
const mirrorPty = spawn('script', ['-q', '/dev/null', 'bash']);
// Forward all input/output between PTYs
```

**Complexity**: High  
**Benefit**: True mirroring

### Option 2: WebSocket Viewer

```typescript
// Stream PTY output to a web interface
// Terminal.app opens browser pointing to localhost viewer
```

**Complexity**: Medium  
**Benefit**: Cross-platform viewing

### Option 3: Named Pipes

```typescript
// Use Unix named pipes (FIFOs) for IPC
// Terminal.app tails the output pipe
```

**Complexity**: Medium  
**Benefit**: Native Unix tools

**Current Decision**: Keep it simple for now. iPhone has full control, Terminal.app shows info.

## Troubleshooting

### Problem: Still Seeing Control Sequences

**Check regex patterns** in `TerminalDetailView.swift`:

```swift
private func cleanTerminalOutput(_ output: String) -> String {
    // Add more patterns if needed
}
```

**Add logging**:
```swift
print("Raw output: \(output)")
print("Cleaned output: \(cleanOutput)")
```

### Problem: Terminal.app Window Shows Old Info

**Expected behavior**: Terminal.app window is static, shows session info only.

**To see live output**: Use iPhone app exclusively.

### Problem: Resize Not Working

**Check**:
1. SwiftTerm `onResize` callback is called
2. HTTP POST to `/terminal/:sessionId/resize` succeeds
3. Laptop logs show `📐 Resized terminal`

**Debug**:
```swift
print("📐 Terminal size changed: \(cols)x\(rows)")
```

### Problem: Colors Not Working

**Check TERM**:
```bash
echo $TERM
# Should output: xterm-256color
```

**Test colors**:
```bash
for i in {0..255}; do echo -e "\e[38;5;${i}mColor ${i}\e[0m"; done
```

## Configuration

### Change Default Shell

```typescript
// laptop-app/src/terminal/TerminalManager.ts
const shell = '/bin/zsh';  // or '/bin/bash', '/bin/fish', etc.
```

### Change Initial Size

```typescript
const pty = spawn(shell, [], {
  cols: 100,  // Default 80
  rows: 40,   // Default 30
  // ...
});
```

### Disable Terminal.app Window

```typescript
// Comment out this line in createSession()
// this.openTerminalWindow(sessionId, tmuxSessionName)
```

## Related Files

- `laptop-app/src/terminal/TerminalManager.ts` - PTY management
- `EchoShell/EchoShell/Views/TerminalDetailView.swift` - Control sequence filtering
- `EchoShell/EchoShell/Views/SwiftTermTerminalView.swift` - Terminal rendering
- `EchoShell/EchoShell/Services/WebSocketClient.swift` - Output streaming

## Summary

✅ **Removed tmux** - No more resize issues  
✅ **Direct PTY** - Clean, fast terminal access  
✅ **Control sequence filtering** - Clean iPhone display  
✅ **Simpler architecture** - Easier to maintain  
⚠️ **No mirroring** - Terminal.app shows info only  

The system now provides a **clean, direct terminal experience** on iPhone without tmux interference!
