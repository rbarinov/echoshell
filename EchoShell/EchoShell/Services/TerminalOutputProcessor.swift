//
//  TerminalOutputProcessor.swift
//  EchoShell
//
//  Processes terminal output and extracts meaningful content
//

import Foundation

class TerminalOutputProcessor {
    private var lastProcessedScreenOutput: String = ""
    
    // Extract only new lines from screen output
    func extractNewLines(from currentOutput: String) -> String {
        if lastProcessedScreenOutput.isEmpty {
            lastProcessedScreenOutput = currentOutput
            return currentOutput
        }
        
        let currentCleaned = removeAnsiCodes(from: currentOutput)
        let lastCleaned = removeAnsiCodes(from: lastProcessedScreenOutput)
        
        if currentCleaned == lastCleaned {
            return ""
        }
        
        // Check if new content was appended
        if currentCleaned.hasPrefix(lastCleaned) {
            let newContent = String(currentCleaned.dropFirst(lastCleaned.count))
            lastProcessedScreenOutput = currentOutput
            return newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : newContent
        }
        
        // Check if content was prepended
        if currentCleaned.hasSuffix(lastCleaned) && currentCleaned.count > lastCleaned.count {
            let newContent = String(currentCleaned.dropLast(lastCleaned.count))
            lastProcessedScreenOutput = currentOutput
            return newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : newContent
        }
        
        // Compare line by line
        let currentLines = currentCleaned.components(separatedBy: .newlines)
        let lastLines = lastCleaned.components(separatedBy: .newlines)
        
        var newLinesStartIndex = 0
        let minLength = min(currentLines.count, lastLines.count)
        
        if currentLines.count > lastLines.count {
            newLinesStartIndex = lastLines.count
        } else {
            for i in stride(from: minLength - 1, through: 0, by: -1) {
                let currentLine = currentLines[i].trimmingCharacters(in: .whitespaces)
                let lastLine = lastLines[i].trimmingCharacters(in: .whitespaces)
                
                if currentLine != lastLine {
                    newLinesStartIndex = i
                    break
                }
            }
        }
        
        if newLinesStartIndex < currentLines.count {
            let newLines = Array(currentLines[newLinesStartIndex...])
            let result = newLines.joined(separator: "\n")
            lastProcessedScreenOutput = currentOutput
            return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : result
        }
        
        lastProcessedScreenOutput = currentOutput
        return ""
    }
    
    func reset() {
        lastProcessedScreenOutput = ""
    }
    
    // Helper function to remove ANSI codes
    private func removeAnsiCodes(from text: String) -> String {
        let pattern = "\\u{001B}\\[[0-9;]*[a-zA-Z]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}

