//
//  DXCCDatabase.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 18/11/2025.
//

import Foundation

/// Represents a single DXCC entity as defined in the standard `cty.plist` / `cty.dat` format.
///
/// Contains all essential geographic and administrative data required for accurate callsign
/// resolution, mapping, logging, and award tracking.
struct DXCCEntity {
    /// Official DXCC entity name (e.g. "Fed. Rep. of Germany", "European Russia")
    let country: String
    
    /// CQ Zone (1–40)
    let cqz: Int
    
    /// ITU Zone (1–90)
    let ituz: Int
    
    /// Continent abbreviation (AF, AN, AS, EU, NA, OC, SA)
    let continent: String
    
    /// Approximate geographic center latitude (North positive)
    let latitude: Double
    
    /// Approximate geographic center longitude (East positive, West negative)
    let longitude: Double
    
    /// Standard time offset from UTC in hours (e.g. -5.0 for EST, +9.0 for JST)
    let utcOffset: Double
}

/// Thread-safe, singleton database that loads and provides fast prefix-based lookup
/// of DXCC entities from the standard `cty.plist` file (distributed by country-files.com).
///
/// Uses longest-prefix matching — the de-facto standard in all serious DXing software.
final class DXCCDatabase: Sendable {
    
    /// Shared singleton instance — safe to use from any thread
    static let shared = DXCCDatabase()
    
    /// Internal storage: prefix → DXCC entity
    private let entities: [String: DXCCEntity]
    
    /// Private initializer ensures singleton pattern
    private init() {
        entities = Self.load()
    }
    
    /// Loads the DXCC database from `cty.plist` bundled with the app.
    ///
    /// The plist must follow the format maintained by Jim AD1C at country-files.com:
    /// ```xml
    /// <key>EA</key>
    /// <dict>
    ///   <key>Country</key><string>Spain</string>
    ///   <key>CQZone</key><integer>14</integer>
    ///   ...
    /// </dict>
    /// ```
    ///
    /// Prints a warning if the file is missing or malformed.
    private static func load() -> [String: DXCCEntity] {
        guard let url = Bundle.main.url(forResource: "cty", withExtension: "plist"),
              let plist = NSDictionary(contentsOf: url) as? [String: Any] else {
            print("DXCCDatabase: 'cty.plist' not found in app bundle!")
            print("Download the latest from https://www.country-files.com/cty-plist/ and add to your target.")
            return [:]
        }
        
        var entities: [String: DXCCEntity] = [:]
        var loadedCount = 0
        
        for (prefix, rawInfo) in plist {
            guard let info = rawInfo as? [String: Any],
                  let country = info["Country"] as? String,
                  let cqz = info["CQZone"] as? Int,
                  let ituz = info["ITUZone"] as? Int,
                  let continent = info["Continent"] as? String,
                  let latitude = info["Latitude"] as? Double,
                  let longitude = info["Longitude"] as? Double,
                  let utcOffset = info["GMTOffset"] as? Double else {
                continue
            }
            
            // Note: cty.plist uses West longitude as positive → we convert to standard (E+, W–)
            let correctedLongitude = longitude >= 0 ? -longitude : abs(longitude)
            
            entities[prefix.uppercased()] = DXCCEntity(
                country: country,
                cqz: cqz,
                ituz: ituz,
                continent: continent,
                latitude: latitude,
                longitude: correctedLongitude,
                utcOffset: utcOffset
            )
            
            loadedCount += 1
        }
        
        print("DXCCDatabase: successfully loaded \(loadedCount) entities from cty.plist")
        return entities
    }
    
    /// Returns the DXCC entity for the longest matching prefix of the given callsign prefix.
    ///
    /// Example:
    /// - "VP8"     → South Shetland Islands
    /// - "TO5"     → French St. Martin
    /// - "4U1UN"   → United Nations HQ
    /// - "W1AW"    → United States
    ///
    /// - Parameter prefix: Callsign prefix to resolve (case-insensitive)
    /// - Returns: Matching `DXCCEntity` or `nil` if no match found
    func entity(for prefix: String) -> DXCCEntity? {
        var search = prefix.uppercased()
        while !search.isEmpty {
            if let entity = entities[search] {
                return entity
            }
            search.removeLast()
        }
        return nil
    }
}
