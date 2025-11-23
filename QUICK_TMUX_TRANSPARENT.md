# Quick Reference: Tmux Transparent Mode

## What Changed

**Before**: Tmux with full features (scrolling, copy mode, status bar, key bindings)  
**After**: Tmux as transparent session mirror ONLY

---

## Key Settings

```bash
# Disable ALL tmux features except session mirroring:

prefix None                    # No Ctrl+B
alternate-screen off           # No tmux scrolling (CRITICAL)
xterm-keys on                 # Pass keys through
status off                    # No UI
mouse off                     # No mouse interception
allow-passthrough on          # Pass escape sequences
set-clipboard off             # No clipboard interception
```

---

## What Tmux Does Now

✅ **Multi-client mirroring** (iPhone ↔ MacBook)  
✅ **Session persistence** (survives disconnections)  

❌ **No scrolling** (handled by SwiftTerm)  
❌ **No key bindings** (Ctrl+B disabled)  
❌ **No status bar** (invisible)  
❌ **No copy mode** (SwiftTerm handles it)  

---

## Testing

```bash
# Test 1: Should see NO tmux UI
tmux attach-session -t echoshell-session-12345
# → Plain terminal, no status bar ✅

# Test 2: Ctrl+B should NOT work
Ctrl+B, c  # Should NOT create window
# → Passed to shell instead ✅

# Test 3: Scrolling should be native
seq 1 100
# → Swipe on iPhone scrolls in SwiftTerm, not tmux ✅
```

---

## Restart to Apply

```bash
# Stop laptop app
Ctrl+C

# Start again
npm run dev:laptop-app

# Create new terminal session
# New sessions will use transparent mode
```

Tmux is now completely invisible! 🎉
