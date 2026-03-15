//
//  SolarConditionsViewModel.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 08/12/2025.
//

import Foundation
import Combine
import SwiftUI

/// Represents the propagation condition for a group of HF bands (day/night).
struct BandCondition {
    let bands: String               // Key like "80m-40m"
    var day: String                 // Condition: "Good", "Fair", "Poor"
    var night: String               // Condition: "Good", "Fair", "Poor"
    
    /// Color coding for day condition
    var dayColor: Color {
        color(for: day)
    }
    
    /// Color coding for night condition
    var nightColor: Color {
        color(for: night)
    }
    
    /// Maps textual condition to UI color (green = good, yellow = fair, red = poor)
    private func color(for condition: String) -> Color {
        switch condition {
        case "Good": return .green
        case "Fair": return .yellow
        case "Poor": return .red
        default: return .gray
        }
    }
}

/// Complete parsed solar-terrestrial data model used throughout the Solar Conditions view.
struct SolarData {
    let updated: String                 // Timestamp of last update
    
    // Primary solar indices
    let solarFlux: String
    let sunspots: String
    let aIndex: String
    let kIndex: String
    let kIndexNT: String                // NOAA K-index
    let xray: String
    let heliumLine: String              // 304 Å helium line
    let protonFlux: String              // Proton flux
    let electronFlux: String            // Electron flux
    let aurora: String                  // Aurora power
    let normalization: String           // Normalization factor
    let latDegree: String               // Aurora latitude
    
    let solarWind: String
    let magneticField: String
    let geomagField: String             // Geomagnetic field status text
    let signalNoise: String             // Background noise level
    
    // VHF / E-Skip conditions
    let vhfAurora: String
    let eSkipEurope: String
    let eSkipNorthAmerica: String
    let eSkipEurope6m: String           // 6m E-Skip Europe
    let eSkipEurope4m: String           // 4m E-Skip Europe
    
    // Additional propagation metrics
    let foF2: String                    // Critical frequency
    let mufFactor: String               // MUF factor
    let muf: String                     // Maximum Usable Frequency
    
    let hfBands: [BandCondition]        // HF band conditions (ordered)
}

/// ViewModel responsible for fetching and parsing real-time solar data from hamqsl.com.
///
/// Automatically refreshes every 15 minutes (900 seconds) and publishes parsed data
/// for the SolarConditionsView. Uses a robust XML parser tolerant to schema changes.
@MainActor
final class SolarConditionsViewModel: ObservableObject {
    
    /// Currently parsed solar data – nil until first successful load
    @Published var data: SolarData?
    
    /// True while data is being fetched
    @Published var isLoading = true
    
    /// Optional error message from the last failed load
    @Published var lastError: String?
    
    private let refreshInterval: TimeInterval = 900
    private let solarDataURLString = "https://www.hamqsl.com/solarxml.php"
    private var cancellables = Set<AnyCancellable>()
    private var activeLoadTask: Task<Void, Never>?
    
    /// Initializes the ViewModel and starts periodic refresh timer
    init() {
        loadData()
        
        // Refresh every 15 minutes
        Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.loadData() }
            .store(in: &cancellables)
    }

    deinit {
        activeLoadTask?.cancel()
    }
    
    /// Triggers a fresh data load from hamqsl.com
    func loadData() {
        guard activeLoadTask == nil else {
            return
        }

        isLoading = true
        lastError = nil

        activeLoadTask = Task { [weak self] in
            guard let self else { return }

            defer {
                self.isLoading = false
                self.activeLoadTask = nil
            }

            guard let url = URL(string: self.solarDataURLString) else {
                self.lastError = "Invalid solar data URL."
                return
            }

            do {
                let (rawData, _) = try await URLSession.shared.data(from: url)
                if let parsed = try SolarXMLParser().parse(rawData) {
                    self.data = parsed
                } else {
                    self.lastError = "Unable to parse solar data feed."
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                print("Error loading solar data: \(error)")
                self.lastError = error.localizedDescription
            }
        }
    }
}

// MARK: - XML Parser for hamqsl.com solar data

/// Extremely resilient XML parser that extracts all available solar-terrestrial values
/// from the hamqsl.com solarxml.php feed, even if tags change or new ones appear.
/// Falls back to safe defaults ("–" or "Band Closed") for missing values.
private class SolarXMLParser: NSObject, XMLParserDelegate {
    
    // Default values for all fields
    private var updated = ""
    private var solarFlux = "–"; private var sunspots = "–"
    private var aIndex = "–"; private var kIndex = "–"; private var kIndexNT = "–"
    private var xray = "–"; private var heliumLine = "–"
    private var protonFlux = "–"; private var electronFlux = "–"
    private var aurora = "–"; private var normalization = "–"; private var latDegree = "–"
    private var solarWind = "–"; private var magneticField = "–"
    private var geomagField = "INACTIVE"; private var signalNoise = "–"
    private var foF2 = "–"; private var mufFactor = "–"; private var muf = "–"
    
    // VHF defaults
    private var vhfAurora = "Band Closed"
    private var eSkipEurope = "Band Closed"
    private var eSkipNorthAmerica = "Band Closed"
    private var eSkipEurope6m = "Band Closed"
    private var eSkipEurope4m = "Band Closed"
    
    // HF band conditions (day/night pairs)
    private var bands: [String: (day: String, night: String)] = [
        "80m-40m": ("–", "–"),
        "30m-20m": ("–", "–"),
        "17m-15m": ("–", "–"),
        "12m-10m": ("–", "–")
    ]
    
    // Temporary parsing state
    private var currentElement = ""
    private var currentValue = ""
    private var currentBandName = ""
    private var currentBandTime = ""
    private var currentPhenomenonName = ""
    private var currentPhenomenonLocation = ""
    
    /// Parses raw XML data and returns fully populated SolarData on success
    func parse(_ data: Data) throws -> SolarData? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        if parser.parse() {
            let orderedKeys = ["80m-40m", "30m-20m", "17m-15m", "12m-10m"]
            let hfBands: [BandCondition] = orderedKeys.compactMap { key in
                guard let cond = bands[key] else { return nil }
                return BandCondition(bands: key, day: cond.day, night: cond.night)
            }
            
            return SolarData(
                updated: updated,
                solarFlux: solarFlux,
                sunspots: sunspots,
                aIndex: aIndex,
                kIndex: kIndex,
                kIndexNT: kIndexNT,
                xray: xray,
                heliumLine: heliumLine,
                protonFlux: protonFlux,
                electronFlux: electronFlux,
                aurora: aurora,
                normalization: normalization,
                latDegree: latDegree,
                solarWind: solarWind,
                magneticField: magneticField,
                geomagField: geomagField,
                signalNoise: signalNoise,
                vhfAurora: vhfAurora,
                eSkipEurope: eSkipEurope,
                eSkipNorthAmerica: eSkipNorthAmerica,
                eSkipEurope6m: eSkipEurope6m,
                eSkipEurope4m: eSkipEurope4m,
                foF2: foF2,
                mufFactor: mufFactor,
                muf: muf,
                hfBands: hfBands
            )
        }
        return nil
    }
    
    // MARK: - XMLParserDelegate
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentValue = ""
        
        if elementName == "band" {
            currentBandName = attributeDict["name"] ?? ""
            currentBandTime = attributeDict["time"] ?? ""
        } else if elementName == "phenomenon" {
            currentPhenomenonName = attributeDict["name"] ?? ""
            currentPhenomenonLocation = attributeDict["location"] ?? ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch elementName {
        case "updated": updated = trimmed
        case "solarflux": solarFlux = trimmed
        case "sunspots": sunspots = trimmed
        case "aindex": aIndex = trimmed
        case "kindex": kIndex = trimmed
        case "kindexnt": kIndexNT = trimmed
        case "xray": xray = trimmed
        case "heliumline": heliumLine = trimmed
        case "protonflux": protonFlux = trimmed
        case "electonflux": electronFlux = trimmed
        case "aurora": aurora = trimmed
        case "normalization": normalization = trimmed
        case "latdegree": latDegree = trimmed
        case "solarwind": solarWind = trimmed
        case "magneticfield": magneticField = trimmed
        case "geomagfield": geomagField = trimmed
        case "signalnoise": signalNoise = trimmed
        case "fof2": foF2 = trimmed
        case "muffactor": mufFactor = trimmed
        case "muf": muf = trimmed
            
        case "band":
            if ["80m-40m", "30m-20m", "17m-15m", "12m-10m"].contains(currentBandName) {
                guard var cond = bands[currentBandName] else {
                    break
                }
                if currentBandTime == "day" {
                    cond.day = trimmed
                } else if currentBandTime == "night" {
                    cond.night = trimmed
                }
                bands[currentBandName] = cond
            }
            
        case "phenomenon":
            switch (currentPhenomenonName, currentPhenomenonLocation) {
            case ("vhf-aurora", "northern_hemi"):
                vhfAurora = trimmed
            case ("E-Skip", "europe"):
                eSkipEurope = trimmed
            case ("E-Skip", "north_america"):
                eSkipNorthAmerica = trimmed
            case ("E-Skip", "europe_6m"):
                eSkipEurope6m = trimmed
            case ("E-Skip", "europe_4m"):
                eSkipEurope4m = trimmed
            default:
                break
            }
            
        default:
            break
        }
    }
}
