import SwiftUI

struct ContentView: View {
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var watchManager = WatchConnectivityManager.shared
    
    // Track active tab to prevent duplicate event handling
    @State private var activeTab: Int = 0
    
    var body: some View {
        TabView(selection: $activeTab) {
            // Tab 1 - Agent Mode
            RecordingView(isActiveTab: activeTab == 0)
                .environmentObject(settingsManager)
                .onAppear {
                    // Set to agent mode when this tab appears
                    settingsManager.commandMode = .agent
                }
                .tabItem {
                    Label("Agent", systemImage: "brain.head.profile")
                }
                .tag(0)
            
            // Tab 2 - Terminals List (only when connected to laptop)
            if settingsManager.laptopConfig != nil {
                TerminalView()
                    .environmentObject(settingsManager)
                    .tabItem {
                        Label("Terminals", systemImage: "terminal.fill")
                    }
                    .tag(1)
            }
            
            // Tab 3 - Settings
            SettingsView()
                .environmentObject(settingsManager)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
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
