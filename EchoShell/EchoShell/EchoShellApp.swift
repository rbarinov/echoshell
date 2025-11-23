//
//  EchoShellApp.swift
//  EchoShell
//
//  Created by Roman Barinov on 2025.11.20.
//

import SwiftUI

@main
struct EchoShellApp: App {
    init() {
        // Initialize WatchConnectivity when app launches
        _ = WatchConnectivityManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
