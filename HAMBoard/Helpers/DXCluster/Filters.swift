//
//  Filters.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 18/11/2025.
//

import Foundation

/// Filter options for selecting specific amateur radio bands in the spot list.
/// Used in SwiftUI pickers and segmented controls.
enum BandFilter: String, CaseIterable, Identifiable {
    case all = "All Bands"
    case m160 = "160m"
    case m80  = "80m"
    case m60  = "60m"
    case m40  = "40m"
    case m30  = "30m"
    case m20  = "20m"
    case m17  = "17m"
    case m15  = "15m"
    case m12  = "12m"
    case m10  = "10m"
    case m6   = "6m"
    
    var id: Self { self }
    
    /// Returns `true` if the given band string matches this filter.
    /// Case-insensitive and tolerant to variations like "160m", "1.8 MHz", "160".
    ///
    /// - Parameter band: Band label from a `Spot` (e.g. "20m", "6m")
    /// - Returns: `true` if the spot should be visible under this filter
    func matches(_ band: String) -> Bool {
        guard self != .all else { return true }
        return Self.resolvedFilter(from: band) == self
    }
    
    /// Localized title suitable for display in UI (already provided via rawValue)
    var title: String { rawValue }

    // MARK: - Helpers

    private static func resolvedFilter(from rawBand: String) -> BandFilter? {
        let normalized = rawBand
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")

        guard !normalized.isEmpty else {
            return nil
        }

        if let meters = metersValue(from: normalized) {
            return filter(forMeters: meters)
        }

        if let mhz = mhzValue(from: normalized) {
            return filter(forMHz: mhz)
        }

        if let khz = khzValue(from: normalized) {
            return filter(forMHz: khz / 1_000)
        }

        if let meters = Int(normalized) {
            return filter(forMeters: meters)
        }

        return nil
    }

    private static func metersValue(from normalized: String) -> Int? {
        guard normalized.hasSuffix("m") else {
            return nil
        }
        return Int(normalized.dropLast())
    }

    private static func mhzValue(from normalized: String) -> Double? {
        guard normalized.contains("mhz") else {
            return nil
        }
        let value = normalized.replacingOccurrences(of: "mhz", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(value)
    }

    private static func khzValue(from normalized: String) -> Double? {
        guard normalized.contains("khz") else {
            return nil
        }
        let value = normalized.replacingOccurrences(of: "khz", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(value)
    }

    private static func filter(forMeters meters: Int) -> BandFilter? {
        switch meters {
        case 160: return .m160
        case 80: return .m80
        case 60: return .m60
        case 40: return .m40
        case 30: return .m30
        case 20: return .m20
        case 17: return .m17
        case 15: return .m15
        case 12: return .m12
        case 10: return .m10
        case 6: return .m6
        default: return nil
        }
    }

    private static func filter(forMHz mhz: Double) -> BandFilter? {
        switch mhz {
        case 1.8..<2.0: return .m160
        case 3.5..<4.0: return .m80
        case 5.0..<5.5: return .m60
        case 7.0..<7.3: return .m40
        case 10.1..<10.15: return .m30
        case 14.0..<14.35: return .m20
        case 18.068..<18.168: return .m17
        case 21.0..<21.45: return .m15
        case 24.89..<24.99: return .m12
        case 28.0..<29.7: return .m10
        case 50.0..<54.0: return .m6
        default: return nil
        }
    }
}
