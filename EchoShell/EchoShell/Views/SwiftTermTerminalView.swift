//
//  SwiftTermTerminalView.swift
//  EchoShell
//
//  Terminal view using SwiftTerm library for professional terminal emulation
//  Based on: https://github.com/migueldeicaza/SwiftTerm
//  Note: SwiftTerm is only available on iOS, not watchOS
//

import SwiftUI

#if os(iOS)
import SwiftTerm

/// SwiftUI wrapper for SwiftTerm's TerminalView
/// Provides full VT100/ANSI terminal emulation with color support
struct SwiftTermTerminalView: UIViewRepresentable {
    var onInput: ((String) -> Void)?
    var onResize: ((Int, Int) -> Void)?
    var onReady: ((SwiftTermTerminalView.Coordinator) -> Void)?
    
    func makeUIView(context: Context) -> UIView {
        // Create a container view
        let container = UIView(frame: .zero)
        container.backgroundColor = .black
        
        // Create terminal view using SwiftTerm with proper settings for mobile
        let terminalView = SwiftTerm.TerminalView(frame: .zero)
        terminalView.terminalDelegate = context.coordinator
        terminalView.backgroundColor = .black
        terminalView.nativeBackgroundColor = .black
        terminalView.nativeForegroundColor = .white
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        
        // CRITICAL: Disable local echo for remote terminals
        // The server PTY will echo back characters, so we don't want SwiftTerm to echo locally
        // This prevents double character display (local echo + server echo)
        // Note: SwiftTerm handles echo correctly by default for remote terminals
        print("✅ SwiftTerm: Using default echo handling (server will handle echo)")
        
        // Configure terminal for proper display on mobile
        // Set proper font size for mobile readability (12pt is good for mobile)
        terminalView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        
        // SwiftTerm handles tabs natively with standard 8-space tab stops
        // No need to configure tab width - SwiftTerm uses standard VT100 tab stops
        
        // Ensure keyboard appears when terminal becomes first responder
        // SwiftTerm's TerminalView should handle this automatically, but we ensure it's enabled
        terminalView.isUserInteractionEnabled = true
        
        // Ensure terminal view can accept text input (shows standard keyboard)
        // SwiftTerm's TerminalView implements UITextInput protocol, so it should show keyboard automatically
        // Explicitly set inputView to nil to ensure standard iOS keyboard appears
        // (If SwiftTerm has a custom inputView, this will override it to show standard keyboard)
        terminalView.inputView = nil
        
        // Use default SwiftTerm settings - it handles tabs, colors, and ANSI sequences automatically
        // Enable scrolling with proper configuration
        terminalView.isScrollEnabled = true
        terminalView.showsVerticalScrollIndicator = true
        terminalView.bounces = false // Disable bounce for better terminal feel
        terminalView.alwaysBounceVertical = false
        terminalView.showsHorizontalScrollIndicator = false // Hide horizontal scroll for terminal
        
        // Enable touch interaction
        terminalView.isUserInteractionEnabled = true
        terminalView.isMultipleTouchEnabled = false // Disable multi-touch for terminal
        
        // Store terminal view in coordinator
        context.coordinator.terminalView = terminalView
        
        container.addSubview(terminalView)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        // Make terminal view become first responder to show keyboard immediately
        // Also ensure local echo is disabled after terminal is fully initialized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if terminalView.canBecomeFirstResponder {
                if terminalView.becomeFirstResponder() {
                    // Force keyboard to appear by reloading input views
                    terminalView.reloadInputViews()
                }
            }
            
            // Note: SwiftTerm handles echo correctly by default for remote terminals
            print("✅ SwiftTerm: Terminal initialized and ready")
            
            onReady?(context.coordinator)
        }
        
        return container
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Ensure terminal view becomes first responder when view updates
        // This ensures keyboard appears when user taps on terminal
        let container = uiView
        
        for subview in container.subviews {
            if let terminalView = subview as? SwiftTerm.TerminalView {
                // Always try to become first responder if not already
                if terminalView.canBecomeFirstResponder && !terminalView.isFirstResponder {
                    DispatchQueue.main.async {
                        _ = terminalView.becomeFirstResponder()
                    }
                }
                break
            }
        }  
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.onInput = onInput
        coordinator.onResize = onResize
        return coordinator
    }
    
    /// Coordinator handles delegate callbacks from TerminalView and provides data feeding
    class Coordinator: NSObject, TerminalViewDelegate {
        var terminalView: SwiftTerm.TerminalView?
        var onInput: ((String) -> Void)?
        var onResize: ((Int, Int) -> Void)?
        
        // Track if user is manually scrolling (to avoid auto-scroll interrupting user)
        private var isUserScrolling = false
        private var lastScrollCheckTime: Date?

        // Feed data directly to terminal - called from parent view
        // Must be called on main thread
        func feed(_ text: String) {
            guard let terminalView = terminalView, !text.isEmpty else { return }

            // Check if we should auto-scroll (only if user is at bottom or not manually scrolling)
            let shouldAutoScroll = shouldScrollToBottom()

            // Ensure we're on main thread
            if Thread.isMainThread {
                // Feed text directly to SwiftTerm - it handles all formatting
                terminalView.feed(text: text)
                // Only auto-scroll if user was already at bottom
                if shouldAutoScroll {
                    scrollToBottomSmooth()
                }
            } else {
                DispatchQueue.main.async {
                    // Feed text directly to SwiftTerm - it handles all formatting
                    terminalView.feed(text: text)
                    // Only auto-scroll if user was already at bottom
                    if shouldAutoScroll {
                        self.scrollToBottomSmooth()
                    }
                }
            }
        }

        // Feed history data without auto-scroll (for initial history load)
        // This keeps the terminal at the top when loading large histories
        func feedHistory(_ text: String) {
            guard let terminalView = terminalView, !text.isEmpty else { return }

            // Ensure we're on main thread
            if Thread.isMainThread {
                // Feed text directly to SwiftTerm - it handles all formatting
                terminalView.feed(text: text)
                // DO NOT auto-scroll - keep terminal at top to show history
            } else {
                DispatchQueue.main.async {
                    // Feed text directly to SwiftTerm - it handles all formatting
                    terminalView.feed(text: text)
                    // DO NOT auto-scroll - keep terminal at top to show history
                }
            }
        }

        // Check if we should auto-scroll to bottom
        // Returns true if user is already at bottom or hasn't manually scrolled recently
        private func shouldScrollToBottom() -> Bool {
            guard let terminalView = terminalView else { return false }

            // If user is manually scrolling, don't auto-scroll
            if isUserScrolling {
                return false
            }

            // Check if user scrolled manually in last 2 seconds
            if let lastCheck = lastScrollCheckTime,
               Date().timeIntervalSince(lastCheck) < 2.0 {
                return false
            }

            // Check if we're already at bottom (within 50 points threshold)
            let contentHeight = terminalView.contentSize.height
            let frameHeight = terminalView.frame.height
            let currentOffset = terminalView.contentOffset.y
            let maxOffset = max(0, contentHeight - frameHeight)

            // If we're within 50 points of bottom, consider it "at bottom"
            return (maxOffset - currentOffset) < 50
        }

        // Scroll terminal to bottom smoothly (only when needed)
        private func scrollToBottomSmooth() {
            guard let terminalView = terminalView else { return }

            // Use CATransaction to batch updates and prevent flickering
            CATransaction.begin()
            CATransaction.setDisableActions(true) // Disable implicit animations

            // Force layout update first
            terminalView.layoutIfNeeded()

            let contentHeight = terminalView.contentSize.height
            let frameHeight = terminalView.frame.height

            if contentHeight > frameHeight {
                let bottomOffset = CGPoint(x: 0, y: max(0, contentHeight - frameHeight))
                terminalView.setContentOffset(bottomOffset, animated: false)
            } else {
                // If content fits, scroll to top (0, 0) to show cursor
                terminalView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
            }

            CATransaction.commit()
        }

        // Force scroll to bottom (used for explicit actions like clear, history load)
        func scrollToBottom() {
            guard let terminalView = terminalView else { return }
            // Wait a bit for layout to update, then scroll to bottom
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Use CATransaction to prevent flickering
                CATransaction.begin()
                CATransaction.setDisableActions(true)

                // Force layout update first
                terminalView.layoutIfNeeded()

                let contentHeight = terminalView.contentSize.height
                let frameHeight = terminalView.frame.height

                if contentHeight > frameHeight {
                    let bottomOffset = CGPoint(x: 0, y: max(0, contentHeight - frameHeight))
                    terminalView.setContentOffset(bottomOffset, animated: false)
                } else {
                    // If content fits, scroll to top (0, 0) to show cursor
                    terminalView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
                }

                CATransaction.commit()
            }
        }
        
        // Reset terminal - clear screen and reset cursor
        func reset() {
            guard let terminalView = terminalView else { return }
            // Send full reset sequence: ESC c (reset) + ESC [ 2 J (clear screen) + ESC [ H (home cursor)
            terminalView.feed(text: "\u{001B}c\u{001B}[2J\u{001B}[H")
        }
        
        // Make terminal become first responder (show keyboard)
        func focus() {
            guard let terminalView = terminalView else { return }
            // Make terminal first responder to show keyboard
            DispatchQueue.main.async {
                if terminalView.canBecomeFirstResponder {
                    // Check if there's a custom inputView that might be hiding the keyboard
                    // SwiftTerm's TerminalView should show standard keyboard, but let's ensure it
                    let hasCustomInputView = terminalView.inputView != nil
                    print("🔍 Terminal inputView: \(hasCustomInputView ? "custom" : "nil (will use standard keyboard)")")
                    
                    // First, resign any other first responder
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    
                    // Small delay to ensure resign completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        // Force keyboard to appear by making terminal first responder
                        let becameFirstResponder = terminalView.becomeFirstResponder()
                        print("⌨️ Terminal became first responder: \(becameFirstResponder)")
                        
                        if becameFirstResponder {
                            // Reload input views to ensure keyboard appears
                            terminalView.reloadInputViews()
                            
                            // Additional attempt: explicitly show keyboard if it's still not showing
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if terminalView.isFirstResponder {
                                    terminalView.reloadInputViews()
                                    print("⌨️ Reloaded input views - keyboard should be visible now")
                                }
                            }
                        } else {
                            // If it didn't become first responder, try again after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if terminalView.becomeFirstResponder() {
                                    terminalView.reloadInputViews()
                                    print("⌨️ Retry successful - keyboard should be visible now")
                                }
                            }
                        }
                    }
                } else {
                    print("⚠️ Terminal cannot become first responder")
                }
            }
        }
        
        // MARK: - TerminalViewDelegate Implementation

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {
            // Terminal scrolled - track user scrolling to avoid auto-scroll interference
            isUserScrolling = true
            lastScrollCheckTime = Date()

            // Reset the flag after 2 seconds of no scrolling
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.isUserScrolling = false
            }
        }
        
        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
            // Terminal title changed
        }
        
        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            // Terminal size changed - notify parent
            print("📐 Terminal resized: \(newCols)x\(newRows)")
            onResize?(newCols, newRows)
        }
        
        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            // User typed something - send it to the laptop
            // Convert bytes to string, handling special characters like backspace (0x7f or 0x08)
            let bytes = Array(data)
            
            // Log all input bytes for debugging (especially backspace)
            let byteCodes = bytes.map { String($0) }.joined(separator: ", ")
            print("⌨️ SwiftTerm input received: \(bytes.count) bytes [\(byteCodes)]")
            
            // Handle backspace/delete key (0x7f = DEL, 0x08 = BS)
            // Both should be sent to server as backspace character
            if bytes.count == 1 {
                let byte = bytes[0]
                if byte == 0x7f || byte == 0x08 {
                    // Backspace/Delete key pressed
                    print("⌨️ Backspace/Delete key detected (byte: \(byte))")
                    // Send backspace character (\b = 0x08) to server
                    onInput?("\u{0008}") // \b character
                    return
                }
            }
            
            // Convert bytes to string for regular characters
            if let text = String(bytes: bytes, encoding: .utf8) {
                // Log the text being sent (escape special characters for readability)
                let escapedText = text
                    .replacingOccurrences(of: "\r", with: "\\r")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\t", with: "\\t")
                    .replacingOccurrences(of: "\u{0008}", with: "\\b")
                print("⌨️ Sending input to server: '\(escapedText)' (\(text.count) chars)")
                onInput?(text)
            } else {
                print("⚠️ Failed to convert input bytes to UTF-8 string")
            }
        }
        
        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            // Copy to clipboard
            if let str = String(bytes: content, encoding: .utf8) {
                UIPasteboard.general.string = str
            }
        }
        
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            // Current directory changed
        }
        
        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            // User clicked a hyperlink - open it
            if let fixedup = link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let urlComponents = URLComponents(string: fixedup),
               let url = urlComponents.url {
                UIApplication.shared.open(url)
            }
        }
        
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
            // Visual changes in terminal buffer
        }
        
        func bell(source: SwiftTerm.TerminalView) {
            // Terminal bell - provide haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        }
        
        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {
            // iTerm2-specific inline images - ignore
        }
    }
}

#endif
