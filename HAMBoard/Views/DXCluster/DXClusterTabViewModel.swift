//
//  DXClusterTabViewModel.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 18/11/2025.
//

import Foundation
import Combine

/// ViewModel responsible for managing the live Telnet connection to a DX cluster,
/// parsing incoming spots in real time, applying UI filters, and exposing data for SwiftUI views.
///
/// Thread-safe, uses `DXClusterTelnetConnector` for TCP streaming, and integrates with
/// `ClusterParser`, `DXCCDatabase`, and `CountryMapper` for full spot resolution.
///
/// Responsibilities split:
/// - Connector handles transport/TELNET handshake details.
/// - ViewModel translates connector events to UI-friendly state and bounded collections.
@MainActor
final class DXClusterTabViewModel: ObservableObject {
    
    // MARK: - Published UI State
    
    /// All received spots in chronological order (newest first)
    @Published var spots: [Spot] = []

    /// WWV and cluster comment lines shown in the announcements tab (newest first)
    @Published var announcements: [String] = []

    /// Current connection status string shown in the UI
    @Published var connectionStatus = "Disconnected"
    
    /// True when TCP connection is established and ready
    @Published var isConnected = false
    
    /// True while waiting for the first message (shows loading overlay)
    @Published var isLoading = true
    
    // MARK: - Filters
    
    /// Currently selected band filter (All Bands, 20m, etc.)
    @Published var selectedBand: BandFilter = .all
    
    // MARK: - Callbacks
    
    /// Optional closure called immediately when new spots are parsed.
    /// Used to feed real-time statistics engine with zero delay.
    var onNewSpots: (([Spot]) -> Void)?
    
    /// Selected cluster host (normalized), shown in the announcements dashboard.
    let clusterHost: String
    let clusterPort: Int
    let clusterCallsign: String
    
    // MARK: - Configuration

    private let connector: DXClusterTelnetConnector
    private let maxAnnouncementLines = 300
    private let announcementsPollingCycleNanoseconds: UInt64 = 90_000_000_000
    private let commandVariantPauseNanoseconds: UInt64 = 220_000_000

    // MARK: - Connection State

    private var firstMessageReceived = false
    private var servicePollingTask: Task<Void, Never>?

    // MARK: - Derived State

    /// Filtered spot list based on current band selection
    var filteredSpots: [Spot] {
        spots.filter { spot in
            selectedBand.matches(spot.band)
        }
    }

    var announcementsFeed: [String] {
        announcements
    }

    // MARK: - Initialization
    
    /// Creates a new ViewModel instance configured for a specific cluster node.
    ///
    /// - Parameters:
    ///   - host: Cluster hostname (e.g. "dxfun.com", "k1ttt.net")
    ///   - port: Telnet port (usually 7000–8000 range)
    ///   - callsign: Your callsign – used for login
    init(host: String, port: Int, callsign: String) {
        let normalizedHost = DXClusterConfigurationRepository.normalizedHost(host)
        let normalizedCallsign = callsign
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        
        self.clusterHost = normalizedHost
        self.clusterPort = port
        self.clusterCallsign = normalizedCallsign.isEmpty ? "NOCALL" : normalizedCallsign
        self.connector = DXClusterTelnetConnector(
            host: clusterHost,
            port: clusterPort,
            callsign: clusterCallsign
        )
        
        connector.onEvent = { [weak self] event in
            self?.handleConnectorEvent(event)
        }
    }
    
    // MARK: - Public API
    
    /// Establishes connection to the DX cluster and begins receiving data.
    func connect() {
        // Fresh session semantics:
        // clear previous feed and wait for first live activity.
        stopServicePolling()
        isConnected = false
        isLoading = true
        firstMessageReceived = false
        spots.removeAll()
        announcements.removeAll()
        connectionStatus = "Connecting to cluster..."
        connector.connect()
    }
    
    /// Gracefully disconnects from the cluster and cleans up resources.
    func disconnect() {
        stopServicePolling()
        connector.disconnect()
        isConnected = false
        isLoading = false
        connectionStatus = "Disconnected"
    }

    /// Allows upper layers/debug tooling to send cluster commands through active session.
    func sendClusterCommand(_ command: String) {
        connector.sendCommand(command)
    }

    func requestAnnouncements() {
        Task { [weak self] in
            await self?.requestAnnouncementsNow()
        }
    }

    // MARK: - Connector Events

    private func handleConnectorEvent(_ event: DXClusterTelnetConnector.Event) {
        switch event {
        case .connecting(let host, let port):
            connectionStatus = "Connecting to \(host):\(port)..."
        case .connected(let callsign):
            isConnected = true
            // TCP ready does not always mean fully authenticated at cluster level yet.
            connectionStatus = "TCP connected. Logging in as \(callsign)..."
        case .message(let message):
            handleMessage(message)
        case .failed(let description):
            stopServicePolling()
            isConnected = false
            isLoading = false
            connectionStatus = "Connection error: \(description)"
        case .disconnectedByRemote:
            stopServicePolling()
            isConnected = false
            isLoading = false
            connectionStatus = "Disconnected by remote host"
        case .disconnected:
            stopServicePolling()
            isConnected = false
            isLoading = false
            connectionStatus = "Disconnected"
        }
    }

    private func handleMessage(_ message: ClusterMessage) {
        switch message {
        case .spot(let spot):
            onNewSpots?([spot])
            markActivityReceived()
            spots.insert(spot, at: 0)
            if spots.count > 200 {
                spots.removeLast(50)
            }
        case .wwv(let text), .comment(let text):
            // Announcements feed aggregates informational lines from cluster output.
            markActivityReceived()
            appendAnnouncement(text)
        case .unknown(let text):
            // Unknown lines still count as activity to unblock loading state.
            markActivityReceived()
            appendAnnouncement(text)
        }
    }

    // MARK: - Helpers

    /// Marks first activity to remove the initial loading state.
    private func markActivityReceived() {
        if !firstMessageReceived {
            firstMessageReceived = true
            isLoading = false
            startServicePollingIfNeeded()
        }
    }

    private func appendAnnouncement(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        announcements.insert(trimmed, at: 0)
        if announcements.count > maxAnnouncementLines {
            announcements.removeLast(announcements.count - maxAnnouncementLines)
        }
    }

    private func requestAnnouncementsNow() async {
        await sendClusterCommands(["SH/ANN 10", "SHOW/ANN 10"])
    }

    private func startServicePollingIfNeeded() {
        guard servicePollingTask == nil, isConnected else {
            return
        }

        servicePollingTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.runServicePollingLoop()
        }
    }

    private func stopServicePolling() {
        servicePollingTask?.cancel()
        servicePollingTask = nil
    }

    private func runServicePollingLoop() async {
        while !Task.isCancelled {
            await requestAnnouncementsNow()
            await sleepIfNeeded(announcementsPollingCycleNanoseconds)
        }
    }

    private func sleepIfNeeded(_ nanoseconds: UInt64) async {
        guard nanoseconds > 0 else {
            return
        }

        do {
            try await Task.sleep(nanoseconds: nanoseconds)
        } catch {
            // Task cancelled during reconnect/disconnect, stop waiting immediately.
        }
    }

    private func sendClusterCommands(_ commands: [String]) async {
        guard isConnected else {
            return
        }

        let normalizedCommands = commands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedCommands.isEmpty else {
            return
        }

        for (index, command) in normalizedCommands.enumerated() {
            if Task.isCancelled {
                return
            }

            if index > 0 {
                await sleepIfNeeded(commandVariantPauseNanoseconds)
            }
            sendClusterCommand(command)
        }
    }
}
