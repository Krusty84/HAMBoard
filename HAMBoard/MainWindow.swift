//
//  MainWindow.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 17/11/2025.
//

import SwiftUI

/// Root view of the HAMBoard app – a tab-based interface with three main sections:
/// 1. DX Cluster (live spots + statistics)
/// 2. Propagation (real-time ionospheric maps)
/// 3. Contest calendar
/// 4. Settings
/// Also hosts global overlays: real-time UTC/local clock (top-right) and live top-bands/countries stats (top-left).
///
struct MainWindow: View {
    
    // MARK: - Persisted Settings (AppStorage)
    
    /// Operator callsign – used for cluster login
    @AppStorage("settings.callsign") private var callsign: String = "UB3ARM"
    
    /// Currently selected cluster hostname
    @AppStorage(ClusterStorageKeys.selectedClusterHost) private var selectedClusterHost: String = "k1ttt.net"
    @AppStorage(ClusterStorageKeys.selectionEventToken) private var clusterSelectionEventToken: Int = 0
    
    /// JSON-encoded dictionary of custom ports per host
    @AppStorage(ClusterStorageKeys.clusterPortsByHost) private var clusterPortsData: Data = Data()

    /// JSON-encoded custom clusters
    @AppStorage(ClusterStorageKeys.customClusters) private var customClustersData: Data = Data()

    /// JSON-encoded removed default cluster hosts
    @AppStorage(ClusterStorageKeys.removedDefaultHosts) private var removedDefaultHostsData: Data = Data()
    
    // MARK: - Local State
    
    /// Currently active tab (0 = DX Cluster, 1 = Propagation, 2 = Caledar, 3 = Settings)
    @State private var selectedTab: Int = 0
    @State private var clusterSessionKey: String = ""
    @State private var mainViewResetID: UUID = UUID()
    
    // MARK: - ViewModels
    
    /// ViewModel for the DX Cluster tab – recreated when host/port/callsign changes
    @State private var clusterVM: DXClusterTabViewModel = DXClusterTabViewModel(host: "dxc.w1nr.net", port: 7300, callsign: "NOCALL")
    
    /// Shared statistics ViewModel – receives spots from the cluster and maintains rolling-window leaderboards
    @StateObject private var statsVM = DXStatViewModel()
    
    // MARK: - Port Resolution
    
    private var normalizedSelectedClusterHost: String {
        DXClusterConfigurationRepository.normalizedHost(selectedClusterHost)
    }

    private var effectiveCallsign: String {
        let normalized = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? "NOCALL" : normalized
    }

    private var currentSessionKey: String {
        "\(normalizedSelectedClusterHost):\(currentPort):\(effectiveCallsign)"
    }
    
    /// Current effective port for the selected cluster
    private var currentPort: Int {
        let map = DXClusterConfigurationRepository.decodePorts(
            from: clusterPortsData,
            availableClusters: availableClusters
        )
        return map[normalizedSelectedClusterHost]
            ?? DXClusterConfigurationRepository.defaultPort(
                for: normalizedSelectedClusterHost,
                availableClusters: availableClusters
            )
    }

    private var shouldShowGlobalOverlays: Bool {
        selectedTab < 3
    }
    
    var body: some View {
        ZStack {
            // MARK: - TabView (main navigation)
            TabView(selection: $selectedTab) {
                // MARK: DX Cluster Tab
                NavigationStack {
                    VStack {
                        DXClusterTabView(vm: clusterVM)
                    }
                }
                .tabItem {
                    Image(systemName: "radio")
                    Text("DX Cluster")
                }
                .tag(0)
                
                // MARK: Propagation Tab
                NavigationStack {
                    PropagationTabView()
                }
                .tabItem {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Propagation")
                }
                .tag(1)
                
                // MARK: Contest Tab
                NavigationStack {
                    ContestsTabView()
                }
                .tabItem {
                    Image(systemName: "figure.fishing")
                    Text("Contests")
                }
                .tag(2)
                
                // MARK: Settings Tab
                NavigationStack {
                    SettingsTabView()
                }
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(3)
            }
            
            // MARK: - Global Overlays
            
            if shouldShowGlobalOverlays {
                // Real-time UTC/Local clock (top-right, non-interactive)
                ClockView()
                    .padding(.trailing, 12)
                    .padding(.top, 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
                
                // Live top-bands / top-countries stats + current cluster name (top-left)
                DXStatView(
                    vm: statsVM,
                    currentClusterName: currentClusterName,
                    selectedClusterHost: selectedClusterHost
                )
                .allowsHitTesting(false)
            }
        }
        .id(mainViewResetID)
        // Reset statistics when the app/window first appears
        .onAppear {
            statsVM.reset()
            _ = refreshClusterSession(forceReconnect: true)
        }
        // Reset stats whenever cluster, port, or callsign changes (new session feel)
        .onChange(of: selectedClusterHost) { _, _ in
            let didRefresh = refreshClusterSession()
            mainViewResetID = UUID()
            if didRefresh {
                statsVM.reset()
            }
        }
        .onChange(of: clusterPortsData) { _, _ in
            if refreshClusterSession() {
                statsVM.reset()
            }
        }
        .onChange(of: callsign) { _, _ in
            if refreshClusterSession() {
                statsVM.reset()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 0, !clusterVM.isConnected {
                _ = refreshClusterSession(forceReconnect: true)
            }
        }
        .onChange(of: clusterSelectionEventToken) { _, _ in
            mainViewResetID = UUID()
        }
        .onDisappear {
            clusterVM.disconnect()
            clusterSessionKey = ""
        }
    }
    
    // MARK: - Cluster Name Resolution
    
    /// Friendly name for the currently selected cluster (e.g., "W1NR")
    private var currentClusterName: String {
        if let endpoint = availableClusters.first(where: {
            $0.host.lowercased() == normalizedSelectedClusterHost
        }) {
            return endpoint.name
        }
        return selectedClusterHost // fallback to raw host
    }

    /// Merged default + custom list, unique by host.
    /// If a custom and default share the same host, custom entry wins.
    private var availableClusters: [ClusterEndpoint] {
        DXClusterConfigurationRepository.availableClusters(
            customClustersData: customClustersData,
            removedDefaultHostsData: removedDefaultHostsData
        )
    }

    // MARK: - Connection Lifecycle

    @discardableResult
    private func refreshClusterSession(forceReconnect: Bool = false) -> Bool {
        guard forceReconnect || clusterSessionKey != currentSessionKey else {
            return false
        }

        clusterVM.disconnect()
        clusterVM = DXClusterTabViewModel(
            host: normalizedSelectedClusterHost,
            port: currentPort,
            callsign: effectiveCallsign
        )
        clusterVM.onNewSpots = { spots in
            statsVM.ingest(spots: spots)
        }
        clusterVM.connect()
        clusterSessionKey = currentSessionKey
        return true
    }
}

// MARK: - Preview

#Preview {
    MainWindow()
}
