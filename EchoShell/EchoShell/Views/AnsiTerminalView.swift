//
//  AnsiTerminalView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  High-quality terminal view with ANSI color support
//

import SwiftUI
import UIKit

struct AnsiTerminalView: UIViewRepresentable {
    let text: String
    let font: UIFont
    
    func makeUIView(context: Context) -> TerminalTextView {
        let textView = TerminalTextView()
        textView.font = font
        textView.backgroundColor = .black
        textView.textColor = .white
        textView.isEditable = false
        textView.isSelectable = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        return textView
    }
    
    func updateUIView(_ uiView: TerminalTextView, context: Context) {
        let attributedText = AnsiParser.parse(text)
        uiView.attributedText = attributedText
    }
}

class TerminalTextView: UITextView {
    override var canBecomeFirstResponder: Bool {
        return false
    }
}

// MARK: - ANSI Parser
class AnsiParser {
    static func parse(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        ]
        
        // Split by ANSI escape sequences
        let pattern = #"(\x1b\[[0-9;]*m)"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        
        var lastIndex = text.startIndex
        var currentAttributes = defaultAttributes
        
        for match in matches {
            // Add text before the escape sequence
            if lastIndex < text.index(text.startIndex, offsetBy: match.range.location) {
                let range = lastIndex..<text.index(text.startIndex, offsetBy: match.range.location)
                let substring = String(text[range])
                result.append(NSAttributedString(string: substring, attributes: currentAttributes))
            }
            
            // Parse the escape sequence
            let escapeRange = Range(match.range, in: text)!
            let escapeCode = String(text[escapeRange])
            currentAttributes = parseAnsiCode(escapeCode, currentAttributes: currentAttributes)
            
            lastIndex = text.index(text.startIndex, offsetBy: match.range.location + match.range.length)
        }
        
        // Add remaining text
        if lastIndex < text.endIndex {
            let substring = String(text[lastIndex...])
            result.append(NSAttributedString(string: substring, attributes: currentAttributes))
        }
        
        return result
    }
    
    private static func parseAnsiCode(_ code: String, currentAttributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes = currentAttributes
        
        // Extract codes (e.g., "31" from "\x1b[31m")
        let codePattern = #"\[([0-9;]*)"#
        guard let regex = try? NSRegularExpression(pattern: codePattern, options: []),
              let match = regex.firstMatch(in: code, options: [], range: NSRange(code.startIndex..., in: code)),
              let codeRange = Range(match.range(at: 1), in: code) else {
            return attributes
        }
        
        let codesString = String(code[codeRange])
        let codes = codesString.split(separator: ";").compactMap { Int($0) }
        
        var foregroundColor: UIColor?
        var backgroundColor: UIColor?
        var isBold = false
        var isDim = false
        var isUnderline = false
        
        for code in codes {
            switch code {
            case 0: // Reset
                foregroundColor = .white
                backgroundColor = nil
                isBold = false
                isDim = false
                isUnderline = false
                
            case 1: // Bold
                isBold = true
            case 2: // Dim
                isDim = true
            case 3: // Italic (not supported in monospaced font)
                break
            case 4: // Underline
                isUnderline = true
                
            case 30: foregroundColor = .black
            case 31: foregroundColor = .systemRed
            case 32: foregroundColor = .systemGreen
            case 33: foregroundColor = .systemYellow
            case 34: foregroundColor = .systemBlue
            case 35: foregroundColor = .systemPurple
            case 36: foregroundColor = .cyan
            case 37: foregroundColor = .white
            case 90: foregroundColor = .darkGray
            case 91: foregroundColor = .systemRed
            case 92: foregroundColor = .systemGreen
            case 93: foregroundColor = .systemYellow
            case 94: foregroundColor = .systemBlue
            case 95: foregroundColor = .systemPurple
            case 96: foregroundColor = .cyan
            case 97: foregroundColor = .white
                
            case 40: backgroundColor = .black
            case 41: backgroundColor = .systemRed
            case 42: backgroundColor = .systemGreen
            case 43: backgroundColor = .systemYellow
            case 44: backgroundColor = .systemBlue
            case 45: backgroundColor = .systemPurple
            case 46: backgroundColor = .cyan
            case 47: backgroundColor = .white
                
            default:
                break
            }
        }
        
        // Apply colors
        if let fg = foregroundColor {
            attributes[.foregroundColor] = fg
        }
        if let bg = backgroundColor {
            attributes[.backgroundColor] = bg
        }
        
        // Apply font weight
        let baseFont = attributes[.font] as? UIFont ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        var weight: UIFont.Weight = .regular
        if isBold {
            weight = .bold
        } else if isDim {
            weight = .light
        }
        attributes[.font] = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: weight)
        
        // Apply underline
        if isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else {
            attributes.removeValue(forKey: .underlineStyle)
        }
        
        return attributes
    }
}
