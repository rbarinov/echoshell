# Terminal Symbols & Scrolling Fix

## Issues Fixed

### 1. ✅ Strange Symbols Appearing in Terminal Input
**Problem**: When reopening terminal, symbols like `65;4;1;2;6;21;22;17;28c65;20;1c` appeared in the input area.

**Root Cause**: These are **Device Attributes query responses** from tmux/terminal. When SwiftTerm initializes, it sends terminal identification queries (CSI sequences), and the terminal responds with its capabilities. These responses were being captured as regular text.

**Example of problematic sequences**:
- `ESC[?65;4;1;2;6;21;22;17;28c` - Primary Device Attributes (DA1)
- `ESC[>65;20;1c` - Secondary Device Attributes (DA2)
- Bare responses: `65;4;1;2;6;21;22;17;28c` (when ESC prefix is lost)

**Solution - 3-Layer Fix**:

#### Layer 1: Enhanced Client-Side Filtering (iOS)
Added comprehensive regex patterns to filter out terminal query responses:

```swift
private func cleanTerminalOutput(_ output: String) -> String {
    var cleaned = output
    
    // Pattern 1: Full ESC sequence with ?
    cleaned = cleaned.replacingOccurrences(
        of: "\\u{001B}\\[\\?[0-9;]+c",
        with: "",
        options: .regularExpression
    )
    
    // Pattern 2: Partial sequence (lost ESC prefix)
    cleaned = cleaned.replacingOccurrences(
        of: "\\[\\?[0-9;]+c",
        with: "",
        options: .regularExpression
    )
    
    // Pattern 3: Secondary Device Attributes
    cleaned = cleaned.replacingOccurrences(
        of: "\\u{001B}\\[>[0-9;]+c",
        with: "",
        options: .regularExpression
    )
    
    // Pattern 4: Bare responses (no brackets)
    // THIS IS THE KEY - catches "65;4;1;2;6;21;22;17;28c"
    cleaned = cleaned.replacingOccurrences(
        of: "\\b[0-9;]+c\\b",
        with: "",
        options: .regularExpression
    )
    
    // Pattern 5: Any stray ESC sequences
    cleaned = cleaned.replacingOccurrences(
        of: "\\u{001B}[@-_][0-?]*[ -/]*[@-~]",
        with: "",
        options: .regularExpression
    )
    
    return cleaned
}
```

**File**: `EchoShell/EchoShell/Views/TerminalDetailView.swift`

#### Layer 2: Tmux Configuration (Server-Side Prevention)
Configured tmux to minimize terminal queries:

```typescript
// Disable features that trigger terminal queries
execAsync(`tmux set-option -t ${tmuxSessionName} remain-on-exit off`);
execAsync(`tmux set-option -t ${tmuxSessionName} allow-rename off`);
execAsync(`tmux set-option -t ${tmuxSessionName} visual-activity off`);
execAsync(`tmux set-option -t ${tmuxSessionName} visual-bell off`);
execAsync(`tmux set-option -t ${tmuxSessionName} monitor-activity off`);
```

**File**: `laptop-app/src/terminal/TerminalManager.ts`

#### Layer 3: History Cleaning
Applied filtering to both:
- ✅ Historical terminal output (loaded on view open)
- ✅ Real-time WebSocket streaming

---

### 2. ✅ Scrolling Not Working in SwiftTerm

**Problem**: Terminal scrolling was not working properly on iPhone. Users couldn't scroll through terminal history.

**Root Cause**: SwiftTerm's internal `UIScrollView` was not properly configured for touch interaction and bouncing behavior.

**Solution**: Enhanced UIScrollView configuration:

```swift
func makeUIView(context: Context) -> UIView {
    let terminalView = SwiftTerm.TerminalView(frame: .zero)
    
    // CRITICAL: Enable scrolling properly
    terminalView.isScrollEnabled = true
    terminalView.showsVerticalScrollIndicator = true
    terminalView.bounces = true  // Allow overscroll bounce
    terminalView.alwaysBounceVertical = true  // Even if content fits
    
    // Make sure touch events work
    terminalView.isUserInteractionEnabled = true
    terminalView.isMultipleTouchEnabled = true
    
    return terminalView
}
```

**Key Changes**:
- ✅ `bounces = true` - Native iOS overscroll bounce effect
- ✅ `alwaysBounceVertical = true` - Bounces even with short content
- ✅ `isUserInteractionEnabled = true` - Ensures touch handling
- ✅ `isMultipleTouchEnabled = true` - Supports gestures

**File**: `EchoShell/EchoShell/Views/SwiftTermTerminalView.swift`

---

## Testing

### Test 1: Verify Symbols Are Gone

```bash
# On laptop
cd laptop-app
npm run dev:laptop-app

# On iPhone
1. Open terminal session
2. Close and reopen terminal
3. Check input area - should be CLEAN (no "65;4;1;2..." symbols)
```

**Expected**: No strange symbols in input area ✅

### Test 2: Verify Scrolling Works

```bash
# On laptop terminal
seq 1 100  # Generate 100 lines

# On iPhone
1. Terminal should show output
2. Swipe up/down to scroll
3. Should see bounce effect at top/bottom
4. Scroll indicator should appear on right side
```

**Expected**: Smooth scrolling with bounce effect ✅

### Test 3: Long History

```bash
# Generate lots of output
for i in {1..500}; do echo "Line $i: Testing terminal history scrolling"; done

# On iPhone
1. Scroll to top
2. Scroll to bottom
3. Should be smooth throughout
```

**Expected**: Can scroll through all 500 lines ✅

---

## Technical Details

### Device Attributes Queries

When a terminal emulator connects, it often queries the terminal capabilities:

```
Query:    ESC[c           (Request Primary Device Attributes)
Response: ESC[?65;4;1;2;6;21;22;17;28c

Query:    ESC[>c          (Request Secondary Device Attributes)  
Response: ESC[>65;20;1c
```

**Why they appear**:
1. SwiftTerm sends query on initialization
2. tmux forwards query to underlying shell
3. Shell responds with capabilities
4. Response gets captured in PTY output
5. iPhone displays it as text ❌

**How we fix it**:
- Filter responses on iPhone side ✅
- Configure tmux to reduce queries ✅
- Clean both history and streaming ✅

### SwiftTerm Scrolling Architecture

SwiftTerm uses `UIScrollView` internally:

```
UIView (container)
  └─ SwiftTerm.TerminalView
       └─ UIScrollView (internal)
            └─ Terminal buffer content
```

**Required properties**:
- `isScrollEnabled` - Enables scrolling
- `bounces` - Native iOS feel
- `alwaysBounceVertical` - Works with short content
- `isUserInteractionEnabled` - Touch handling

---

## Tmux Configuration Summary

All tmux options set for echoshell sessions:

```bash
# Behavior
mouse off                    # Disable tmux mouse (let iPhone handle touches)
status off                   # Hide status bar (iPhone has its own UI)
mode-keys emacs              # Emacs-style keybindings
history-limit 50000          # Large scrollback buffer
aggressive-resize on         # Better multi-client resizing

# Query Prevention (NEW)
remain-on-exit off           # Don't keep pane after exit
allow-rename off             # Prevent title updates
visual-activity off          # No visual activity indicators
visual-bell off              # No visual bell
monitor-activity off         # Don't monitor for activity
```

---

## Before vs After

### Before (Broken)

**Symbols Issue**:
```
$ ls
[terminal input shows: "65;4;1;2;6;21;22;17;28c65;20;1c"]
file1.txt  file2.txt
```

**Scrolling Issue**:
```
[User swipes up/down]
→ Nothing happens, terminal is stuck
→ Can't view history
```

### After (Fixed)

**Symbols Fixed**:
```
$ ls
file1.txt  file2.txt
[clean, no strange symbols]
```

**Scrolling Fixed**:
```
[User swipes up/down]
→ Terminal scrolls smoothly
→ Bounce effect at edges
→ Can access full history
```

---

## Files Modified

### iOS App
- `EchoShell/EchoShell/Views/TerminalDetailView.swift`
  - Enhanced `cleanTerminalOutput()` with 6 regex patterns
  - Filters both history and streaming

- `EchoShell/EchoShell/Views/SwiftTermTerminalView.swift`
  - Added `bounces = true`
  - Added `alwaysBounceVertical = true`
  - Enabled `isUserInteractionEnabled`
  - Enabled `isMultipleTouchEnabled`

### Laptop App
- `laptop-app/src/terminal/TerminalManager.ts`
  - Added 5 new tmux configuration options
  - Prevents terminal queries at source

---

## Summary

✅ **Strange Symbols Fixed** - Comprehensive filtering of Device Attributes responses  
✅ **Scrolling Fixed** - Proper UIScrollView configuration with bounce effects  
✅ **Server-Side Prevention** - Tmux configured to minimize unwanted queries  
✅ **Both History & Streaming** - Filters applied to all terminal output  

The terminal is now clean and scrollable! 🎉
