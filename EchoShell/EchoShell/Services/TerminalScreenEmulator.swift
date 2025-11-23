//
//  TerminalScreenEmulator.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Emulates terminal screen state by processing ANSI escape sequences
//

import Foundation

/// Emulates a terminal screen by processing ANSI escape sequences
/// This allows us to track the final state of the screen after all updates,
/// filtering out intermediate "Generating..." messages that get overwritten
class TerminalScreenEmulator {
    private var screen: [String] = [] // Screen lines (grows as needed)
    private var cursorRow: Int = 0
    private var cursorCol: Int = 0
    private let maxLines = 1000 // Limit screen size
    
    /// Process terminal output text, handling ANSI escape sequences
    func processOutput(_ text: String) {
        var remaining = text
        
        while !remaining.isEmpty {
            // Look for ANSI escape sequences (ESC[)
            if let escIndex = remaining.firstIndex(of: "\u{001B}") {
                // Add text before escape sequence
                let beforeEsc = String(remaining[..<escIndex])
                if !beforeEsc.isEmpty {
                    writeText(beforeEsc)
                }
                
                // Process escape sequence (skip ESC, process what follows)
                let afterEsc = String(remaining[remaining.index(after: escIndex)...])
                if let consumed = processEscapeSequence(afterEsc) {
                    // consumed includes the characters after ESC
                    remaining = String(afterEsc[afterEsc.index(afterEsc.startIndex, offsetBy: consumed)...])
                } else {
                    // Invalid escape sequence, skip ESC character and continue
                    remaining = afterEsc
                }
            } else {
                // No more escape sequences, write remaining text
                writeText(remaining)
                break
            }
        }
    }
    
    /// Get the final screen content as a string
    func getScreenContent() -> String {
        // Remove trailing empty lines
        var lines = screen
        while !lines.isEmpty && lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
    
    /// Reset the screen state
    func reset() {
        screen = []
        cursorRow = 0
        cursorCol = 0
    }
    
    // MARK: - Private Methods
    
    /// Write text to current cursor position
    private func writeText(_ text: String) {
        // Ensure we have enough lines
        while cursorRow >= screen.count {
            screen.append("")
        }
        
        let currentLine = screen[cursorRow]
        let _ = Array(currentLine) // Not used, but kept for potential future use
        
        // Handle newlines
        if text.contains("\n") {
            let parts = text.components(separatedBy: "\n")
            for (index, part) in parts.enumerated() {
                if index == 0 {
                    // First part goes to current line
                    writeToLine(part, atRow: cursorRow, atCol: cursorCol)
                    cursorCol += part.count
                } else {
                    // Subsequent parts start new lines
                    cursorRow += 1
                    cursorCol = 0
                    writeToLine(part, atRow: cursorRow, atCol: cursorCol)
                    cursorCol = part.count
                }
            }
        } else {
            // No newlines, just write text
            writeToLine(text, atRow: cursorRow, atCol: cursorCol)
            cursorCol += text.count
        }
        
        // Limit screen size
        if screen.count > maxLines {
            screen.removeFirst(screen.count - maxLines)
            cursorRow = min(cursorRow, maxLines - 1)
        }
    }
    
    /// Write text to a specific line at a specific column
    private func writeToLine(_ text: String, atRow row: Int, atCol col: Int) {
        while row >= screen.count {
            screen.append("")
        }
        
        let currentLine = screen[row]
        let lineChars = Array(currentLine)
        
        // Extend line if needed
        var newLine = lineChars
        while newLine.count < col {
            newLine.append(" ")
        }
        
        // Replace characters at cursor position
        let textChars = Array(text)
        for (index, char) in textChars.enumerated() {
            let pos = col + index
            if pos < newLine.count {
                newLine[pos] = char
            } else {
                newLine.append(char)
            }
        }
        
        screen[row] = String(newLine)
    }
    
    /// Process ANSI escape sequence (text after ESC)
    /// Returns: number of characters consumed, or nil if not a valid sequence
    private func processEscapeSequence(_ text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        
        // Check for CSI (Control Sequence Introducer): [
        if text.first == "[" {
            var consumed = 1 // [
            var sequence = "["
            
            // Collect sequence characters
            var index = text.index(after: text.startIndex)
            while index < text.endIndex {
                let char = text[index]
                sequence.append(char)
                consumed += 1
                
                // Sequence ends with a letter (command)
                if char.isLetter {
                    processCSI(sequence)
                    return consumed
                }
                
                index = text.index(after: index)
            }
            
            // Incomplete sequence, but consume what we have
            return consumed
        }
        
        return nil
    }
    
    /// Process CSI (Control Sequence Introducer) sequence
    private func processCSI(_ sequence: String) {
        // Remove [ and final letter
        let inner = String(sequence.dropFirst().dropLast())
        let command = sequence.last!
        
        switch command {
        case "K": // Erase in Line
            processEraseInLine(inner)
            
        case "A": // Cursor Up
            processCursorUp(inner)
            
        case "B": // Cursor Down
            processCursorDown(inner)
            
        case "C": // Cursor Forward
            processCursorForward(inner)
            
        case "D": // Cursor Backward
            processCursorBackward(inner)
            
        case "G": // Cursor Horizontal Absolute
            processCursorHorizontalAbsolute(inner)
            
        case "H": // Cursor Position
            processCursorPosition(inner)
            
        case "m": // SGR (Select Graphic Rendition) - colors, styles
            // We ignore formatting for now
            break
            
        default:
            // Unknown command, ignore
            break
        }
    }
    
    /// Process Erase in Line (EL) - [K
    /// 0 or default: Erase from cursor to end of line
    /// 1: Erase from start of line to cursor
    /// 2: Erase entire line
    private func processEraseInLine(_ params: String) {
        let param = params.isEmpty ? "0" : params
        
        while cursorRow >= screen.count {
            screen.append("")
        }
        
        let currentLine = screen[cursorRow]
        
        switch param {
        case "0", "":
            // Erase from cursor to end of line
            if cursorCol < currentLine.count {
                let newLine = String(currentLine.prefix(cursorCol))
                screen[cursorRow] = newLine
            }
            
        case "1":
            // Erase from start of line to cursor
            if cursorCol < currentLine.count {
                let newLine = String(currentLine.dropFirst(cursorCol))
                screen[cursorRow] = newLine
                cursorCol = 0
            } else {
                screen[cursorRow] = ""
                cursorCol = 0
            }
            
        case "2":
            // Erase entire line
            screen[cursorRow] = ""
            cursorCol = 0
            
        default:
            break
        }
    }
    
    /// Process Cursor Up (CUU) - [A
    private func processCursorUp(_ params: String) {
        let count = Int(params) ?? 1
        cursorRow = max(0, cursorRow - count)
    }
    
    /// Process Cursor Down (CUD) - [B
    private func processCursorDown(_ params: String) {
        let count = Int(params) ?? 1
        cursorRow += count
    }
    
    /// Process Cursor Forward (CUF) - [C
    private func processCursorForward(_ params: String) {
        let count = Int(params) ?? 1
        cursorCol += count
    }
    
    /// Process Cursor Backward (CUB) - [D
    private func processCursorBackward(_ params: String) {
        let count = Int(params) ?? 1
        cursorCol = max(0, cursorCol - count)
    }
    
    /// Process Cursor Horizontal Absolute (CHA) - [G
    private func processCursorHorizontalAbsolute(_ params: String) {
        let col = Int(params) ?? 1
        cursorCol = max(0, col - 1) // Convert to 0-based
    }
    
    /// Process Cursor Position (CUP) - [H or [row;colH
    private func processCursorPosition(_ params: String) {
        if params.isEmpty {
            // Default: move to (1,1) - top left
            cursorRow = 0
            cursorCol = 0
        } else {
            // Parse row;col
            let parts = params.split(separator: ";")
            if parts.count == 2 {
                let row = Int(parts[0]) ?? 1
                let col = Int(parts[1]) ?? 1
                cursorRow = max(0, row - 1) // Convert to 0-based
                cursorCol = max(0, col - 1) // Convert to 0-based
            } else if parts.count == 1 {
                // Only row specified
                let row = Int(parts[0]) ?? 1
                cursorRow = max(0, row - 1) // Convert to 0-based
                cursorCol = 0
            }
        }
    }
}

