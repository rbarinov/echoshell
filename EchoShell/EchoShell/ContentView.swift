import SwiftUI

struct ContentView: View {
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var watchManager = WatchConnectivityManager.shared
    
    var body: some View {
        TabView {
            // EXISTING: Tab 1 - Recording
            RecordingView()
                .environmentObject(settingsManager)
                .tabItem {
                    Label("Record", systemImage: "mic.fill")
                }
            
            // NEW: Tab 2 - Terminal (only in laptop mode)
            if settingsManager.isLaptopMode {
                TerminalView()
                    .environmentObject(settingsManager)
                    .tabItem {
                        Label("Terminal", systemImage: "terminal.fill")
                    }
            }
            
            // EXISTING: Tab 3 - Settings
            SettingsView()
                .environmentObject(settingsManager)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .onAppear {
            print("📱 iOS ContentView: App appeared")
            print("📱 iOS ContentView: Operation mode: \(settingsManager.operationMode.displayName)")
        }
    }
}

#Preview {
    ContentView()
}
