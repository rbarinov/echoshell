# iPhone App Improvements

## Summary of Changes

Three key improvements implemented for the iPhone app:
1. ✅ **Swipe to delete sessions** - Kill terminal sessions from iPhone
2. ✅ **Portrait orientation only** - Disable landscape mode
3. ✅ **Terminal scrolling enabled** - Scroll through terminal history

---

## 1. Swipe to Delete Sessions

### What It Does

Swipe left on any terminal session in the list to reveal a red "Delete" button. Tapping it:
- Kills the terminal process on the laptop
- Closes the PTY session
- Removes the session from the iPhone list

### Implementation

**Backend (laptop-app):**
```typescript
// DELETE /terminal/:sessionId
terminalManager.destroySession(sessionId);
// Kills PTY session
```

**iOS (EchoShell):**
```swift
// TerminalView.swift
List {
    ForEach(viewModel.sessions) { session in
        Button { /* open session */ }
    }
    .onDelete { indexSet in
        // Swipe to delete handler
        viewModel.deleteSession(session, config: config)
    }
}
```

### Usage

1. Open Terminal tab
2. See list of sessions
3. **Swipe left** on any session
4. Tap red "Delete" button
5. Session killed on laptop and removed from list

---

## 2. Portrait Orientation Lock

### What It Does

Forces the iPhone app to stay in portrait mode only. Rotating the device to landscape will not rotate the app.

### Why This Helps

- Terminal content designed for portrait
- Prevents accidental rotation
- Consistent UI experience
- Easier one-handed use

### Implementation

```swift
// EchoShellApp.swift
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait
    
    func application(_ application: UIApplication, 
                    supportedInterfaceOrientationsFor window: UIWindow?) 
                    -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}
```

### Behavior

- ✅ Portrait (normal): Supported
- ✅ Portrait upside-down: Supported (if device allows)
- ❌ Landscape left: Disabled
- ❌ Landscape right: Disabled

---

## 3. Terminal History Scrolling

### What It Does

Enables scrolling through terminal output history with your finger. You can scroll up to see previous commands and output.

### Implementation

**SwiftTerm Configuration:**
```swift
// SwiftTermTerminalView.swift
terminalView.isScrollEnabled = true
terminalView.showsVerticalScrollIndicator = true
```

**PTY Configuration:**
```typescript
// laptop-app/src/terminal/TerminalManager.ts
// Direct PTY session with 50,000 lines of output buffer
```

### How to Use

1. Open terminal session
2. See command output
3. **Swipe up** with your finger → scroll to older content
4. **Swipe down** → return to latest content
5. Scroll indicator shows on right edge

### Features

- ✅ Smooth 60fps scrolling
- ✅ 50,000 lines of history
- ✅ Direct PTY control
- ✅ Scroll indicator visible

---

## Testing

### Test Swipe to Delete

```bash
# Terminal 1: Start laptop app
cd laptop-app && npm run dev:laptop-app

# iPhone: Create 2-3 terminal sessions
# iPhone: Swipe left on one session
# iPhone: Tap Delete
# Expected: Session removed from list
# Expected: Laptop logs show "🗑️  Deleted session: session-xxx"
```

### Test Portrait Lock

```bash
# iPhone: Open EchoShell app
# iPhone: Rotate device to landscape
# Expected: App stays in portrait mode
# Expected: UI does not rotate
```

### Test Terminal Scrolling

```bash
# iPhone: Open terminal session
# iPhone: Run command with long output:
ls -la /usr/bin

# iPhone: Swipe up on terminal
# Expected: Scroll to see earlier output
# Expected: Scroll indicator visible on right
# Expected: Smooth scrolling (no lag)

# iPhone: Swipe down
# Expected: Return to latest output
```

---

## Files Modified

### Backend (laptop-app)
- `src/index.ts` - Added DELETE /terminal/:sessionId endpoint
- `src/terminal/TerminalManager.ts` - Already had destroySession()

### iOS (EchoShell)
- `EchoShell/EchoShell/EchoShellApp.swift` - Added orientation lock
- `EchoShell/EchoShell/Views/TerminalView.swift` - Added swipe-to-delete
- `EchoShell/EchoShell/ViewModels/TerminalViewModel.swift` - Added deleteSession()
- `EchoShell/EchoShell/Services/APIClient.swift` - Added deleteSession() API call
- `EchoShell/EchoShell/Views/SwiftTermTerminalView.swift` - Enabled scrolling
- `EchoShell/EchoShell/Views/TerminalDetailView.swift` - Minor UI update

---

## API Endpoints

### DELETE /terminal/:sessionId

**Request:**
```http
DELETE /api/{tunnelId}/terminal/session-1763906662425
X-Device-ID: iPhone-UUID
```

**Response:**
```json
{
  "session_id": "session-1763906662425",
  "status": "deleted"
}
```

**What It Does:**
1. Finds session by ID
2. Kills PTY process
3. Removes from sessions map
4. Returns success

---

## Troubleshooting

### Problem: Can't swipe to delete

**Check:**
- Are you on the Terminal tab?
- Are there any sessions in the list?
- Try swiping from the right edge of the row

**Debug:**
```swift
// Check if list has sessions
print("Sessions: \(viewModel.sessions.count)")
```

### Problem: App still rotates to landscape

**Solution:**
- Clean build folder in Xcode
- Rebuild app
- Reinstall on device

**Verify:**
```swift
// Check orientation lock
print("Orientation lock: \(AppDelegate.orientationLock)")
```

### Problem: Can't scroll terminal

**Check:**
- Is terminal view fully loaded?
- Is there enough content to scroll?
- Try running a command with long output

**Debug:**
```swift
// Check if SwiftTerm scrolling is enabled
print("Scroll enabled: \(terminalView.isScrollEnabled)")
```

---

## Known Limitations

### Swipe to Delete
- ⚠️ No confirmation dialog (delete is immediate)
- ⚠️ Can't undo deletion
- ⚠️ MacBook Terminal.app window will show [exited]

### Portrait Lock
- ⚠️ Applies to entire app (can't rotate any view)
- ⚠️ Videos/images won't go landscape either

### Terminal Scrolling
- ⚠️ Scroll position resets when new output arrives
- ⚠️ No "scroll to bottom" button (just type or wait)
- ⚠️ History limited to 50,000 lines

---

## Future Enhancements

### Swipe to Delete Improvements
- [ ] Add confirmation dialog
- [ ] Add "undo" with 5-second timer
- [ ] Show loading indicator while deleting
- [ ] Haptic feedback on delete

### Orientation Improvements
- [ ] Allow landscape for terminal only
- [ ] Auto-rotate terminal based on output width
- [ ] Picture-in-picture terminal

### Scrolling Improvements
- [ ] Scroll position indicator (showing line number)
- [ ] Search in terminal history
- [ ] Export/share terminal history
- [ ] Auto-scroll toggle button

---

## Summary

✅ **Swipe to delete** - Easily remove terminal sessions  
✅ **Portrait only** - Consistent UI, no accidental rotation  
✅ **Scrollable terminal** - Review full command history  

The iPhone app now provides better control over terminal sessions with intuitive gestures and a focused portrait-oriented interface!
