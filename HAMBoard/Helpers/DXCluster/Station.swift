//
//  Station.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 18/11/2025.
//

import Foundation

/// Represents a ham radio callsign with associated DXCC entity resolution.
///
/// The class parses a raw callsign, strips portable/maritime/mobile identifiers (e.g. /P, /MM, /QRP),
/// determines the longest matching DXCC prefix, and exposes country information,
/// CQ zone, continent, and ISO code via the shared `DXCCDatabase` and `CountryMapper`.
final class Station {
    
    // MARK: - Raw Input
    
    /// Original callsign exactly as received (uppercase, trimmed)
    let raw: String
    
    // MARK: - Resolved DXCC Data
    
    /// Whether a valid DXCC entity was successfully matched
    var valid = false
    
    /// Full DXCC entity name (e.g., "Fed. Rep. of Germany", "European Russia")
    var country: String?
    
    /// CQ Zone number (1–40)
    var cqz: Int?
    
    /// Continent abbreviation (EU, AS, NA, SA, AF, OC)
    var continent: String?
    
    /// ISO 3166-1 alpha-2 country code (e.g., "DE", "RU", "JP") — resolved via CountryMapper
    var iso3166: String? {
        CountryMapper.isoCode(for: country)
    }
    
    // MARK: - Internal
    
    /// The longest prefix of the callsign that matches a known DXCC entity
    private var prefix: String?
    
    // MARK: - Initialization
    
    /// Creates a station instance from a raw callsign string.
    ///
    /// - Parameter call: The callsign as received (e.g., "R1ABC/P", "MM0XYZ/MM", "W1AW")
    init(call: String) {
        raw = call.uppercased().trimmingCharacters(in: .whitespaces)
        
        // Extract base callsign by removing portable identifiers (/P, /MM, /A, etc.)
        let baseCall = raw
            .components(separatedBy: "/")
            .first(where: { !$0.isEmpty }) ?? raw
        
        // Find the longest prefix that matches a known DXCC entity
        prefix = Self.longestKnownPrefix(for: baseCall)
        
        // Resolve DXCC entity using the matched prefix
        if let prefix = prefix,
           let entity = DXCCDatabase.shared.entity(for: prefix) {
            country = entity.country
            cqz = entity.cqz
            continent = entity.continent
            valid = true
        }
    }
    
    // MARK: - Public UI Helpers
    
    /// Returns a clean, human-readable country name suitable for display.
    /// Example: "Germany", "Russia", "Canary Islands", "USA"
    var displayCountryName: String {
        CountryMapper.displayName(for: country)
    }
    
    /// Returns the ISO 3166-1 alpha-2 code for flag display and statistics.
    /// Falls back to `nil` if the country cannot be mapped.
    var countryCode: String? {
        CountryMapper.isoCode(for: country)
    }
    
    // MARK: - Prefix Matching Logic
    
    /// Returns the longest prefix of the callsign that corresponds to a known DXCC entity.
    ///
    /// This handles cases like:
    /// - VP8/GM3WIJ → "VP8" (South Shetland Is.)
    /// - TO5A → "TO" (French St. Martin)
    /// - 4U1A → "4U" (United Nations HQ)
    ///
    /// - Parameter call: Cleaned base callsign (without /suffixes)
    /// - Returns: Longest matching prefix, or `nil` if no match
    private static func longestKnownPrefix(for call: String) -> String? {
        var candidate = call
        while !candidate.isEmpty {
            if DXCCDatabase.shared.entity(for: candidate) != nil {
                return candidate
            }
            candidate.removeLast()
        }
        return nil
    }
}
