# Tmux as Plain Terminal (Transparent Session Mirror)

## Philosophy

**Goal**: Use tmux ONLY for session mirroring between iPhone and MacBook. Disable ALL tmux special features to make it behave exactly like a plain terminal.

**Why**: Tmux's features (scrolling, copy mode, status bar, key bindings) interfere with the terminal emulator (SwiftTerm) on iPhone. We want tmux to be completely transparent.

---

## Configuration Applied

### 1. **Disable Tmux Control Keys**
```bash
prefix None       # Disable Ctrl+B (tmux command mode)
prefix2 None      # Disable any secondary prefix
```
**Effect**: Ctrl+B is passed through to shell, not intercepted by tmux.

---

### 2. **Disable Tmux Scrolling/Copy Mode**
```bash
alternate-screen off    # CRITICAL: Don't use alternate screen buffer
xterm-keys on          # Pass all xterm key sequences through
```
**Effect**: Scrolling is handled by SwiftTerm on iPhone, not tmux.

---

### 3. **Disable Visual Features**
```bash
status off              # No status bar
visual-activity off     # No activity alerts
visual-bell off         # No bell notifications
visual-silence off      # No silence alerts
monitor-activity off    # Don't monitor activity
monitor-bell off        # Don't monitor bell
monitor-silence 0       # Don't monitor silence
```
**Effect**: Tmux is completely invisible - no UI elements.

---

### 4. **Disable Window/Pane Management**
```bash
allow-rename off        # Don't allow window renaming
automatic-rename off    # Don't auto-rename windows
remain-on-exit off      # Close when process exits
```
**Effect**: Tmux doesn't interfere with window titles or lifecycle.

---

### 5. **Pass Through Escape Sequences**
```bash
allow-passthrough on    # Pass ALL escape sequences unchanged
set-clipboard off       # Don't intercept clipboard operations
```
**Effect**: All ANSI/VT100 sequences go directly to iPhone's SwiftTerm.

---

### 6. **Multi-Client Support**
```bash
aggressive-resize on    # Resize based on smallest client
history-limit 50000     # Large history buffer
```
**Effect**: Proper mirroring between iPhone and MacBook Terminal.app.

---

### 7. **Disable Mouse**
```bash
mouse off              # Don't intercept mouse/touch events
```
**Effect**: Touch events go to SwiftTerm, not tmux.

---

## What Tmux Still Does

✅ **Session persistence** - Survives disconnections  
✅ **Multi-client mirroring** - iPhone and MacBook see same session  
✅ **Session naming** - Each session has unique ID  

❌ **No scrolling** - Handled by SwiftTerm  
❌ **No copy mode** - Handled by SwiftTerm  
❌ **No status bar** - iPhone has its own UI  
❌ **No key bindings** - All keys go to shell  
❌ **No visual effects** - Completely transparent  

---

## Verification

### Test 1: Tmux Should Be Invisible

```bash
# On MacBook Terminal.app
tmux attach-session -t echoshell-session-12345

# You should see:
# - NO status bar at bottom
# - NO tmux indicators
# - Just a plain terminal
```

### Test 2: Ctrl+B Should Not Work

```bash
# Try tmux commands
Ctrl+B, c    # Should NOT create new window
Ctrl+B, d    # Should NOT detach

# These keys should go to shell instead
```

### Test 3: Scrolling Should Be Native

```bash
# Generate output
seq 1 1000

# On iPhone: Swipe to scroll
# Should scroll in SwiftTerm, NOT enter tmux copy mode
```

### Test 4: No Strange Symbols

```bash
# On iPhone:
1. Open terminal
2. Close and reopen
3. No "65;4;1;2..." symbols should appear
```

---

## Tmux Configuration Summary

| Feature | Setting | Purpose |
|---------|---------|---------|
| **Control Keys** | `prefix None` | Disable Ctrl+B |
| **Scrolling** | `alternate-screen off` | Native scrolling |
| **Status Bar** | `status off` | Hide UI |
| **Mouse** | `mouse off` | Pass touch to iPhone |
| **Clipboard** | `set-clipboard off` | Pass to SwiftTerm |
| **Escape Sequences** | `allow-passthrough on` | Don't filter |
| **Visual Effects** | All `off` | Completely transparent |
| **Window Rename** | `allow-rename off` | Don't interfere |
| **Mirroring** | `aggressive-resize on` | Multi-client support |

---

## Architecture

```
iPhone (SwiftTerm)                MacBook (Terminal.app)
        │                                 │
        └─────────┬───────────────────────┘
                  │
            tmux session
          (transparent proxy)
                  │
              Shell (zsh/bash)
```

**Data Flow**:
1. User types on iPhone → Goes to tmux → Goes to shell
2. Shell produces output → Goes to tmux → Broadcast to iPhone + MacBook
3. Tmux does NO processing - just mirrors data

---

## Key Points

1. **Tmux is now completely transparent** - It's just a session mirror
2. **All features handled by SwiftTerm** - Scrolling, copy, paste, colors
3. **No tmux interference** - No key bindings, no status bar, no copy mode
4. **Still benefits from tmux** - Multi-client, persistence, session naming

---

## Before vs After

### Before (Tmux interfering)
```
User types: Ctrl+B
→ Tmux intercepts: "Enter command mode"
→ Strange behavior on iPhone

User swipes to scroll:
→ Tmux enters copy mode
→ Terminal stuck, can't type
```

### After (Tmux transparent)
```
User types: Ctrl+B
→ Passed to shell unchanged
→ Shell handles it (or ignores)

User swipes to scroll:
→ SwiftTerm scrolls natively
→ Tmux doesn't interfere
```

---

## Files Modified

- `laptop-app/src/terminal/TerminalManager.ts` - Added comprehensive tmux configuration

---

## Summary

✅ Tmux is now a **transparent session mirror**  
✅ All special features **disabled**  
✅ Behaves like a **plain terminal**  
✅ Only used for **multi-client persistence**  

Tmux is invisible! 🎉
