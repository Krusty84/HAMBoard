//
//  SolarConditionsView.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 08/12/2025.
//

import SwiftUI

/// Solar condition tab view displaying real-time data  from hamqsl.com
struct SolarConditionsView: View {
    
    @StateObject private var vm = SolarConditionsViewModel()
    
    // 1) Whole card height sync (left -> right)
    @State private var leftCardHeight: CGFloat = 0

    // 2) Section height sync (top + bottom across both cards)
    @State private var topAreaHeight: CGFloat = 0
    @State private var bottomAreaHeight: CGFloat = 0
    
    // Extra spacing between Aurora rows (user request)
    private let hfRowSpacing: CGFloat = 20
    private let vhfRowSpacing: CGFloat = 20
    private let solarRowSpacing: CGFloat = 5

    private let bandMapping = [
        "80m-40m": "80–40m",
        "30m-20m": "30–20m",
        "17m-15m": "17–15m",
        "12m-10m": "12–10m"
    ]

    var body: some View {
        GeometryReader { geo in
            // Layout tuning for TV Screen
            let hPadding: CGFloat = 100
            let spacing: CGFloat = hPadding

            // Make both cards equal width and clamp to look good on big TVs (no less than 580-680)
            let available = max(0, geo.size.width - (hPadding * 2) - spacing)
            let columnWidth = max(680, min(800, available / 2))

            ZStack {
                Color.black.ignoresSafeArea()

                if vm.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.4)
                        
                        Text("Waiting for propagation data…")
                            .foregroundColor(.white)
                            .font(.title3.monospaced())
                    }
                    
                } else if let data = vm.data {
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: spacing) {

                            // LEFT CARD (natural height)
                            PanelCard(width: columnWidth, height: nil) {
                                leftCardContent(data: data)
                            }
                            .readHeight { h in
                                leftCardHeight = max(leftCardHeight, h)
                            }

                            // RIGHT CARD (forced to left card height)
                            PanelCard(width: columnWidth, height: leftCardHeight > 0 ? leftCardHeight : nil) {
                                rightCardContent(data: data)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, hPadding)
                        .padding(.top, 10)
                        .padding(.bottom, 60)
                        .onPreferenceChange(TopAreaHeightKey.self) { topAreaHeight = $0 }
                        .onPreferenceChange(BottomAreaHeightKey.self) { bottomAreaHeight = $0 }
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("Unable to load propagation data")
                            .foregroundColor(.white)
                            .font(.title3.monospaced())

                        if let lastError = vm.lastError, !lastError.isEmpty {
                            Text(lastError)
                                .foregroundColor(.white.opacity(0.8))
                                .font(.callout.monospaced())
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .padding(.horizontal, 80)
                        }

                        Button("Retry") {
                            vm.loadData()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    // MARK: - Left Card Content (no background here)

    @ViewBuilder
    private func leftCardContent(data: SolarData) -> some View {
        VStack(spacing: 5) {

            Text("HF Conditions")
                .foregroundColor(Color("labelColorGreen"))
                .font(.headline)
                .fontWeight(.heavy)
                .frame(maxWidth: .infinity)

            // TOP AREA (HF table) — synced height with right top area
            VStack(spacing: hfRowSpacing) {
                HStack(spacing: 10) {
                    Text("Band").frame(width: 180, alignment: .leading)
                    Text("Day").frame(width: 130, alignment: .center)
                    Text("Night").frame(width: 130, alignment: .center)
                }
                .foregroundColor(Color("labelColorGreen"))
                .font(.subheadline)
                .fontWeight(.heavy)

                ForEach(data.hfBands, id: \.bands) { cond in
                    HStack(spacing: 10) {
                        Text(bandMapping[cond.bands] ?? cond.bands)
                            .frame(width: 180, alignment: .leading)

                        Text(cond.day)
                            .foregroundColor(cond.dayColor)
                            .frame(width: 130, alignment: .center)

                        Text(cond.night)
                            .foregroundColor(cond.nightColor)
                            .frame(width: 130, alignment: .center)
                    }
                    .font(.body)
                    .padding(.vertical, 4)
                }
            }
            .measureHeight(key: TopAreaHeightKey.self)
            .frame(height: topAreaHeight > 0 ? topAreaHeight : nil, alignment: .top)

            SectionDivider()

            Text("VHF Phenomena")
                .foregroundColor(Color("labelColorGreen"))
                .font(.headline)
                .fontWeight(.heavy)
                .frame(maxWidth: .infinity)

            // BOTTOM AREA (VHF list) — synced height with right bottom area
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: vhfRowSpacing) {
                    Text("Aurora")
                    Text("Aurora Lat")
                    Text("E-Skip EU")
                    Text("EU 4m")
                    Text("EU 6m")
                    Text("NA")
                }
                .frame(width: 180, alignment: .leading)
                .foregroundColor(Color("labelColorGreen"))
                .font(.body)

                Spacer()

                VStack(alignment: .leading, spacing: vhfRowSpacing) {
                    Text(data.vhfAurora)
                    Text(data.latDegree)
                    Text(data.eSkipEurope)
                    Text(data.eSkipEurope4m)
                    Text(data.eSkipEurope6m)
                    Text(data.eSkipNorthAmerica)
                }
                .frame(width: 180, alignment: .trailing)
                .foregroundColor(Color("valueColorGreen"))
                .font(.body)
            }
            .measureHeight(key: BottomAreaHeightKey.self)
            .frame(height: bottomAreaHeight > 0 ? bottomAreaHeight : nil, alignment: .top)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Right Card Content (no background here)

    @ViewBuilder
    private func rightCardContent(data: SolarData) -> some View {
        VStack(spacing: solarRowSpacing) {
            Text("Solar Weather")
                .foregroundColor(Color("labelColorGreen"))
                .font(.headline)
                .fontWeight(.heavy)
                .frame(maxWidth: .infinity)

            // TOP AREA (key parameters) — synced height with left top area
            VStack(alignment: .leading, spacing: solarRowSpacing) {
                KeySolarParameters(title: "Sunspot Number", value: data.sunspots, color: .orange) {
                    Text("Higher better")
                }
                KeySolarParameters(title: "Solar Flux", value: data.solarFlux, color: colorForSFI(data.solarFlux)) {
                    Text("Higher better")
                }
                KeySolarParameters(title: "Solar Wind", value: data.solarWind + " km/s", color: .cyan) {
                    Text("Lower better")
                }
                KeySolarParameters(title: "Noise Floor", value: data.signalNoise, color: .yellow) { }
                KeySolarParameters(title: "Geomagnetic Storm", value: data.geomagField.capitalized, color: colorForGeomag(data.geomagField)) { }
            }
            .measureHeight(key: TopAreaHeightKey.self)
            .frame(height: topAreaHeight > 0 ? topAreaHeight : nil, alignment: .top)

            SectionDivider()

            Text("Solar Indices")
                .foregroundColor(Color("labelColorGreen"))
                .font(.headline)
                .fontWeight(.heavy)
                .frame(maxWidth: .infinity)

            // BOTTOM AREA (indices) — synced height with left bottom area
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: solarRowSpacing) {
                    Text("SFI")
                    Text("A-Index")
                    Text("K-Index")
                    Text("X-Ray")
                    Text("B₀ Angle")
                    Text("He Line")
                    Text("Proton Flux")
                    Text("Electron Flux")
                }
                .frame(width: 250, alignment: .leading)
                .foregroundColor(Color("labelColorGreen"))
                .font(.body)

                Spacer()

                VStack(alignment: .leading, spacing: solarRowSpacing) {
                    Text(data.solarFlux)
                    Text(data.aIndex)
                    Text(data.kIndex)
                    Text(data.xray)
                    Text(data.magneticField)
                    Text(data.heliumLine)
                    Text(data.protonFlux)
                    Text(data.electronFlux)
                }
                .frame(width: 200, alignment: .trailing)
                .foregroundColor(Color("valueColorGreen"))
                .font(.body)
            }
            .measureHeight(key: BottomAreaHeightKey.self)
            .frame(height: bottomAreaHeight > 0 ? bottomAreaHeight : nil, alignment: .top)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Color Helpers

    private func colorForSFI(_ s: String) -> Color {
        guard let v = Int(s) else { return .white }
        if v >= 150 { return .green }
        if v >= 100 { return .yellow }
        return .red
    }

    private func colorForGeomag(_ s: String) -> Color {
        if s.contains("INACTIVE") || s.contains("QUIET") { return .green }
        if s.contains("UNSETTLED") { return .yellow }
        return .red
    }
}

// MARK: - Card Wrapper (fixes missing bottom border)

private struct PanelCard<Content: View>: View {
    let width: CGFloat
    let height: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(24)
            // Important: apply final frame BEFORE background/overlay so border draws on full height
            .frame(width: width, height: height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
    }
}

private struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(height: 1)
            .padding(.vertical, 10)
    }
}

// MARK: - Reusable Components

struct KeySolarParameters<Description: View>: View {
    let title: String
    let value: String
    let color: Color
    let description: () -> Description

    init(
        title: String,
        value: String,
        color: Color,
        @ViewBuilder description: @escaping () -> Description = { EmptyView() }
    ) {
        self.title = title
        self.value = value
        self.color = color
        self.description = description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .foregroundColor(Color("labelColorGreen"))
                    .font(.body)
                    .fontWeight(.heavy)

                Spacer()

                Text(value)
                    .foregroundColor(color)
                    .font(.body)
            }

            description()
                .font(.system(size: 20, design: .monospaced))
                .foregroundColor(.gray.opacity(0.85))
        }
    }
}

// MARK: - Section Height Sync (Top / Bottom)

private struct TopAreaHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct BottomAreaHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func measureHeight<K: PreferenceKey>(key: K.Type) -> some View where K.Value == CGFloat {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: key, value: geo.size.height)
            }
        )
    }
}

// MARK: - Whole Card Height Reader (Left -> Right)

private struct HeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func readHeight(onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self, perform: onChange)
    }
}

// MARK: - Preview

#Preview {
    SolarConditionsView()
}
