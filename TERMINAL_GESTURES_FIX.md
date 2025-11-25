# Fixed: Terminal Swipe Gesture & Orientation Issues

## Issues Fixed

### 1. ✅ Disabled Swipe-Down-to-Dismiss on Terminal
**Problem**: Swiping down in terminal would dismiss the view instead of scrolling  
**Solution**: Added `.interactiveDismissDisabled(true)` to prevent swipe-to-dismiss

### 2. ✅ Blocked Landscape Orientation
**Problem**: Device rotation still allowed landscape mode  
**Solution**: Updated both code and Xcode project settings

---

## Implementation Details

### 1. Swipe-Down-to-Dismiss Fix

**File**: `TerminalDetailView.swift`

```swift
.navigationTitle(session.id)
.navigationBarTitleDisplayMode(.inline)
.toolbar { /* ... */ }
.interactiveDismissDisabled(true)  // 🔒 Prevents swipe-down-to-dismiss
.onAppear { /* ... */ }
```

**What it does:**
- Disables the iOS sheet gesture that allows swiping down to close
- Terminal scrolling now works properly
- Must use "Done" button to close terminal

**Result:**
- ✅ Swipe down = scroll terminal up
- ✅ Swipe up = scroll terminal down  
- ✅ No accidental dismissal
- ✅ "Done" button required to close

---

### 2. Landscape Orientation Lock

**Three-layer approach:**

#### Layer 1: App Delegate
**File**: `EchoShellApp.swift`

```swift
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait
    
    func application(_ application: UIApplication, 
                    supportedInterfaceOrientationsFor window: UIWindow?) 
                    -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}
```

#### Layer 2: Launch Configuration
**File**: `EchoShellApp.swift`

```swift
func application(_ application: UIApplication, 
                didFinishLaunchingWithOptions launchOptions: ...) -> Bool {
    // Force portrait on launch
    if #available(iOS 16.0, *) {
        guard let windowScene = UIApplication.shared.connectedScenes.first 
                    as? UIWindowScene else { return true }
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }
    return true
}
```

#### Layer 3: Xcode Project Settings
**File**: `EchoShell.xcodeproj/project.pbxproj`

**Before:**
```
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = 
    "UIInterfaceOrientationPortrait 
     UIInterfaceOrientationLandscapeLeft 
     UIInterfaceOrientationLandscapeRight";
```

**After:**
```
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = 
    "UIInterfaceOrientationPortrait";
```

---

## Testing

### Test Swipe-Down-to-Dismiss Fix

```bash
# iPhone: Open terminal session
# iPhone: Try to swipe down from top of terminal
# Expected: Terminal scrolls, does NOT dismiss
# Expected: Must tap "Done" button to close
```

**Behavior:**
| Gesture | Old Behavior | New Behavior |
|---------|--------------|--------------|
| Swipe down in terminal | Dismiss view ❌ | Scroll terminal ✅ |
| Tap "Done" | Close ✅ | Close ✅ |
| Swipe down on nav bar | Dismiss ❌ | Nothing (locked) ✅ |

### Test Orientation Lock

```bash
# iPhone: Open EchoShell app
# iPhone: Rotate device to landscape
# Expected: App stays in portrait
# Expected: UI does NOT rotate

# iPhone: Try in all views (Settings, Terminal, Recording)
# Expected: All views stay portrait
```

**Behavior:**
| Device Orientation | App Display |
|-------------------|-------------|
| Portrait (normal) | Portrait ✅ |
| Landscape left | Portrait ✅ |
| Landscape right | Portrait ✅ |
| Portrait upside-down | Portrait ✅ |

---

## Why This Fixes The Issues

### Swipe-Down Problem

**The Conflict:**
```
SwiftUI Sheet
  └─ Swipe down gesture → Dismiss sheet
  └─ Terminal ScrollView
       └─ Swipe down gesture → Scroll up
```

iOS couldn't tell which gesture you intended.

**The Solution:**
```
SwiftUI Sheet (.interactiveDismissDisabled)
  ├─ Swipe down gesture → DISABLED ❌
  └─ Terminal ScrollView
       └─ Swipe down gesture → Works! ✅
```

Now only the terminal receives swipe gestures.

### Orientation Problem

**The Issue:**
- Code-level orientation lock was not enough
- Xcode project settings override code settings
- Need both to be aligned

**The Fix:**
1. **Code**: AppDelegate returns `.portrait` mask
2. **Code**: Request portrait geometry on launch
3. **Project**: Remove landscape from Info.plist keys

All three layers now enforce portrait-only.

---

## Files Modified

### Swift Files
- `EchoShell/EchoShell/EchoShellApp.swift`
  - Added `@UIApplicationDelegateAdaptor`
  - Implemented `didFinishLaunchingWithOptions`
  
- `EchoShell/EchoShell/Views/TerminalDetailView.swift`
  - Added `.interactiveDismissDisabled(true)`

### Project Files
- `EchoShell/EchoShell.xcodeproj/project.pbxproj`
  - Removed `UIInterfaceOrientationLandscapeLeft`
  - Removed `UIInterfaceOrientationLandscapeRight`

---

## Rebuild Required

**Important**: After modifying project.pbxproj, you MUST:

1. **Clean Build Folder**
   - Xcode → Product → Clean Build Folder (⇧⌘K)

2. **Rebuild App**
   - Xcode → Product → Build (⌘B)

3. **Reinstall on Device**
   - Delete app from iPhone
   - Run from Xcode again

**Why?** Xcode caches build settings. Without clean build, old settings persist.

---

## Troubleshooting

### Problem: Still Can't Scroll Terminal

**Debug steps:**
1. Check if `.interactiveDismissDisabled(true)` is present
2. Verify SwiftTerm has `isScrollEnabled = true`
3. Check if there's enough content to scroll

**Test:**
```bash
# iPhone terminal: Run command with lots of output
cat /usr/share/dict/words

# Should be able to scroll through all words
```

### Problem: Still Rotates to Landscape

**Debug steps:**
1. Did you clean build folder?
2. Did you reinstall app (not just rerun)?
3. Check project settings in Xcode:
   - Target → General → Deployment Info
   - Should only have "Portrait" checked

**Verify in Xcode:**
```
Project Navigator → EchoShell → 
  General → Deployment Info → 
    iPhone Orientation → 
      ☑️ Portrait
      ☐ Upside Down (optional)
      ☐ Landscape Left
      ☐ Landscape Right
```

### Problem: Can't Close Terminal

**Solution:**
- Tap "Done" button in top-left
- Swipe-to-dismiss is intentionally disabled
- This is correct behavior!

---

## Known Behaviors

### Expected

✅ **Swipe in terminal = scroll** (not dismiss)  
✅ **Tap Done = close terminal**  
✅ **Device rotation = app stays portrait**  
✅ **All tabs locked to portrait**  

### By Design

⚠️ **Can't swipe down to dismiss terminal** - Use "Done" button  
⚠️ **Can't rotate app** - Portrait only for better UX  
⚠️ **Terminal scrolling uses SwiftTerm** - Native terminal scrolling  

---

## Architecture

### Gesture Handling Flow

```
User Touch Event
    ↓
SwiftUI Sheet Check
    ├─ .interactiveDismissDisabled(true)
    │   → Dismiss gesture BLOCKED ❌
    │
    └─ Pass to child views
           ↓
    SwiftTermTerminalView
           ↓
    SwiftTerm.TerminalView
           ↓
    Handle scroll gesture ✅
```

### Orientation Handling Flow

```
Device Rotation Event
    ↓
iOS System Query: "What orientations are supported?"
    ↓
AppDelegate.application(...supportedInterfaceOrientationsFor...)
    ├─ Check AppDelegate.orientationLock
    │   → Returns: .portrait
    │
    └─ iOS: "OK, only portrait allowed"
           ↓
    App stays in portrait ✅
```

---

## Summary

✅ **Swipe-down-to-dismiss** - Disabled to allow terminal scrolling  
✅ **Landscape orientation** - Blocked at 3 levels (code + project + runtime)  
✅ **Terminal scrolling** - Now works smoothly  
✅ **Must use Done button** - Intentional UX decision  

Both issues are now completely fixed! 🎉
