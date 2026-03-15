//
//  CountryCodeMapper.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 19/11/2025.
//

import Foundation

/// A thread-safe, lazily-loaded resolver that maps DXCC entity names from `cty.plist`
/// to ISO 3166-1 alpha-2 country codes and clean, user-friendly display names.
///
/// Data is loaded once from `country_code.json` bundled with the app.
/// Uses `NSLock` to prevent race conditions during concurrent first access.
/// Designed to be fast, memory-efficient, and safe on all Apple platforms (including tvOS).
struct CountryMapper {
    
    // MARK: - JSON Model
    
    private struct Entry: Decodable {
        let ISO: String   // ISO 3166-1 alpha-2 code (e.g., "DE", "RU")
        let desc: String  // Full DXCC entity name as appears in cty.plist
    }
    
    private struct JSONContainer: Decodable {
        let country_codes: [Entry]
    }
    
    // MARK: - Thread-Safe Storage

    private final class Storage: @unchecked Sendable {
        var isoByDesc: [String: String] = [:]
        var displayByDesc: [String: String] = [:]
        let loadLock = NSLock()
        var isLoaded = false
    }

    private static let storage = Storage()
    
    // MARK: - Lazy Loading
    
    /// Ensures the country mapping data is loaded exactly once, even under concurrent access.
    /// Thread-safe thanks to `NSLock`.
    private static func ensureLoaded() {
        let storage = self.storage
        storage.loadLock.lock()
        defer { storage.loadLock.unlock() }
        
        guard !storage.isLoaded else { return }
        
        guard let url = Bundle.main.url(forResource: "country_code", withExtension: "json") else {
            print("CountryMapper: 'country_code.json' not found in app bundle")
            storage.isLoaded = true
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let container = try JSONDecoder().decode(JSONContainer.self, from: data)
            
            // Clear any previous data (defensive)
            storage.isoByDesc.removeAll(keepingCapacity: true)
            storage.displayByDesc.removeAll(keepingCapacity: true)
            
            for entry in container.country_codes {
                // Force string copy to break NSTaggedPointerString (important on tvOS/watchOS)
                let rawDesc = String(entry.desc)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard !rawDesc.isEmpty else { continue }
                
                let isoCode = entry.ISO
                    .trimmingCharacters(in: .whitespaces)
                    .uppercased()
                
                // Store ISO code if valid
                if !isoCode.isEmpty {
                    storage.isoByDesc[rawDesc] = isoCode
                }
                
                // Generate clean display name
                var pretty = rawDesc
                    .replacingOccurrences(of: "Fed. Rep. of ", with: "")
                    .replacingOccurrences(of: "Republic of ", with: "")
                    .replacingOccurrences(of: " Is\\..*$", with: " Islands", options: .regularExpression)
                    .replacingOccurrences(of: " \\(.+\\)$", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&", with: "and")
                
                // Manual overrides for better readability
                switch pretty {
                case "United States": pretty = "USA"
                case "England", "Scotland", "Wales", "Northern Ireland": pretty = "United Kingdom"
                case "Rep. of Korea", "South Korea": pretty = "S. Korea"
                default: break
                }
                
                storage.displayByDesc[rawDesc] = pretty
            }
            
            storage.isLoaded = true
            print("CountryMapper: successfully loaded \(container.country_codes.count) country mappings")
            
        } catch {
            print("CountryMapper: failed to load or decode 'country_code.json' – \(error)")
            storage.isLoaded = true // Prevent repeated attempts
        }
    }
    
    // MARK: - Public API
    
    /// Returns the ISO 3166-1 alpha-2 country code for a given DXCC entity name.
    ///
    /// - Parameter countryName: The exact entity name from cty.plist or cluster spot
    /// - Returns: Two-letter country code (e.g., "DE", "JA", "US") or `nil` if not found
    static func isoCode(for countryName: String?) -> String? {
        ensureLoaded()
        guard let name = countryName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return storage.isoByDesc[name]
    }
    
    /// Returns a clean, human-readable country name suitable for UI display.
    ///
    /// - Parameter countryName: Raw entity name from cty.plist
    /// - Returns: Formatted name (e.g., "Germany", "USA", "Canary Islands") or "-" if unknown
    static func displayName(for countryName: String?) -> String {
        ensureLoaded()
        guard let name = countryName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return "-" }
        
        if let pretty = storage.displayByDesc[name] {
            return pretty
        }
        
        // Fallback: basic cleanup if no precomputed display name exists
        let cleaned = name
            .replacingOccurrences(of: "Fed. Rep. of ", with: "")
            .replacingOccurrences(of: "Republic of ", with: "")
            .replacingOccurrences(of: " \\(.+\\)$", with: "", options: .regularExpression)
        
        return cleaned.isEmpty ? "-" : cleaned
    }
}
