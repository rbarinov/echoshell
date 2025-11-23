# tmux Session Mirroring

## Overview

The terminal sessions now use **tmux** (terminal multiplexer) to enable true mirroring between your iPhone and MacBook. When you create a terminal session from your iPhone, a tmux session is created that can be viewed and interacted with from multiple places simultaneously.

## How It Works

```
┌─────────────────────┐
│   tmux Session      │
│  echoshell-xxx      │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     │           │
┌────▼────┐ ┌───▼─────┐
│ iPhone  │ │ MacBook │
│  App    │ │Terminal │
└─────────┘ └─────────┘
```

Both clients see **exactly the same terminal state**:
- Commands typed on iPhone appear on MacBook
- Commands typed on MacBook appear on iPhone
- Output is synchronized in real-time
- Terminal size is shared

## Prerequisites

### Install tmux on macOS

```bash
brew install tmux
```

### Verify Installation

```bash
tmux -V
# Should output: tmux 3.x or higher
```

## Architecture Changes

### Before (No Mirroring)
- PTY → iPhone only
- Terminal.app opened separate window with static message
- No synchronization

### After (With Mirroring)
- PTY → tmux session → Multiple clients
- Terminal.app attaches to same tmux session
- Full bidirectional synchronization

## Usage

### 1. Start Laptop App

```bash
cd laptop-app
npm start
```

### 2. Create Session from iPhone

1. Scan QR code
2. Tap "New Session" or create from voice command
3. **Result**: 
   - Terminal.app window opens on MacBook (after ~500ms)
   - Both windows show the **same** terminal session
   - Window title: "EchoShell - session-xxx (Mirror)"

### 3. Test Mirroring

**On iPhone**: Type `ls -la`
- ✅ Command executes
- ✅ Output appears on iPhone
- ✅ Output appears on MacBook Terminal.app

**On MacBook**: Type `pwd`
- ✅ Command executes  
- ✅ Output appears on MacBook Terminal.app
- ✅ Output appears on iPhone

### 4. Close Session

When you close the session from iPhone:
- PTY is killed
- tmux session is terminated
- Terminal.app window closes (or shows "[exited]")

## tmux Session Names

Format: `echoshell-session-{timestamp}`

Example: `echoshell-session-1763905250392`

### List All Sessions

```bash
tmux list-sessions
```

### Manually Attach to Session

```bash
tmux attach-session -t echoshell-session-1763905250392
```

### Manually Kill Session

```bash
tmux kill-session -t echoshell-session-1763905250392
```

## Troubleshooting

### Problem: Terminal.app Window Doesn't Open

**Check if tmux is installed:**
```bash
which tmux
```

**Install if missing:**
```bash
brew install tmux
```

**Check laptop app logs:**
Look for: `✅ Opened Terminal.app window attached to tmux session`

### Problem: "Session Not Found" Error

**Cause**: tmux session was killed but PTY still running

**Solution**: Restart laptop app
```bash
# Stop laptop app (Ctrl+C)
# Start again
npm start
```

### Problem: Terminal.app Shows "[exited]"

**Cause**: Shell inside tmux crashed

**Check PTY logs:**
```bash
# Look at laptop app console output
```

**Recreate session:**
- Close session from iPhone
- Create new session

### Problem: Input Not Syncing

**Check WebSocket connection:**
- iPhone app should show "Connected" (green dot)
- Laptop app logs should show: `⌨️ Terminal input for session-xxx`

**Reconnect:**
- Close and reopen terminal session in iPhone app

### Problem: MacBook Terminal Laggy

**Possible causes:**
- Network latency (data flows: MacBook → Tunnel → iPhone → Tunnel → MacBook)
- tmux overhead

**Solutions:**
- Type directly in MacBook Terminal.app for instant feedback
- Use iPhone for remote access only

## Advanced Configuration

### Custom tmux Configuration

Create `~/.tmux.conf`:

```bash
# Better colors
set -g default-terminal "screen-256color"

# Mouse support
set -g mouse on

# Larger history
set -g history-limit 10000

# Status bar
set -g status-bg black
set -g status-fg white
set -g status-left "[EchoShell] "
```

### Change Default Shell

```bash
# In laptop-app/src/terminal/TerminalManager.ts
# Modify line ~89:
const shell = '/bin/zsh';  // or '/bin/bash'
```

## Technical Details

### PTY → tmux Integration

```typescript
// Old approach (no mirroring)
const pty = spawn(shell, [], { ... });

// New approach (with mirroring)
const pty = spawn('tmux', [
  'new-session',
  '-s', tmuxSessionName,
  '-c', cwd,
  shell
], { ... });
```

### Terminal.app Attachment

```applescript
tell application "Terminal"
  do script "tmux attach-session -t echoshell-session-xxx"
  activate
  set custom title of front window to "EchoShell - session-xxx (Mirror)"
end tell
```

### Session Lifecycle

1. **Create**: `tmux new-session -s name`
2. **Attach iPhone**: PTY connected via node-pty
3. **Attach MacBook**: Terminal.app via AppleScript
4. **Destroy**: `tmux kill-session -t name`

## Benefits

✅ **True Mirroring**: Both devices see identical terminal state  
✅ **Multi-attach**: Can attach from multiple Terminal.app windows  
✅ **Persistence**: Session survives network disconnections  
✅ **Native Feel**: Terminal.app behaves like local terminal  
✅ **Debugging**: Can watch commands execute on MacBook  

## Limitations

⚠️ **macOS Only**: Terminal.app mirroring requires macOS  
⚠️ **tmux Required**: Must install tmux (`brew install tmux`)  
⚠️ **Slight Delay**: 500ms delay before Terminal.app opens  
⚠️ **Single Shell**: One shell instance per session  

## Next Steps

1. Test creating a session from iPhone
2. Verify Terminal.app window opens
3. Test typing on both iPhone and MacBook
4. Verify output synchronization
5. Test terminal resize from iPhone
6. Test closing session

## Related Files

- `laptop-app/src/terminal/TerminalManager.ts` - tmux integration
- `TERMINAL_FIXES.md` - Previous fixes documentation
- `IMPLEMENTATION_SUMMARY.md` - Overall architecture
