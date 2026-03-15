//
//  ClusterConfigurationRepository.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 24/02/2026.
//

import SwiftUI
import Foundation

enum ClusterStorageKeys {
    static let selectedClusterHost = "settings.cluster.host"
    static let clusterPortsByHost = "settings.cluster.portsByHost"
    static let customClusters = "settings.cluster.customClusters"
    static let removedDefaultHosts = "settings.cluster.removedDefaultHosts"
    static let selectionEventToken = "settings.cluster.selectionEventToken"
}

/// Represents a DX Cluster endpoint with a friendly display name.
struct ClusterEndpoint: Identifiable, Hashable, Codable {
    var id: String { host }
    let name: String
    let host: String
    let defaultPort: Int
}

enum DXClusterConfigurationRepository {

    // MARK: - Defaults

    static let fallbackPort: Int = 7300
    
    static let defaultClusters: [ClusterEndpoint] = [
        ClusterEndpoint(name: "W1NR", host: "dxc.w1nr.net", defaultPort: 7300),
        ClusterEndpoint(name: "K1TTT", host: "k1ttt.net", defaultPort: 7373),
        ClusterEndpoint(name: "W3LPL", host: "w3lpl.net", defaultPort: 7373),
        ClusterEndpoint(name: "W4MYA", host: "dxc.w4mya.us", defaultPort: 7373),
        ClusterEndpoint(name: "UA0APV", host: "ua0apv.i234.me", defaultPort: 7300),
        ClusterEndpoint(name: "EA4URE", host: "ea4ure.com", defaultPort: 7300),
        ClusterEndpoint(name: "G6NHU", host: "dxspider.co.uk", defaultPort: 7300),
        ClusterEndpoint(name: "VE6DXC", host: "dx.middlebrook.ca", defaultPort: 8000),
        ClusterEndpoint(name: "S50CLX", host: "s50clx.infrax.si", defaultPort: 41112),
        ClusterEndpoint(name: "N7OD", host: "n7od.pentux.net", defaultPort: 7300),
    ]

    static let defaultHostSet: Set<String> = Set(defaultClusters.map { normalizedHost($0.host) })

    // MARK: - Host Normalization

    static func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Cluster Lists

    static func availableClusters(customClustersData: Data, removedDefaultHostsData: Data) -> [ClusterEndpoint] {
        let removedDefaults = decodeRemovedDefaultHosts(from: removedDefaultHostsData)
        let filteredDefaults = defaultClusters.filter { !removedDefaults.contains(normalizedHost($0.host)) }
        let merged = decodeCustomClusters(from: customClustersData) + filteredDefaults
        var uniqueHosts = Set<String>()
        var uniqueClusters: [ClusterEndpoint] = []

        for cluster in merged {
            let normalized = normalizedHost(cluster.host)
            if uniqueHosts.insert(normalized).inserted {
                uniqueClusters.append(
                    ClusterEndpoint(
                        name: cluster.name,
                        host: normalized,
                        defaultPort: cluster.defaultPort
                    )
                )
            }
        }

        return uniqueClusters.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func decodeCustomClusters(from data: Data) -> [ClusterEndpoint] {
        guard !data.isEmpty else { return [] }
        do {
            let decoded = try JSONDecoder().decode([ClusterEndpoint].self, from: data)
            return decoded.map {
                ClusterEndpoint(
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    host: normalizedHost($0.host),
                    defaultPort: $0.defaultPort
                )
            }
        } catch {
            return []
        }
    }

    static func encodeCustomClusters(_ clusters: [ClusterEndpoint]) -> Data? {
        let normalized = clusters.map {
            ClusterEndpoint(
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                host: normalizedHost($0.host),
                defaultPort: $0.defaultPort
            )
        }
        return try? JSONEncoder().encode(normalized)
    }

    static func decodeRemovedDefaultHosts(from data: Data) -> Set<String> {
        guard !data.isEmpty else { return [] }
        do {
            let decoded = try JSONDecoder().decode([String].self, from: data)
            return Set(decoded.map(normalizedHost))
        } catch {
            return []
        }
    }

    static func encodeRemovedDefaultHosts(_ hosts: Set<String>) -> Data? {
        let normalizedHosts = Array(Set(hosts.map(normalizedHost))).sorted()
        return try? JSONEncoder().encode(normalizedHosts)
    }

    // MARK: - Ports

    static func defaultPort(for host: String, availableClusters: [ClusterEndpoint]) -> Int {
        let normalized = normalizedHost(host)
        return availableClusters.first(where: { normalizedHost($0.host) == normalized })?.defaultPort ?? fallbackPort
    }

    static func decodePorts(from data: Data, availableClusters: [ClusterEndpoint]) -> [String: Int] {
        let base = basePorts(for: availableClusters)
        guard !data.isEmpty else { return base }

        do {
            let decoded = try JSONDecoder().decode([String: Int].self, from: data)
            var merged = base
            for (host, port) in decoded {
                let normalized = normalizedHost(host)
                guard base[normalized] != nil, (1...65535).contains(port) else { continue }
                merged[normalized] = port
            }
            return merged
        } catch {
            return base
        }
    }

    static func encodePorts(_ ports: [String: Int], availableClusters: [ClusterEndpoint]) -> Data? {
        let knownHosts = Set(availableClusters.map { normalizedHost($0.host) })
        var filtered: [String: Int] = [:]

        for (host, port) in ports {
            let normalized = normalizedHost(host)
            guard knownHosts.contains(normalized), (1...65535).contains(port) else { continue }
            filtered[normalized] = port
        }

        return try? JSONEncoder().encode(filtered)
    }

    // MARK: - Helpers

    private static func basePorts(for availableClusters: [ClusterEndpoint]) -> [String: Int] {
        var map: [String: Int] = [:]
        for cluster in availableClusters {
            map[normalizedHost(cluster.host)] = cluster.defaultPort
        }
        return map
    }
}
