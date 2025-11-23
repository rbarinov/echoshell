//
//  EchoShellWatchAppApp.swift
//  EchoShell Watch App
//
//  Created by Roman Barinov on 2025.11.20.
//

import SwiftUI

@main
struct EchoShellWatchAppApp: App {
    @StateObject private var audioRecorder = AudioRecorder()
    
    init() {
        // Initialize WatchConnectivity when app launches
        _ = WatchConnectivityManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioRecorder)
        }
    }
}
