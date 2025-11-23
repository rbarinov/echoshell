# Navigation & Scrolling Fixes

## Changes Made

### 1. ✅ Terminal as Navigation Page (Not Sheet/Popover)

**Before**: Terminal opened as a sheet (modal) that could be swiped down  
**After**: Terminal opens as a full navigation page with back button

#### What Changed

**TerminalView.swift**:
```swift
// Before: Sheet presentation
.sheet(item: $selectedSession) { session in
    TerminalDetailView(...)
        .interactiveDismissDisabled(true)
}

// After: Navigation destination
.navigationDestination(item: $selectedSession) { session in
    TerminalDetailView(...)
}
```

**TerminalDetailView.swift**:
```swift
// Before: Custom header with close button
VStack {
    HStack {
        Button { dismiss() } label: { Image("xmark") }
        Text(session.id)
        Circle() // status
    }
    SwiftTermTerminalView(...)
}

// After: Native navigation bar
VStack {
    SwiftTermTerminalView(...)
}
.navigationTitle(session.id)
.navigationBarTitleDisplayMode(.inline)
.toolbar {
    ToolbarItem(placement: .principal) {
        VStack {
            Text(session.id)
            HStack {
                Text(session.workingDir)
                Circle() // status badge
            }
        }
    }
}
```

**Benefits**:
- ✅ Native back button (< Terminal Sessions)
- ✅ Can't swipe down to dismiss accidentally
- ✅ Standard iOS navigation experience
- ✅ Terminal takes full screen
- ✅ Proper navigation stack

---

### 2. ✅ Fixed Scrolling (Disabled Tmux Copy Mode)

**Problem**: When scrolling on Mac Terminal.app, it jumped through command history. This was tmux entering "copy mode" on scroll events.

**Root Cause**: Tmux intercepts scroll events (mouse wheel, Page Up/Down) and enters copy mode to let you scroll through history. But we want native scrolling in SwiftTerm on iPhone.

**Solution**: Unbind ALL tmux scroll keys

#### Tmux Key Unbindings

```typescript
// Unbind mouse wheel scrolling
execAsync(`tmux unbind-key -T root WheelUpPane`);
execAsync(`tmux unbind-key -T root WheelDownPane`);

// Unbind Page Up/Down
execAsync(`tmux unbind-key -T root PPage`);
execAsync(`tmux unbind-key -T root NPage`);

// Unbind copy-mode-vi wheel events
execAsync(`tmux unbind-key -T copy-mode-vi WheelUpPane`);
execAsync(`tmux unbind-key -T copy-mode-vi WheelDownPane`);
```

**What This Does**:
- ❌ Tmux no longer enters copy mode on scroll
- ✅ Scroll events pass through to SwiftTerm
- ✅ Native scrolling in terminal buffer
- ✅ No more jumping through command history

**File**: `laptop-app/src/terminal/TerminalManager.ts`

---

## Testing

### Test 1: Navigation (Not Sheet)

```bash
# On iPhone:
1. Go to Terminal Sessions list
2. Tap a session
3. Should slide in as navigation page (not pop up as sheet)
4. See back button (< Terminal Sessions) in top-left
5. Tap back button to return
6. Cannot swipe down to dismiss ✅
```

### Test 2: Scrolling on iPhone

```bash
# Generate output:
seq 1 100

# On iPhone:
1. Swipe up/down to scroll
2. Should scroll through terminal buffer smoothly
3. Should NOT jump through command history
4. SwiftTerm handles scrolling natively ✅
```

### Test 3: Scrolling on Mac Terminal.app

```bash
# On MacBook:
tmux attach-session -t echoshell-session-12345

# Generate output:
seq 1 100

# Scroll with mouse wheel:
1. Should scroll in native terminal (not tmux copy mode)
2. No more jumping through command history ✅
```

---

## UI Changes

### Navigation Bar Layout

```
┌─────────────────────────────────────┐
│ < Terminal Sessions   session-123   │ ← Compact title
│                      /Users/roman  ● │ ← Working dir + status
├─────────────────────────────────────┤
│                                     │
│  Terminal Output (SwiftTerm)        │
│                                     │
│                                     │
└─────────────────────────────────────┘
```

**Elements**:
- Back button (< Terminal Sessions)
- Session ID (centered, bold)
- Working directory (gray, small)
- Status indicator (green/red circle, 8pt)

---

## Architecture

### Navigation Flow

```
ContentView
  └─ TabView
      └─ TerminalView (NavigationView)
          ├─ List of sessions
          └─ .navigationDestination
              └─ TerminalDetailView (full screen navigation page)
                  └─ SwiftTermTerminalView
```

**Before**: Sheet presentation broke navigation stack  
**After**: Proper NavigationStack hierarchy

---

## Tmux Scroll Key Bindings (Now Disabled)

| Key | Table | Action | Status |
|-----|-------|--------|--------|
| Mouse Wheel Up | `root` | Enter copy mode, scroll up | ❌ Unbound |
| Mouse Wheel Down | `root` | Enter copy mode, scroll down | ❌ Unbound |
| Page Up | `root` | Enter copy mode | ❌ Unbound |
| Page Down | `root` | Enter copy mode | ❌ Unbound |
| Wheel in Copy Mode | `copy-mode-vi` | Scroll in history | ❌ Unbound |

**Result**: Tmux never enters copy mode. All scrolling is native.

---

## Files Modified

### iOS App
- `EchoShell/EchoShell/Views/TerminalView.swift`
  - Changed `.sheet()` to `.navigationDestination()`
  - Removed `.interactiveDismissDisabled()`

- `EchoShell/EchoShell/Views/TerminalDetailView.swift`
  - Removed custom header with close button
  - Added `.navigationTitle()` and `.toolbar()`
  - Removed `@Environment(\.dismiss)`

### Laptop App
- `laptop-app/src/terminal/TerminalManager.ts`
  - Added 6 `tmux unbind-key` commands
  - Disabled all tmux scroll interception

---

## Before vs After

### Navigation

**Before (Sheet)**:
- Terminal pops up from bottom
- Can swipe down to dismiss
- Floats over session list
- Not part of navigation stack

**After (Navigation Page)**:
- Terminal slides in from right
- Back button to dismiss
- Full screen, part of navigation stack
- Standard iOS navigation

### Scrolling

**Before (Tmux Copy Mode)**:
- Scroll on Mac → Tmux enters copy mode
- Jumps through command history
- Can't type until exiting copy mode
- Confusing UX

**After (Native Scrolling)**:
- Scroll on Mac → Native terminal scrolling
- Smooth scroll in current output
- No copy mode interference
- Works like normal terminal

---

## Summary

✅ **Terminal is now a navigation page** - Not a dismissible sheet  
✅ **Native iOS navigation** - Back button, proper stack  
✅ **Scrolling fixed** - Tmux copy mode disabled  
✅ **No history jumping** - Smooth native scrolling  
✅ **Better UX** - Standard iOS patterns  

Terminal navigation and scrolling now work perfectly! 🎉
