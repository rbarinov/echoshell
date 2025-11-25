import SwiftUI

struct ContentView: View {
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var watchManager = WatchConnectivityManager.shared
    
    var body: some View {
        TabView {
            // Tab 1 - Recording
            RecordingView()
                .environmentObject(settingsManager)
                .tabItem {
                    Label("Record", systemImage: "mic.fill")
                }
            
            // Tab 2 - Terminal (only when connected to laptop)
            if settingsManager.laptopConfig != nil {
                TerminalView()
                    .environmentObject(settingsManager)
                    .tabItem {
                        Label("Terminal", systemImage: "terminal.fill")
                    }
            }
            
            // Tab 3 - Settings
            SettingsView()
                .environmentObject(settingsManager)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .onAppear {
            print("📱 iOS ContentView: App appeared")
            print("📱 iOS ContentView: Operation mode: Laptop Mode (Terminal Control)")
        }
    }
}

#Preview {
    ContentView()
}
