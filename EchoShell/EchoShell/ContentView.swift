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
            
            // Tab 2 - Terminal Agent Mode
            RecordingView(isActiveTab: activeTab == 1)
                .environmentObject(settingsManager)
                .onAppear {
                    // Set to direct mode when this tab appears
                    settingsManager.commandMode = .direct
                }
                .tabItem {
                    Label("Terminal Agent", systemImage: "terminal.fill")
                }
                .tag(1)
            
            // Tab 3 - Terminals List (only when connected to laptop)
            if settingsManager.laptopConfig != nil {
                TerminalView()
                    .environmentObject(settingsManager)
                    .tabItem {
                        Label("Terminals", systemImage: "list.bullet.rectangle")
                    }
            }
            
            // Tab 4 - Settings
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
