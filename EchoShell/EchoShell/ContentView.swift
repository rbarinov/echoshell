import SwiftUI

struct ContentView: View {
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var watchManager = WatchConnectivityManager.shared
    @StateObject private var navigationStateManager = NavigationStateManager()
    @StateObject private var laptopHealthChecker = LaptopHealthChecker()
    @StateObject private var terminalViewModel = TerminalViewModel()
    
    @State private var sidebarPresented = false
    @State private var currentView: NavigationState = .supervisor
    
    // Get connection state for header
    private var connectionState: ConnectionState {
        if settingsManager.laptopConfig != nil {
            return laptopHealthChecker.connectionState
        }
        return .disconnected
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Main content based on current view
                VStack(spacing: 0) {
                    // Unified header with sidebar button
                    UnifiedHeaderView(
                        navigationState: $currentView,
                        connectionState: connectionState,
                        sidebarPresented: $sidebarPresented
                    )
                    .environmentObject(settingsManager)
                    
                    // Main content
                    mainContentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .navigationBarHidden(true)
                
                // Sidebar overlay (on top of everything)
                if sidebarPresented {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                sidebarPresented = false
                            }
                        }
                    
                    HStack(spacing: 0) {
                        SidebarView(
                            terminalViewModel: terminalViewModel,
                            isPresented: $sidebarPresented,
                            onSelectSupervisor: {
                                currentView = .supervisor
                                navigationStateManager.navigateToSupervisor()
                                settingsManager.commandMode = .supervisor
                            },
                            onSelectTerminal: { session in
                                currentView = .terminalDetail(
                                    sessionId: session.id,
                                    sessionName: session.name,
                                    workingDir: session.workingDir,
                                    terminalType: session.terminalType
                                )
                                navigationStateManager.navigateToTerminalDetail(session: session)
                            },
                            onSelectSettings: {
                                currentView = .settings
                                navigationStateManager.navigateToSettings()
                            },
                            onCreateTerminal: { terminalType in
                                // Create terminal via EventBus
                                EventBus.shared.createTerminalPublisher.send(terminalType)
                            }
                        )
                        .frame(width: 280)
                        .background(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 2, y: 0)
                        .transition(.move(edge: .leading))
                        
                        Spacer()
                    }
                }
            }
            .gesture(
                // Swipe from left edge to open sidebar
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let verticalAmount = value.translation.height
                        
                        // Detect swipe from left edge to right
                        if abs(horizontalAmount) > abs(verticalAmount) &&
                           horizontalAmount > 50 &&
                           value.startLocation.x < 50 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                sidebarPresented = true
                            }
                        }
                    }
            )
        }
        .environmentObject(settingsManager)
        .environmentObject(navigationStateManager)
        .onAppear {
            print("📱 iOS ContentView: App appeared")
            print("📱 iOS ContentView: Operation mode: Laptop Mode (Terminal Control)")
            
            // Set to supervisor mode on startup
            settingsManager.commandMode = .supervisor
            navigationStateManager.navigateToSupervisor()
            currentView = .supervisor
            
            // Load terminal sessions
            if let config = settingsManager.laptopConfig {
                laptopHealthChecker.start(config: config)
                Task {
                    await terminalViewModel.loadSessions(config: config)
                }
            }
        }
        .onChange(of: settingsManager.laptopConfig) { oldValue, newValue in
            if let config = newValue {
                laptopHealthChecker.start(config: config)
                Task {
                    await terminalViewModel.loadSessions(config: config)
                }
            } else {
                laptopHealthChecker.stop()
            }
        }
        .onChange(of: navigationStateManager.currentState) { oldValue, newValue in
            // Sync current view with navigation state
            currentView = newValue
        }
        .onReceive(EventBus.shared.navigateBackPublisher) { _ in
            // Navigate back to supervisor
            currentView = .supervisor
            navigationStateManager.navigateToSupervisor()
            settingsManager.commandMode = .supervisor
        }
        .onReceive(EventBus.shared.createTerminalPublisher) { terminalType in
            // Create terminal
            guard let config = settingsManager.laptopConfig else { return }
            Task {
                await terminalViewModel.createNewSession(
                    config: config,
                    terminalType: terminalType
                )
                await terminalViewModel.loadSessions(config: config)
                
                // Navigate to newly created terminal
                if let newSession = terminalViewModel.sessions.last {
                    currentView = .terminalDetail(
                        sessionId: newSession.id,
                        sessionName: newSession.name,
                        workingDir: newSession.workingDir,
                        terminalType: newSession.terminalType
                    )
                    navigationStateManager.navigateToTerminalDetail(session: newSession)
                }
            }
        }
        .onReceive(EventBus.shared.terminalDeletedPublisher) { sessionId in
            // Refresh terminal list after deletion
            guard let config = settingsManager.laptopConfig else { return }
            Task {
                await terminalViewModel.loadSessions(config: config)
            }
        }
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        switch currentView {
        case .supervisor:
            RecordingView(isActiveTab: true)
                .environmentObject(settingsManager)
                .environmentObject(navigationStateManager)
        case .terminalsList:
            // Terminal list is now in sidebar, show supervisor instead
            RecordingView(isActiveTab: true)
                .environmentObject(settingsManager)
                .environmentObject(navigationStateManager)
                .onAppear {
                    // Navigate to supervisor if somehow ended up on terminals list
                    currentView = .supervisor
                }
        case .terminalDetail(let sessionId, _, _, _):
            if let session = terminalViewModel.sessions.first(where: { $0.id == sessionId }),
               let config = settingsManager.laptopConfig {
                TerminalDetailView(session: session, config: config)
                    .environmentObject(settingsManager)
                    .environmentObject(navigationStateManager)
            } else {
                // Session not found, go back to supervisor
                RecordingView(isActiveTab: true)
                    .environmentObject(settingsManager)
                    .environmentObject(navigationStateManager)
                    .onAppear {
                        currentView = .supervisor
                    }
            }
        case .settings:
            SettingsView()
                .environmentObject(settingsManager)
                .environmentObject(navigationStateManager)
        }
    }
}

#Preview {
    ContentView()
}
