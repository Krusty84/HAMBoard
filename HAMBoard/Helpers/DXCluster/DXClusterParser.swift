//
//  ClusterParser.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 18/11/2025.
//

import Foundation

/// A fully parsed DX cluster spot with resolved station information.
struct Spot: Identifiable, Hashable {
    private let spotID = UUID()

    let freq: Double          // Frequency in kHz (e.g. 14074.0)
    let dx: String            // DX callsign (de-entity)
    let spotter: String       // Spotter callsign
    let comment: String       // Free-text comment (often contains QSL info, grid, etc.)
    let timeZ: String          // Time in UTC, ending with "Z" (e.g. "1230Z")
    let dxCountryKey: String  // Stable country key for stats (ISO code or fallback text)
    
    let dxStation: Station    // Fully resolved DX entity (country, CQ zone, flag, etc.)
    let spotterStation: Station
    
    let band: String          // Human-readable band (e.g. "20m", "6m")
    let mode: String          // Inferred mode: "CW", "SSB", or "?"
    
    /// Stable identifier for SwiftUI lists and tables
    var id: UUID {
        spotID
    }

    static func == (lhs: Spot, rhs: Spot) -> Bool {
        lhs.spotID == rhs.spotID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(spotID)
    }
}

/// Represents different types of messages received from a DX cluster.
enum ClusterMessage {
    case spot(Spot)              // Regular DX spot
    case wwv(String)             // WWV/WCY solar-terrestrial report
    case comment(String)         // To ALL/LOCAL announcements
    case unknown(String)       // Anything else (login prompts, errors, etc.)
}

/// High-performance parser for classic DX cluster telnet protocol lines.
///
/// Supports the standard AR-Cluster/DXSpider format:
/// `DX de SP9XYZ:   14074.0  JA1ZLO       CW 23 dB  QSL via bureau   1230Z`
///
/// Thread-safe, zero-allocation where possible, used heavily in real-time feeds.
struct DXClusterParser {
    
    /// Parses a single line from the cluster and returns the appropriate message type.
    ///
    /// Classification strategy:
    /// 1. Fast prefix checks for known high-volume message families (`DX de`, `WWV`, `WCY`).
    /// 2. Announcement target checks for `To ... de ...` style messages used by multiple clusters.
    /// 3. Fallback to `.unknown` so upper layers can still observe activity safely.
    ///
    /// - Parameter line: Raw string as received from the telnet stream
    /// - Returns: Classified `ClusterMessage`
    static func parse(_ line: String) -> ClusterMessage {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix("DX de ") {
            return parseSpot(trimmed)
        }
        
        if trimmed.hasPrefix("WWV") || trimmed.hasPrefix("WCY") {
            return .wwv(trimmed)
        }
        let lowercased = trimmed.lowercased()
        // AR/CC style announcements are often "To TARGET de CALL: ...", not only "to all/local".
        if lowercased.hasPrefix("to all")
            || lowercased.hasPrefix("to local")
            || (lowercased.hasPrefix("to ") && lowercased.contains(" de ")) {
            return .comment(trimmed)
        }
        
        return .unknown(trimmed)
    }
    
    /// Parses a DX spot line into a fully populated `Spot` struct.
    ///
    /// Example input:
    /// `DX de G3XYZ:    14023.0  P5ABC        CW 15 dB  QSL via LOTW    0515Z`
    ///
    /// - Parameter line: Full line starting with "DX de "
    /// - Returns: `.spot` on success, `.unknown` on parsing failure
    private static func parseSpot(_ line: String) -> ClusterMessage {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return .unknown(line)
        }
        
        // Extract spotter callsign: everything between "DX de " and the colon
        let spotterStart = line.index(line.startIndex, offsetBy: 6)
        let spotter = String(line[spotterStart..<colonIndex])
            .trimmingCharacters(in: .whitespaces)
        
        // Everything after the colon
        let rest = String(line[line.index(after: colonIndex)...])
        let components = rest
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        // Minimal schema validation keeps parser resilient to malformed banner/error lines.
        guard components.count >= 3,
              let frequency = Double(components[0]) else {
            return .unknown(line)
        }
        
        let dxCall = components[1]
        
        // Time is the last numeric field ending with "Z" (e.g. "1230Z")
        let zuluTimeMatch = components.enumerated().reversed().first {
            normalizedZuluTimeToken($0.element) != nil
        }
        let timeIndex = zuluTimeMatch?.offset
        let timeZ = zuluTimeMatch.flatMap { normalizedZuluTimeToken($0.element) } ?? ""
        
        // Comment = everything between DX call and time (or end of line)
        let commentStartIndex = 2
        let commentEndIndex = max(commentStartIndex, timeIndex ?? components.count)
        
        let comment: String
        if commentStartIndex < commentEndIndex {
            comment = components[commentStartIndex..<commentEndIndex].joined(separator: " ")
        } else {
            comment = ""
        }
        
        let (band, mode) = bandAndMode(from: frequency)
        let dxStation = Station(call: dxCall)
        let spotterStation = Station(call: spotter)
        let countryKey = dxStation.countryCode?.uppercased()
            ?? dxStation.country?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Unknown"
        
        let spot = Spot(
            freq: frequency,
            dx: dxCall,
            spotter: spotter,
            comment: comment,
            timeZ: timeZ,
            dxCountryKey: countryKey,
            dxStation: dxStation,
            spotterStation: spotterStation,
            band: band,
            mode: mode
        )
        
        return .spot(spot)
    }
    
    /// Determines amateur radio band and likely mode from frequency in kHz.
    ///
    /// - Parameter freq: Frequency in kHz
    /// - Returns: Tuple with band label (e.g. "20m") and mode ("CW", "SSB", or "?")
    private static func bandAndMode(from freq: Double) -> (band: String, mode: String) {
        switch freq {
        case 1810..<2000:   return ("160m", freq < 1840 ? "CW" : "SSB")
        case 3500..<4000:   return ("80m",  freq < 3600 ? "CW" : "SSB")
        case 7000..<7300:   return ("40m",  freq < 7040 ? "CW" : "SSB")
        case 10100..<10150: return ("30m",  "CW")
        case 14000..<14350: return ("20m",  freq < 14070 ? "CW" : "SSB")
        case 18068..<18168: return ("17m",  freq < 18110 ? "CW" : "SSB")
        case 21000..<21450: return ("15m",  freq < 21070 ? "CW" : "SSB")
        case 24890..<24990: return ("12m",  freq < 24930 ? "CW" : "SSB")
        case 28000..<29700: return ("10m",  freq < 28300 ? "CW" : "SSB")
        case 50000..<54000: return ("6m",   "SSB")
        case 144000..<148000: return ("2m",   "SSB")
        default:
            let mhz = Int(freq / 1000)
            return ("\(mhz)k", "?")
        }
    }

    private static func isZuluTimeToken(_ token: String) -> Bool {
        guard token.hasSuffix("Z"), token.count > 1 else {
            return false
        }

        let numericPart = token.dropLast()
        return !numericPart.isEmpty && numericPart.allSatisfy(\.isNumber)
    }

    private static func normalizedZuluTimeToken(_ token: String) -> String? {
        // Control chars can leak through TELNET streams; strip before regex checks.
        let withoutControl = String(token.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if let explicitZulu = extractSuffixTime(from: withoutControl, pattern: #"\d{3,6}Z$"#),
           isZuluTimeToken(explicitZulu) {
            return explicitZulu
        }

        // Some nodes emit plain HHMM. Normalize to HHMMZ for uniform UI/statistics usage.
        if let plainTime = extractSuffixTime(from: withoutControl, pattern: #"\d{4}$"#),
           isValidHHMM(plainTime) {
            return plainTime + "Z"
        }

        return nil
    }

    private static func extractSuffixTime(from token: String, pattern: String) -> String? {
        guard let range = token.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(token[range])
    }

    private static func isValidHHMM(_ token: String) -> Bool {
        guard token.count == 4 else {
            return false
        }

        let hoursString = String(token.prefix(2))
        let minutesString = String(token.suffix(2))

        guard let hours = Int(hoursString), let minutes = Int(minutesString) else {
            return false
        }

        return (0..<24).contains(hours) && (0..<60).contains(minutes)
    }
}
