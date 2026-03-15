//
//  DXClusterTabView.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 18/11/2025.
//

import SwiftUI
import FlagKit

/// Main SwiftUI view displaying a live DX cluster feed with filtering, flags, and announcements.
struct DXClusterTabView: View {
    
    @ObservedObject var vm: DXClusterTabViewModel
    @State private var selection: Int = 0
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Group {
                VStack(spacing: 5) {
                    HStack {
                        Spacer()
                        Picker("DX Cluster pages", selection: $selection) {
                            Text("Spots").tag(0)
                            Text("Announcements").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .labelsHidden()
                        .frame(maxWidth: 800)
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
                    
                    content
                        .padding(.top, 0)
                }
                .background(Color.black.ignoresSafeArea())
            }
        }
    }
    
    // MARK: - Subviews
    
    private var content: some View {
        TabView(selection: $selection) {
            spotsContent
                .tag(0)
            
            announcementsContent
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
    }
    
    private var spotsContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 10) {
                HeaderRow()
                    .padding(.horizontal)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(vm.filteredSpots.enumerated()), id: \.element) { index, spot in
                            SpotRow(spot: spot, index: index)
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .overlay(alignment: .center) {
                if vm.isLoading || vm.filteredSpots.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.4)
                        
                        Text(vm.isLoading ? "Connecting to cluster…" : "Waiting for spots…")
                            .foregroundColor(.white)
                            .font(.title3.monospaced())
                        
                        Text("If it takes a long time, then try to change cluster...")
                            .foregroundColor(.white.opacity(0.85))
                            .font(.callout.monospaced())
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("clusterLoadingOverlay")
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
        }
    }
    
    private var announcementsContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 10) {
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(vm.announcementsFeed.enumerated()), id: \.offset) { index, line in
                            AnnouncementLineRow(text: line, index: index)
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .overlay(alignment: .center) {
                if vm.isLoading || vm.announcementsFeed.isEmpty {
                    VStack(spacing: 12) {
                        if vm.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(1.4)
                        }
                        
                        Text(vm.isLoading ? "Connecting to cluster…" : "Waiting for announcements…")
                            .foregroundColor(.white)
                            .font(.title3.monospaced())
                        
//                        Text("Commands: SH/ANN 10 -> SHOW/ANN 10")
//                            .foregroundColor(.white.opacity(0.85))
//                            .font(.callout.monospaced())
//                            .multilineTextAlignment(.center)
//                            .transition(.opacity)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("clusterAnnouncementOverlay")
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

// MARK: - Table Header Row

/// Fixed header that defines column layout and colors for the spot table.
private struct HeaderRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Band")
                .frame(width: 120, alignment: .leading)
                .foregroundColor(Color("labelColorGreen"))
                .font(.headline)
                .fontWeight(.heavy)
            
            Text("Freq")
                .frame(width: 180, alignment: .leading)
                .foregroundColor(Color("labelColorGreen"))
                .font(.headline)
                .fontWeight(.heavy)
            
            Text("DX")
                .frame(width: 200, alignment: .leading)
                .foregroundColor(Color("labelColorGreen"))
                .font(.headline)
                .fontWeight(.heavy)
            
            Text("Country")
                .frame(width: 380, alignment: .leading)
                .foregroundColor(Color("labelColorGreen"))
                .font(.headline)
                .fontWeight(.heavy)
            
            Text("Spotter")
                .frame(width: 180, alignment: .leading)
                .foregroundColor(Color("labelColorGreen"))
                .font(.headline)
                .fontWeight(.heavy)
            
            Text("Time")
                .frame(width: 180, alignment: .leading)
                .foregroundColor(Color("labelColorGreen"))
                .font(.headline)
                .fontWeight(.heavy)
            
            Text("Comment")
                .foregroundColor(Color("labelColorGreen"))
                .font(.headline)
                .fontWeight(.heavy)
            
            Spacer(minLength: 0)
        }
        .font(.system(size: 28, weight: .semibold, design: .monospaced))
    }
}

// MARK: - Individual Spot Row

/// Single row in the cluster table – displays all relevant spot information with flag.
private struct SpotRow: View {
    let spot: Spot
    let index: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            
            // Band
            Text(spot.band)
                .foregroundColor(Color("valueColorGreen"))
                .frame(width: 120, alignment: .leading)
                .fontWeight(.heavy)
            
            // Freq
            Text(String(format: "%.1f", spot.freq))
                .foregroundColor(Color("valueColorGreen"))
                .frame(width: 180, alignment: .leading)
                .fontWeight(.heavy)
            
            // DX
            Text(spot.dx)
                .foregroundColor(Color("valueColorGreen"))
                .frame(width: 200, alignment: .leading)
                .fontWeight(.heavy)
            
            // Country
            HStack(spacing: 12) {
                Group {
                    if let code = spot.dxStation.countryCode,
                       let flag = Flag(countryCode: code)?.image(style: .roundedRect) {
                        Image(uiImage: flag)
                            .resizable()
                            .frame(width: 60, height: 40)
                            .saturation(0.6)
                    } else {
                        Text("🌍")
                            .font(.system(size: 40))
                    }
                }
                Text(spot.dxStation.displayCountryName)
                    .foregroundColor(Color("valueColorGreen"))
                    .lineLimit(1)
            }
            .frame(width: 380, alignment: .leading)
            
            // Spotter
            Text(spot.spotter)
                .frame(width: 180, alignment: .leading)
                .foregroundColor(Color("valueColorGreen"))
            
            // Time
            Text(spot.timeZ)
                .frame(width: 180, alignment: .leading)
                .foregroundColor(Color("valueColorGreen"))
            
            // Comment
            Text(spot.comment)
                .lineLimit(1)
                .foregroundColor(Color("valueColorGreen"))
            
            Spacer(minLength: 0)
        }
        //.font(.system(size: 32, design: .monospaced))
        .font(.body)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(rowBackgroundColor)
    }
    
    private var rowBackgroundColor: Color {
        if index % 2 == 0 {
            return Color.black.opacity(0.95)
        } else {
            return Color(hex: "1A1A1A")
        }
    }
}

// MARK: - Announcement Rows

private struct AnnouncementLineRow: View {
    let text: String
    let index: Int
    
    var body: some View {
        Text(text)
            .foregroundColor(Color("valueColorGreen"))
            .font(.body.monospaced())
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.horizontal, 12)
            .background(rowBackgroundColor)
    }
    
    private var rowBackgroundColor: Color {
        if index % 2 == 0 {
            return Color.black.opacity(0.95)
        } else {
            return Color(hex: "1A1A1A")
        }
    }
}

// Helper for convert color to hex
extension Color {
    init(hex: String) {
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: cleanedHex)
        var rgb: UInt64 = 0
        
        scanner.scanHexInt64(&rgb)
        
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

// Preview
#Preview {
    DXClusterTabView(
        vm: DXClusterTabViewModel(
            host: "dxc.w1nr.net",
            port: 7300,
            callsign: "NOCALL"
        )
    )
}
