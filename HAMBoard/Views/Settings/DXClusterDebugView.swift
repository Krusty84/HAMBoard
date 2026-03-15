//
//  DXClusterDebugView.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 01/03/2026.
//

import SwiftUI

/// Direct connect to the selected DX Cluster and provide raw data from it
struct DXClusterDebugView: View {

    @State private var vm = DXClusterDebugViewModel()
    @ObservedObject var vmSettings: SettingsTabViewModel
    
    let isActive: Bool

    // for stable auto-scrolling
    private let bottomAnchorID = "dxClusterDebugBottomAnchor"

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { vm.showError },
            set: { isPresented in
                if !isPresented {
                    vm.clearError()
                }
            }
        )
    }

    private var rawDataStreamBinding: Binding<Bool> {
        Binding(
            get: { vm.isStreaming },
            set: { isEnabled in
                vm.setRawDataStreamEnabled(
                    isEnabled,
                    host: vmSettings.selectedClusterHost,
                    port: vmSettings.currentPort,
                    callsign: vmSettings.callsign
                )
            }
        )
    }

    private var consoleFont: Font {
        .system(size: 18, weight: .regular, design: .monospaced)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            //Header (UP)
            HStack(spacing: 14) {
                Toggle("Raw Data Stream", isOn: rawDataStreamBinding)
                Button("Clear Log") {
                    vm.clearLogAndReconnect(
                        host: vmSettings.selectedClusterHost,
                        port: vmSettings.currentPort,
                        callsign: vmSettings.callsign
                    )
                }
                .buttonStyle(.bordered)
            }
            //Raw data (DOWN)
            rawDXClusterData
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
        .onDisappear {
            vm.stopRawStreamAndClearLog()
        }
        .onChange(of: isActive) { _, newValue in
            if !newValue {
                vm.stopRawStreamAndClearLog()
            }
        }
        .onChange(of: vmSettings.selectedClusterHost) { _, _ in
            vm.reconnectIfStreaming(
                host: vmSettings.selectedClusterHost,
                port: vmSettings.currentPort,
                callsign: vmSettings.callsign
            )
        }
        .onChange(of: vmSettings.currentPort) { _, _ in
            vm.reconnectIfStreaming(
                host: vmSettings.selectedClusterHost,
                port: vmSettings.currentPort,
                callsign: vmSettings.callsign
            )
        }
        .onChange(of: vmSettings.callsign) { _, _ in
            vm.reconnectIfStreaming(
                host: vmSettings.selectedClusterHost,
                port: vmSettings.currentPort,
                callsign: vmSettings.callsign
            )
        }
    }

    // MARK: - Subviews

    private var rawDXClusterData: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if vm.rawConsoleText.isEmpty {
                        Text("No raw data yet. Turn on Raw Data Stream to start receiving server output.")
                            .font(consoleFont)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    } else {
                        Text(verbatim: vm.rawConsoleText)
                            .font(consoleFont)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .onChange(of: vm.rawConsoleText) { _, _ in
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DXClusterDebugView(vmSettings: SettingsTabViewModel(), isActive: true)
}
