# SwiftTerm Integration Guide

## Why SwiftTerm?

We replaced the custom ANSI parser with **SwiftTerm** because:

1. **Professional Quality**: Full VT100/ANSI terminal emulation
2. **Better Performance**: Optimized rendering engine
3. **Active Maintenance**: Regularly updated library
4. **Complete Feature Set**: Cursor movement, colors, formatting, etc.
5. **Battle-Tested**: Used in production apps

## Installation

### Via Xcode (Swift Package Manager)

1. Open `EchoShell.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter URL: `https://github.com/migueldeicaza/SwiftTerm.git`
4. Select version: **Latest** (or specific version like `1.0.0`)
5. Add to target: **EchoShell**
6. Click **Add Package**

### Via Package.swift (if using SPM)

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0")
]
```

## Usage

The `SwiftTermTerminalView` is already integrated in `TerminalDetailView.swift`.

It automatically:
- Parses ANSI escape sequences
- Renders colors and formatting
- Handles cursor movement
- Supports terminal features (scrolling, selection, etc.)

## Migration from Custom ANSI Parser

The old `AnsiTerminalView.swift` has been replaced with `SwiftTermTerminalView.swift`.

**Benefits:**
- ✅ Full VT100 compatibility
- ✅ Better color support (256 colors, RGB)
- ✅ Cursor emulation
- ✅ Terminal features (scrolling, selection)
- ✅ Better performance
- ✅ Less code to maintain

## Resources

- [SwiftTerm GitHub](https://github.com/migueldeicaza/SwiftTerm)
- [Documentation](https://github.com/migueldeicaza/SwiftTerm/blob/main/README.md)
