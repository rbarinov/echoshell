//
//  EchoShellApp.swift
//  EchoShell
//
//  Created by Roman Barinov on 2025.11.20.
//

import SwiftUI

@main
struct EchoShellApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sessionState = SessionStateManager.shared
    
    init() {
        // Initialize WatchConnectivity when app launches
        _ = WatchConnectivityManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionState)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
        }
    }
    
    // MARK: - Lifecycle Handling
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            print("📱 App became active")
            handleAppBecameActive()
            
        case .inactive:
            print("📱 App became inactive (transitioning)")
            // Don't interrupt operations - might be temporary (control center, call, etc.)
            
        case .background:
            print("📱 App entered background")
            handleAppEnteredBackground()
            
        @unknown default:
            break
        }
    }
    
    private func handleAppBecameActive() {
        // Restore WebSocket connections if needed
        // Check if ephemeral keys need refresh
        // Resume any paused operations
        // Note: ViewModels handle their own state restoration via loadState()
    }
    
    private func handleAppEnteredBackground() {
        // Save all ViewModel states
        // Keep audio session active for TTS playback
        // Pause non-critical operations
        
        // Note: Don't end IdleTimer operations - they're still needed in background
        // for TTS playback to continue
    }
    
    // Handle app termination - clean up resources
    private func handleAppWillTerminate() {
        // Clean up IdleTimer when app terminates
        IdleTimerManager.shared.endAllOperations()
    }
}

// App delegate to handle orientation locking and lifecycle
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Force portrait orientation on launch
        if #available(iOS 16.0, *) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return true }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Clean up IdleTimer when app terminates
        Task { @MainActor in
            IdleTimerManager.shared.endAllOperations()
        }
    }
}
