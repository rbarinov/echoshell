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
        
        // Create terminal view using SwiftTerm with default settings
        let terminalView = SwiftTerm.TerminalView(frame: .zero)
        terminalView.terminalDelegate = context.coordinator
        terminalView.backgroundColor = .black
        terminalView.nativeBackgroundColor = .black
        terminalView.nativeForegroundColor = .white
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        
        // Ensure keyboard appears when terminal becomes first responder
        // SwiftTerm's TerminalView should handle this automatically, but we ensure it's enabled
        terminalView.isUserInteractionEnabled = true
        
        // Ensure terminal view can accept text input (shows standard keyboard)
        // SwiftTerm's TerminalView implements UITextInput protocol, so it should show keyboard automatically
        // Explicitly set inputView to nil to ensure standard iOS keyboard appears
        // (If SwiftTerm has a custom inputView, this will override it to show standard keyboard)
        terminalView.inputView = nil
        
        // Use default SwiftTerm settings - it handles tabs, colors, and ANSI sequences automatically
        // Enable scrolling
        terminalView.isScrollEnabled = true
        terminalView.showsVerticalScrollIndicator = true
        terminalView.bounces = true
        terminalView.alwaysBounceVertical = true
        
        // Enable touch interaction
        terminalView.isUserInteractionEnabled = true
        terminalView.isMultipleTouchEnabled = true
        
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if terminalView.canBecomeFirstResponder {
                if terminalView.becomeFirstResponder() {
                    // Force keyboard to appear by reloading input views
                    terminalView.reloadInputViews()
                }
            }
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
        
        // Feed data directly to terminal - called from parent view
        // Must be called on main thread
        func feed(_ text: String) {
            guard let terminalView = terminalView, !text.isEmpty else { return }
            // Ensure we're on main thread
            if Thread.isMainThread {
                terminalView.feed(text: text)
                // Auto-scroll to bottom after feeding data (especially after clear command)
                scrollToBottom()
            } else {
                DispatchQueue.main.async {
                    terminalView.feed(text: text)
                    // Auto-scroll to bottom after feeding data
                    self.scrollToBottom()
                }
            }
        }
        
        // Scroll terminal to bottom to show cursor
        func scrollToBottom() {
            guard let terminalView = terminalView else { return }
            // SwiftTerm's TerminalView is a UIScrollView, so we can scroll it
            // Wait a bit for layout to update, then scroll to bottom
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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
            }
        }
        
        // Reset terminal
        func reset() {
            guard let terminalView = terminalView else { return }
            terminalView.feed(text: "\u{001B}c")  // ESC c = Full reset
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
            // Terminal scrolled
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
            if let text = String(bytes: data, encoding: .utf8) {
                onInput?(text)
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
