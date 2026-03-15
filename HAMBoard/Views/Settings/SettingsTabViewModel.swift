//
//  SettingsTabViewModel.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 18/11/2025.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SettingsTabViewModel: ObservableObject {

    // MARK: - Constants

    let availableBands: [String] = ["All", "160m", "80m", "60m", "40m", "30m", "20m", "15m", "10m"]
    let availableRefreshMinutes: [Int] = [1, 2, 5, 10, 15, 20, 25, 30]

    // MARK: - AppStorage keys

    private enum Keys {
        static let callsign = "settings.callsign"
        static let disableScreensaver = "settings.display.disableScreensaver"
    }
    
    // MARK: - DX Cluster Editor and Other States

    @Published var editName: String = ""
    @Published var editHost: String = ""
    @Published var editPort: Int = 7300
    @Published var editErrorText: String? = nil

    /// When non-nil, we are editing an existing cluster.
    @Published var editOriginalHost: String? = nil

    var canSaveEditedCluster: Bool {
        let h = DXClusterConfigurationRepository.normalizedHost(editHost)
        return !h.isEmpty && (1...65535).contains(editPort)
    }
    
    @Published var qrDXClusterURLImage: UIImage?
    @Published private(set) var isLoadingQRCode = false

    // MARK: - Stored settings via AppStorage

    @AppStorage(Keys.callsign) var callsign: String = "UB3ARM"
    @AppStorage(ClusterStorageKeys.selectedClusterHost) var selectedClusterHost: String = "k1ttt.net"
    @AppStorage(ClusterStorageKeys.selectionEventToken) var selectionEventToken: Int = 0
    @AppStorage(ClusterStorageKeys.clusterPortsByHost) private var clusterPortsData: Data = Data()
    @AppStorage(ClusterStorageKeys.customClusters) private var customClustersData: Data = Data()
    @AppStorage(ClusterStorageKeys.removedDefaultHosts) private var removedDefaultHostsData: Data = Data()
    @AppStorage(Keys.disableScreensaver) var disableScreensaver: Bool = true

    // MARK: - Clusters (merged: defaults + custom)

    /// Decoded custom clusters, sorted by name.
    var customClusters: [ClusterEndpoint] {
        decodeCustomClusters().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// All clusters (defaults + custom), unique by host, sorted by name.
    /// If a custom and default share the same host, custom entry wins.
    var availableClusters: [ClusterEndpoint] {
        DXClusterConfigurationRepository.availableClusters(
            customClustersData: customClustersData,
            removedDefaultHostsData: removedDefaultHostsData
        )
    }

    // MARK: - Custom clusters persistence

    private func decodeCustomClusters() -> [ClusterEndpoint] {
        DXClusterConfigurationRepository.decodeCustomClusters(from: customClustersData)
    }

    private func encodeCustomClusters(_ clusters: [ClusterEndpoint]) {
        if let data = DXClusterConfigurationRepository.encodeCustomClusters(clusters) {
            customClustersData = data
        } else {
            customClustersData = Data()
        }
    }

    private func decodeRemovedDefaultHosts() -> Set<String> {
        DXClusterConfigurationRepository.decodeRemovedDefaultHosts(from: removedDefaultHostsData)
    }

    private func encodeRemovedDefaultHosts(_ hosts: Set<String>) {
        if let data = DXClusterConfigurationRepository.encodeRemovedDefaultHosts(hosts) {
            removedDefaultHostsData = data
        } else {
            removedDefaultHostsData = Data()
        }
    }

    // MARK: - Custom DX Clusters
    
    func addCustomCluster(name: String, host: String, port: Int) -> String? {
        let normalizedHost = DXClusterConfigurationRepository.normalizedHost(host)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedHost.isEmpty else { return "Host is empty." }
        guard port >= 1 && port <= 65535 else { return "Port must be 1…65535." }

        // Reject duplicates (default or custom)
        let existingHosts = Set(availableClusters.map { DXClusterConfigurationRepository.normalizedHost($0.host) })
        if existingHosts.contains(normalizedHost) {
            return "This host already exists."
        }

        var customs = decodeCustomClusters()
        customs.append(ClusterEndpoint(
            name: cleanName.isEmpty ? normalizedHost : cleanName,
            host: normalizedHost,
            defaultPort: port
        ))
        encodeCustomClusters(customs)

        // Ensure ports map has the port for new host
        var ports = decodePorts()
        ports[normalizedHost] = port
        encodePorts(ports)

        // Auto-select the newly added cluster
        selectedClusterHost = normalizedHost

        objectWillChange.send()
        return nil
    }
    
    func saveEditedCluster() {
        editErrorText = nil

        let finalHost = DXClusterConfigurationRepository.normalizedHost(editHost)
        let finalNameRaw = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = finalNameRaw.isEmpty ? finalHost : finalNameRaw

        guard !finalHost.isEmpty else { editErrorText = "Host is empty."; return }
        guard (1...65535).contains(editPort) else { editErrorText = "Port must be 1…65535."; return }

        // CASE A: Editing existing cluster
        if let original = editOriginalHost.map(DXClusterConfigurationRepository.normalizedHost) {
            // Validate duplicates if host changed
            if finalHost != original {
                let existingHosts = Set(availableClusters.map { DXClusterConfigurationRepository.normalizedHost($0.host) })
                if existingHosts.contains(finalHost) {
                    editErrorText = "This host already exists."
                    return
                }
            }

            // Upsert edited cluster into custom list so it can override default by host.
            var customs = decodeCustomClusters()
            customs.removeAll { DXClusterConfigurationRepository.normalizedHost($0.host) == original }
            customs.removeAll { DXClusterConfigurationRepository.normalizedHost($0.host) == finalHost }
            customs.append(ClusterEndpoint(name: finalName, host: finalHost, defaultPort: editPort))
            encodeCustomClusters(customs)

            // Move port mapping when host changes.
            var ports = decodePorts()
            ports.removeValue(forKey: original)
            ports[finalHost] = editPort
            encodePorts(ports)

            // Keep editor state consistent.
            selectedClusterHost = finalHost
            editOriginalHost = finalHost
            editHost = finalHost
            editName = finalName

            objectWillChange.send()
            return
        }

        // CASE B: Creating new cluster (same as your addCustomCluster)
        if let err = addCustomCluster(name: finalName, host: finalHost, port: editPort) {
            editErrorText = err
            return
        }

        // Stay in editor after adding: treat as editing this newly created cluster
        beginEditCluster(host: finalHost)
    }

    func removeCluster(host: String) {
        let normalizedHost = DXClusterConfigurationRepository.normalizedHost(host)

        var customs = decodeCustomClusters()
        customs.removeAll { DXClusterConfigurationRepository.normalizedHost($0.host) == normalizedHost }
        encodeCustomClusters(customs)

        let defaultHosts = DXClusterConfigurationRepository.defaultHostSet
        var removedDefaults = decodeRemovedDefaultHosts()
        if defaultHosts.contains(normalizedHost) {
            removedDefaults.insert(normalizedHost)
        }
        encodeRemovedDefaultHosts(removedDefaults)

        // If removed cluster was selected -> pick first valid
        let knownHosts = Set(availableClusters.map { DXClusterConfigurationRepository.normalizedHost($0.host) })
        if !knownHosts.contains(DXClusterConfigurationRepository.normalizedHost(selectedClusterHost)) {
            selectedClusterHost = availableClusters.first?.host ?? selectedClusterHost
        }

        // Prune ports map (keep only known hosts)
        var ports = decodePorts()
        ports = ports.filter { knownHosts.contains(DXClusterConfigurationRepository.normalizedHost($0.key)) }
        encodePorts(ports)

        objectWillChange.send()
    }

    func removeEditedCluster() {
        let hostToRemove = editOriginalHost.map(DXClusterConfigurationRepository.normalizedHost)
            ?? DXClusterConfigurationRepository.normalizedHost(selectedClusterHost)
        removeCluster(host: hostToRemove)
        beginEditSelectedCluster()
    }
    
    func isCustomCluster(_ host: String) -> Bool {
        let h = DXClusterConfigurationRepository.normalizedHost(host)
        return decodeCustomClusters().contains { DXClusterConfigurationRepository.normalizedHost($0.host) == h }
    }

    // MARK: - Ports mapping

    private func decodePorts() -> [String: Int] {
        DXClusterConfigurationRepository.decodePorts(
            from: clusterPortsData,
            availableClusters: availableClusters
        )
    }

    private func encodePorts(_ dict: [String: Int]) {
        if let data = DXClusterConfigurationRepository.encodePorts(dict, availableClusters: availableClusters) {
            if data != clusterPortsData {
                clusterPortsData = data
            }
        }
    }

    /// Port for any host (for UI list)
    func portForHost(_ host: String) -> Int {
        let normalizedHost = DXClusterConfigurationRepository.normalizedHost(host)
        let map = decodePorts()
        return map[normalizedHost]
            ?? DXClusterConfigurationRepository.defaultPort(
                for: normalizedHost,
                availableClusters: availableClusters
            )
    }

    // MARK: - Port binding for currently selected host

    var currentPort: Int {
        get {
            let normalizedHost = DXClusterConfigurationRepository.normalizedHost(selectedClusterHost)
            let map = decodePorts()
            return map[normalizedHost]
                ?? DXClusterConfigurationRepository.defaultPort(
                    for: normalizedHost,
                    availableClusters: availableClusters
                )
        }
        set {
            let normalizedHost = DXClusterConfigurationRepository.normalizedHost(selectedClusterHost)
            var map = decodePorts()
            map[normalizedHost] = newValue
            encodePorts(map)
            objectWillChange.send()
        }
    }

    // MARK: - Helpers

    func ensureDefaults() {
        let knownHosts = Set(availableClusters.map { DXClusterConfigurationRepository.normalizedHost($0.host) })
        let normalizedSelectedHost = DXClusterConfigurationRepository.normalizedHost(selectedClusterHost)

        // Validate selected host
        if !knownHosts.contains(normalizedSelectedHost) {
            selectedClusterHost = availableClusters.first?.host ?? selectedClusterHost
        } else if selectedClusterHost != normalizedSelectedHost {
            selectedClusterHost = normalizedSelectedHost
        }

        // Normalize persisted ports and backfill defaults for all known hosts.
        encodePorts(decodePorts())
    }

    func selectClusterFromGeneralPicker(_ host: String) {
        selectedClusterHost = DXClusterConfigurationRepository.normalizedHost(host)
        selectionEventToken &+= 1
    }
    
    func beginNewCluster() {
        editErrorText = nil
        editOriginalHost = nil
        editName = ""
        editHost = ""
        editPort = 7300
    }

    func beginEditSelectedCluster() {
        beginEditCluster(host: selectedClusterHost)
    }

    func beginEditCluster(host: String) {
        editErrorText = nil
        let normalized = DXClusterConfigurationRepository.normalizedHost(host)
        editOriginalHost = normalized

        if let c = availableClusters.first(where: {
            DXClusterConfigurationRepository.normalizedHost($0.host) == normalized
        }) {
            editName = c.name
            editHost = c.host
            editPort = portForHost(c.host)
        } else {
            // fallback
            editName = normalized
            editHost = normalized
            editPort = portForHost(normalized)
        }
    }

    func ensureDXClusterQRCode() {
        guard qrDXClusterURLImage == nil, !isLoadingQRCode else {
            return
        }
        isLoadingQRCode = true

        Task { [weak self] in
            guard let self else {
                return
            }

            let image = await QRCodeCache.shared.image(for: .dxClusterURL)
            self.qrDXClusterURLImage = image
            self.isLoadingQRCode = false
        }
    }
}
