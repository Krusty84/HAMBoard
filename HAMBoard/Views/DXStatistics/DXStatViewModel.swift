//
//  DXClusterStatsService.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 24/11/2025.
//

import Foundation
import Combine

// MARK: - ViewModel (MainActor-bound, publishes UI state)

/// ViewModel responsible for exposing real-time DX cluster statistics to SwiftUI views.
/// All published properties are updated on the main actor.
@MainActor
final class DXStatViewModel: ObservableObject {
    
    @Published var topBands: [TopItem] = []
    @Published var topCountries: [TopItem] = []
    
    private let actor = DXStatStatActor()
    /// Max stat value for countries and bands
    var maxItems: Int = 4
    
    /// Resets the statistics both in the actor and in the published UI state.
    func reset() {
        Task { await actor.reset() }
        topBands = []
        topCountries = []
    }
    
    /// Processes a batch of incoming spots and updates the published top lists.
    /// Computation is offloaded to a background task to avoid blocking the UI.
    func ingest(spots: [Spot]) {
        guard !spots.isEmpty else { return }
        
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.actor.ingest(spots: spots)
            
            let bands = await self.actor.snapshotTopBands(limit: self.maxItems)
            let countries = await self.actor.snapshotTopCountries(limit: self.maxItems)
            
            self.topBands = bands
            self.topCountries = countries
        }
    }
    
    /// Convenience method for ingesting a single spot.
    func ingestSingle(_ spot: Spot) {
        ingest(spots: [spot])
    }
}

// MARK: - Public Model for UI Layer

/// Represents a single item in the "Top Bands" or "Top Countries" leaderboard displayed in the UI.
public struct TopItem: Identifiable, Hashable, Sendable {
    public let label: String      // e.g., "20m" or "JA"
    public let count: Int         // number of spots in the current time window
    
    public var id: String { label }
}

// MARK: - Rolling Window Statistics Collector (Actor-Isolated)

/// An actor that maintains real-time statistics over a sliding time window (default: 5 minutes).
/// It tracks the most active bands and DXCC countries from incoming cluster spots,
/// automatically expiring old data and keeping counters up-to-date.
/// Designed for high-throughput ingestion while remaining thread-safe.
actor DXStatStatActor {
    
    // Current aggregated counters (updated in real time)
    private var bandCounts: [String: Int] = [:]
    private var countryCounts: [String: Int] = [:]
    
    // Circular buffer entry storing timestamp and associated keys
    private struct Entry {
        let time: Date
        let band: String
        let countryKey: String
    }
    
    // Fixed-size deque simulation for O(1) removal of oldest entries
    private var queue: [Entry] = []
    private var head: Int = 0
    
    // Time window configuration
    private let window: TimeInterval         // duration of the rolling window in seconds
    private let cleanupInterval: TimeInterval // how often the background cleanup task runs
    private var cleanupTask: Task<Void, Never>?
    
    /// Initializes the statistics collector with custom window and cleanup intervals.
    /// - Parameters:
    ///   - window: Length of the rolling window in seconds (default: 300 = 5 minutes)
    ///   - cleanupInterval: How often to run background cleanup (default: 30 seconds)
    init(window: TimeInterval = 300, cleanupInterval: TimeInterval = 30) {
        self.window = window
        self.cleanupInterval = cleanupInterval
        Task { [weak self] in
            await self?.startCleanupLoopIfNeeded()
        }
    }
    
    deinit {
        cleanupTask?.cancel()
    }
    
    // MARK: - Public API
    
    /// Resets all statistics and clears the internal buffer.
    func reset() {
        bandCounts.removeAll()
        countryCounts.removeAll()
        queue.removeAll()
        head = 0
    }
    
    /// Ingests an array of new cluster spots and updates the rolling statistics.
    /// Old entries outside the time window are removed during this call.
    /// - Parameter spots: Array of `Spot` objects received from the DX cluster
    func ingest(spots: [Spot]) {
        guard !spots.isEmpty else { return }
        let now = Date()
        cleanup(now: now)
        
        for spot in spots {
            let bandKey = spot.band
            let countryKey = spot.dxCountryKey
            
            let entry = Entry(time: now, band: bandKey, countryKey: countryKey)
            queue.append(entry)
            
            bandCounts[bandKey, default: 0] += 1
            countryCounts[countryKey, default: 0] += 1
        }
    }
    
    /// Returns the current top bands sorted by activity within the rolling window.
    /// - Parameter limit: Maximum number of items to return
    /// - Returns: Array of `TopItem` sorted by count (descending), then alphabetically
    func snapshotTopBands(limit: Int) -> [TopItem] {
        cleanup(now: Date())
        return bandCounts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map { TopItem(label: $0.key, count: $0.value) }
    }
    
    /// Returns the current top DXCC countries/entities sorted by activity.
    /// - Parameter limit: Maximum number of items to return
    /// - Returns: Array of `TopItem` sorted by count (descending), then alphabetically
    func snapshotTopCountries(limit: Int) -> [TopItem] {
        cleanup(now: Date())
        return countryCounts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map { TopItem(label: $0.key, count: $0.value) }
    }
    
    // MARK: - Private Implementation
    
    /// Starts a background task that periodically removes expired entries.
    private func startCleanupLoopIfNeeded() {
        guard cleanupTask == nil || cleanupTask?.isCancelled == true else {
            return
        }

        let interval = cleanupInterval
        cleanupTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self else {
                    break
                }
                await self.cleanup(now: Date())
            }
        }
    }
    
    /// Removes all entries older than the configured time window and updates counters accordingly.
    /// Also compacts the internal array periodically to prevent unbounded memory growth.
    private func cleanup(now: Date) {
        // Evict expired entries from the head of the queue
        while head < queue.count, now.timeIntervalSince(queue[head].time) > window {
            let old = queue[head]
            
            if let count = bandCounts[old.band], count > 1 {
                bandCounts[old.band] = count - 1
            } else {
                bandCounts.removeValue(forKey: old.band)
            }
            
            if let count = countryCounts[old.countryKey], count > 1 {
                countryCounts[old.countryKey] = count - 1
            } else {
                countryCounts.removeValue(forKey: old.countryKey)
            }
            
            head += 1
        }
        
        // Compact the array when a significant portion has been removed
        if head > 1024 && head > queue.count / 2 {
            queue.removeFirst(head)
            head = 0
        }
    }
}
