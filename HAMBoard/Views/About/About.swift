//
//  About.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 17/11/2025.
//

import SwiftUI

struct About: View {
    
    @StateObject private var vm = AboutViewModel()
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 48
            let verticalPadding: CGFloat = 10
            let columnSpacing: CGFloat = 36
            let qrMinSide: CGFloat = 280
            let qrScale: CGFloat = 0.28
            let qrMaxSide: CGFloat = 460
            let qrSize = min(max(qrMinSide, geometry.size.width * qrScale), qrMaxSide)
            let qrColumnWidth = qrSize + 40
            
            HStack(alignment: .top, spacing: columnSpacing) {
                //Left Column
                qrPanel(size: qrSize, width: qrColumnWidth)
                //Right Column
                aboutTextColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .task {
            vm.ensureRepoQRCode()
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func qrPanel(size: CGFloat, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let qrURLImage = vm.qrRepoURLImage {
                Image(uiImage: qrURLImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.white)
                    )
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: size, height: size)
                    .overlay {
                        if vm.isLoadingQRCode {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("Loading QR code...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("QR unavailable")
                                .foregroundStyle(.secondary)
                        }
                    }
            }
            
            Text("Docs/Sources/Issues")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(width: width, alignment: .leading)
    }
    
    private var aboutTextColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.aboutText)
                .font(.headline.monospaced())
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    NavigationStack {
        About()
    }
}
