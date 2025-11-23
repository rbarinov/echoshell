# tmux Scrolling Fix

## Problem

When scrolling in the terminal on iPhone, tmux was exhibiting strange behaviors:
- Entering copy mode unexpectedly
- Mouse events interfering with touch scrolling
- Status bar appearing/disappearing
- Vi mode keybindings interfering

## Solution

Configured tmux to disable interfering features while keeping mirroring functionality.

## tmux Configuration Applied

```bash
# Disable mouse support (prevents copy mode on scroll)
set-option -g mouse off

# Disable status bar (no green bar at bottom)
set-option -g status off

# Use emacs mode instead of vi (prevents vi keybindings)
set-option -g mode-keys emacs

# Large scrollback buffer (50,000 lines)
set-option -g history-limit 50000

# Better resize handling
set-option -g aggressive-resize on

# Allow programs to use alternate screen
set-option -g alternate-screen on
```

## What Each Option Does

### `mouse off`
**Problem**: tmux intercepts touch events and tries to handle them as mouse events
**Result**: Scrolling would enter copy mode or select text
**Fix**: Completely disable mouse support - let SwiftTerm handle all touch events

### `status off`
**Problem**: Status bar at bottom showing session name, time, etc.
**Result**: Takes up screen space and can flash/update
**Fix**: Hide status bar completely - iPhone app shows session info

### `mode-keys emacs`
**Problem**: Vi mode keybindings could interfere with terminal behavior
**Result**: Unexpected behavior from vi-style navigation
**Fix**: Use simpler emacs-style keybindings

### `history-limit 50000`
**Problem**: Limited scrollback makes it hard to review long output
**Result**: Older output gets lost
**Fix**: Store 50,000 lines of history

### `aggressive-resize on`
**Problem**: tmux constrains window size to smallest attached client
**Result**: When Terminal.app and iPhone have different sizes, gets confused
**Fix**: Allow each client to have its own view size

### `alternate-screen on`
**Problem**: Some programs (vim, less) use alternate screen buffer
**Result**: Could interfere with tmux screen management
**Fix**: Enable proper alternate screen support

## Implementation

### Global Configuration
Applied once when any tmux session exists:
```typescript
const tmuxConfig = [
  'set-option -g mouse off',
  'set-option -g status off',
  // ... etc
].join(' \\; ');
execAsync(tmuxConfig);
```

### Per-Session Configuration
Applied to each specific session:
```typescript
execAsync(`tmux set-option -t ${sessionName} mouse off`);
execAsync(`tmux set-option -t ${sessionName} status off`);
```

## Testing

### Before Fix
1. Open terminal on iPhone
2. Scroll up with finger
3. **Problem**: Enters tmux copy mode, shows `[0/10]` at top
4. **Problem**: Status bar appears at bottom
5. **Problem**: Can't scroll smoothly

### After Fix
1. Open terminal on iPhone
2. Scroll up with finger
3. ✅ Smooth scrolling via SwiftTerm
4. ✅ No status bar
5. ✅ No copy mode
6. ✅ Natural touch behavior

## SwiftTerm Integration

SwiftTerm handles scrolling natively:
- Touch events → SwiftTerm scroll handling
- SwiftTerm manages viewport position
- No tmux interference
- Smooth 60fps scrolling

## Terminal.app Behavior

On MacBook Terminal.app:
- Status bar still hidden (consistent)
- Mouse still disabled (use keyboard for copy/paste)
- Scrolling works with trackpad/mouse wheel
- tmux copy mode available via keyboard: `Ctrl+B [` if needed

## Additional tmux Commands

If you need to:

### Enable mouse temporarily (in Terminal.app)
```bash
tmux set-option -t echoshell-session-XXX mouse on
```

### Show status bar temporarily
```bash
tmux set-option -t echoshell-session-XXX status on
```

### Check current settings
```bash
tmux show-options -t echoshell-session-XXX
```

### List all sessions
```bash
tmux list-sessions
```

## Troubleshooting

### Problem: Still entering copy mode

**Check if mouse is really disabled:**
```bash
tmux show-options -g | grep mouse
# Should show: mouse off
```

**Manually disable:**
```bash
tmux set-option -g mouse off
```

### Problem: Status bar still showing

**Check status option:**
```bash
tmux show-options -g | grep status
# Should show: status off
```

**Manually disable:**
```bash
tmux set-option -g status off
```

### Problem: Configuration not applying

**Kill all tmux sessions and restart:**
```bash
tmux kill-server
```

Then restart laptop app.

## Files Modified

- `laptop-app/src/terminal/TerminalManager.ts`
  - Added tmux configuration on session creation
  - Applies both global and per-session settings

## Related Documentation

- `TMUX_MIRROR_SETUP.md` - tmux mirroring architecture
- `TERMINAL_FIXES.md` - Terminal input/output fixes
- `TERMINAL_SESSION_ARCHITECTURE.md` - Overall terminal architecture

## Summary

✅ **Disabled mouse** - No copy mode on scroll  
✅ **Hidden status bar** - Clean display  
✅ **Smooth scrolling** - SwiftTerm handles all touch events  
✅ **Large history** - 50,000 lines of scrollback  
✅ **Better resize** - Proper size handling  

tmux now provides mirroring without interfering with iPhone scrolling behavior!
