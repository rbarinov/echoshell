import SwiftUI

struct ContentView: View {
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var watchManager = WatchConnectivityManager.shared
    @StateObject private var navigationStateManager = NavigationStateManager()
    @StateObject private var laptopHealthChecker = LaptopHealthChecker()
    
    // Track active tab to prevent duplicate event handling
    @State private var activeTab: Int = 0
    
    // Get connection state for header
    private var connectionState: ConnectionState {
        if settingsManager.laptopConfig != nil {
            return laptopHealthChecker.connectionState
        }
        return .disconnected
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Unified static header
            UnifiedHeaderView(
                navigationState: $navigationStateManager.currentState,
                connectionState: connectionState
            )
            .environmentObject(settingsManager)
            
            // Main content with tabs
            TabView(selection: $activeTab) {
                // Tab 1 - Agent Mode
                RecordingView(isActiveTab: activeTab == 0)
                    .environmentObject(settingsManager)
                    .environmentObject(navigationStateManager)
                    .onAppear {
                        // Set to agent mode when this tab appears
                        settingsManager.commandMode = .agent
                        navigationStateManager.navigateToAgent()
                    }
                    .tabItem {
                        Label("Agent", systemImage: "brain.head.profile")
                    }
                    .tag(0)
                
                // Tab 2 - Terminals List
                TerminalView()
                    .environmentObject(settingsManager)
                    .environmentObject(navigationStateManager)
                    .onAppear {
                        navigationStateManager.navigateToTerminalsList()
                    }
                    .tabItem {
                        Label("Terminals", systemImage: "terminal.fill")
                    }
                    .tag(1)
                
                // Tab 3 - Settings
                SettingsView()
                    .environmentObject(settingsManager)
                    .environmentObject(navigationStateManager)
                    .onAppear {
                        navigationStateManager.navigateToSettings()
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(2)
            }
        }
        .environmentObject(settingsManager)
        .environmentObject(navigationStateManager)
        .onAppear {
            print("📱 iOS ContentView: App appeared")
            print("📱 iOS ContentView: Operation mode: Laptop Mode (Terminal Control)")
            
            // Start health checker
            if let config = settingsManager.laptopConfig {
                laptopHealthChecker.start(config: config)
            }
        }
        .onChange(of: settingsManager.laptopConfig) { oldValue, newValue in
            if let config = newValue {
                laptopHealthChecker.start(config: config)
            } else {
                laptopHealthChecker.stop()
            }
        }
    }
}

#Preview {
    ContentView()
}
