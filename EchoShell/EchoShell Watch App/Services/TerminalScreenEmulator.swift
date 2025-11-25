//
//  TerminalScreenEmulator.swift
//  EchoShell Watch App
//
//  Created for Voice-Controlled Terminal Management System
//  Emulates terminal screen state by processing ANSI escape sequences
//

import Foundation

/// Emulates a terminal screen by processing ANSI escape sequences
class TerminalScreenEmulator {
    private var screen: [String] = []
    private var cursorRow: Int = 0
    private var cursorCol: Int = 0
    private let maxLines = 1000
    
    func processOutput(_ text: String) {
        var remaining = text
        
        while !remaining.isEmpty {
            if let escIndex = remaining.firstIndex(of: "\u{001B}") {
                let beforeEsc = String(remaining[..<escIndex])
                if !beforeEsc.isEmpty {
                    writeText(beforeEsc)
                }
                
                let afterEsc = String(remaining[remaining.index(after: escIndex)...])
                if let consumed = processEscapeSequence(afterEsc) {
                    remaining = String(afterEsc[afterEsc.index(afterEsc.startIndex, offsetBy: consumed)...])
                } else {
                    remaining = afterEsc
                }
            } else {
                writeText(remaining)
                break
            }
        }
    }
    
    func getScreenContent() -> String {
        var lines = screen
        while !lines.isEmpty && lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
    
    func reset() {
        screen = []
        cursorRow = 0
        cursorCol = 0
    }
    
    private func writeText(_ text: String) {
        while cursorRow >= screen.count {
            screen.append("")
        }
        
        if text.contains("\n") {
            let parts = text.components(separatedBy: "\n")
            for (index, part) in parts.enumerated() {
                if index == 0 {
                    writeToLine(part, atRow: cursorRow, atCol: cursorCol)
                    cursorCol += part.count
                } else {
                    cursorRow += 1
                    cursorCol = 0
                    writeToLine(part, atRow: cursorRow, atCol: cursorCol)
                    cursorCol = part.count
                }
            }
        } else {
            writeToLine(text, atRow: cursorRow, atCol: cursorCol)
            cursorCol += text.count
        }
        
        if screen.count > maxLines {
            screen.removeFirst(screen.count - maxLines)
            cursorRow = min(cursorRow, maxLines - 1)
        }
    }
    
    private func writeToLine(_ text: String, atRow row: Int, atCol col: Int) {
        while row >= screen.count {
            screen.append("")
        }
        
        let currentLine = screen[row]
        var newLine = Array(currentLine)
        
        while newLine.count < col {
            newLine.append(" ")
        }
        
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
    
    private func processEscapeSequence(_ text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        
        if text.first == "[" {
            var consumed = 1
            var sequence = "["
            
            var index = text.index(after: text.startIndex)
            while index < text.endIndex {
                let char = text[index]
                sequence.append(char)
                consumed += 1
                
                if char.isLetter {
                    processCSI(sequence)
                    return consumed
                }
                
                index = text.index(after: index)
            }
            
            return consumed
        }
        
        return nil
    }
    
    private func processCSI(_ sequence: String) {
        let inner = String(sequence.dropFirst().dropLast())
        let command = sequence.last!
        
        switch command {
        case "K":
            processEraseInLine(inner)
        case "A":
            processCursorUp(inner)
        case "B":
            processCursorDown(inner)
        case "C":
            processCursorForward(inner)
        case "D":
            processCursorBackward(inner)
        case "G":
            processCursorHorizontalAbsolute(inner)
        case "H":
            processCursorPosition(inner)
        case "m":
            break
        default:
            break
        }
    }
    
    private func processEraseInLine(_ params: String) {
        let param = params.isEmpty ? "0" : params
        
        while cursorRow >= screen.count {
            screen.append("")
        }
        
        let currentLine = screen[cursorRow]
        
        switch param {
        case "0", "":
            if cursorCol < currentLine.count {
                screen[cursorRow] = String(currentLine.prefix(cursorCol))
            }
        case "1":
            if cursorCol < currentLine.count {
                screen[cursorRow] = String(currentLine.dropFirst(cursorCol))
                cursorCol = 0
            } else {
                screen[cursorRow] = ""
                cursorCol = 0
            }
        case "2":
            screen[cursorRow] = ""
            cursorCol = 0
        default:
            break
        }
    }
    
    private func processCursorUp(_ params: String) {
        let count = Int(params) ?? 1
        cursorRow = max(0, cursorRow - count)
    }
    
    private func processCursorDown(_ params: String) {
        let count = Int(params) ?? 1
        cursorRow += count
    }
    
    private func processCursorForward(_ params: String) {
        let count = Int(params) ?? 1
        cursorCol += count
    }
    
    private func processCursorBackward(_ params: String) {
        let count = Int(params) ?? 1
        cursorCol = max(0, cursorCol - count)
    }
    
    private func processCursorHorizontalAbsolute(_ params: String) {
        let col = Int(params) ?? 1
        cursorCol = max(0, col - 1)
    }
    
    private func processCursorPosition(_ params: String) {
        if params.isEmpty {
            cursorRow = 0
            cursorCol = 0
        } else {
            let parts = params.split(separator: ";")
            if parts.count == 2 {
                let row = Int(parts[0]) ?? 1
                let col = Int(parts[1]) ?? 1
                cursorRow = max(0, row - 1)
                cursorCol = max(0, col - 1)
            } else if parts.count == 1 {
                let row = Int(parts[0]) ?? 1
                cursorRow = max(0, row - 1)
                cursorCol = 0
            }
        }
    }
}

