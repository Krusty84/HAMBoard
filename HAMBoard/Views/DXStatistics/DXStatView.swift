//
//  DXStatView.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 05/12/2025.
//

import SwiftUI

/// Compact statistics overlay view displayed in the top-left corner of the DX Cluster tab.
struct DXStatView: View {
    
    @ObservedObject var vm: DXStatViewModel
    
    /// Human-readable name of the current cluster (e.g. "W1NR", "DXFun")
    let currentClusterName: String
    
    /// Hostname/IP of the connected cluster node (for display only)
    let selectedClusterHost: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top active bands
            VStack(alignment: .leading, spacing: 1) {
                Text("Top Bands:")
                    .foregroundColor(Color("labelColorGreen"))
                    .fontWeight(.heavy)
                
                Text(vm.topBands.isEmpty ? "N/A" : vm.topBands.map { $0.label }.joined(separator: "/"))
                    .foregroundColor(Color("valueColorGreen"))
            }
            .font(.system(size: 28, weight: .semibold, design: .monospaced))
            
            // Top active countries/entities
            VStack(alignment: .leading, spacing: 1) {
                Text("Top Countries:")
                    .foregroundColor(Color("labelColorGreen"))
                    .fontWeight(.heavy)
   
                Text(vm.topCountries.isEmpty ? "N/A" : vm.topCountries.map { $0.label }.joined(separator: "/"))
                        .foregroundColor(Color("valueColorGreen"))
            }
            .font(.system(size: 28, weight: .semibold, design: .monospaced))
            
            // Cluster identifier
            HStack(spacing: 8) {
                     Text("Cluster:")
                         .foregroundColor(Color("labelColorGreen"))
                         .fontWeight(.heavy)
                     
                     Text("\(currentClusterName)")
                         .foregroundColor(Color("valueColorGreen"))
                 }
            .font(.system(size: 24, weight: .semibold, design: .monospaced))
        }
        //.padding(.vertical, 2)
        .padding(.horizontal, 12)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.leading, 12)
        //.padding(.top, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Preview

#Preview {
    DXStatView(
        vm: {
            let vm = DXStatViewModel()
            vm.topBands = [TopItem(label: "20m", count: 12), TopItem(label: "40m", count: 8)]
            vm.topCountries = [TopItem(label: "K", count: 10), TopItem(label: "DL", count: 6)]
            return vm
        }(),
        currentClusterName: "W1NR",
        selectedClusterHost: "dxc.w1nr.net"
    )
}
