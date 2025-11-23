//
//  TunnelConfig.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//

import Foundation

struct TunnelConfig: Codable, Equatable {
    let tunnelId: String
    let tunnelUrl: String
    let wsUrl: String
    let keyEndpoint: String
    
    // Computed property for full API base URL
    var apiBaseUrl: String {
        return "\(tunnelUrl)/api/\(tunnelId)"
    }
}
