//
//  SettingsTabView.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 18/11/2025.
//

import SwiftUI

// MARK: - Root

struct SettingsTabView: View {

    @State private var selection: Int = 0
    @StateObject private var vm = SettingsTabViewModel()
    
    var body: some View {
        NavigationStack {
            Group {
                VStack(spacing: 5) {
                    // tvOS segmented control under top menu
                    HStack {
                        Spacer()
                        Picker("Settings pages", selection: $selection) {
                            Text("General").tag(0)
                            Text("DX Cluster").tag(1)
                            Text("DX Cluster Debug").tag(2)
                            Text("About").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .labelsHidden()
                        .frame(maxWidth: 1250)
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
                    
                    // Main settings content
                    content
                        .padding(.top, 0)
                }
                .background(Color.black.ignoresSafeArea())
            }
            .onAppear { vm.ensureDefaults() }
        }
    }
    
    private var content: some View {
        TabView(selection: $selection) {
            GeneralSettingsView(vm: vm)
                .tag(0)
            
            DXClusterSettingsView(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .tag(1)

            DXClusterDebugView(vmSettings: vm, isActive: selection == 2)
                .tag(2)
            
            About()
                .tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        //.background(Color.black)
    }
}

// MARK: - General page (Operator + current Host/Port + Display)

private struct GeneralSettingsView: View {

    @State private var clusterPickerSelection: String? = nil
    @State private var formResetID = UUID()
    @ObservedObject var vm: SettingsTabViewModel

    private var selectedClusterName: String {
        let selectedHost = DXClusterConfigurationRepository.normalizedHost(vm.selectedClusterHost)

        return vm.availableClusters.first(where: {
            DXClusterConfigurationRepository.normalizedHost($0.host) == selectedHost
        })?.name ?? vm.selectedClusterHost
    }

    private var dxClusterHeader: String {
        "\(selectedClusterName) (\(vm.selectedClusterHost):\(vm.currentPort))"
    }

    var body: some View {
        
        Form {
            Section("You are") {
                TextField("Callsign", text: $vm.callsign)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
            }

            Section("Current DX Cluster") {
                Picker(dxClusterHeader, selection: $clusterPickerSelection) {
                    ForEach(vm.availableClusters) { cluster in
                        Text(cluster.name)
                            .tag(Optional(cluster.host))
                    }
                }
            }
            
            Section("Display") {
                Toggle("Disable screensaver while running", isOn: $vm.disableScreensaver)
            }
        }
        .id(formResetID)
        .onChange(of: clusterPickerSelection) { _, newHost in
            guard let newHost else {
                return
            }
            vm.selectClusterFromGeneralPicker(newHost)
            DispatchQueue.main.async {
                clusterPickerSelection = nil
                formResetID = UUID()
            }
        }
        .onAppear {
            clusterPickerSelection = nil
        }
    }
}

// MARK: - DX Cluster page (add/manage cluster entry point)

private struct DXClusterSettingsView: View {
    
    @ObservedObject var vm: SettingsTabViewModel
    private let buttonRowLeadingInset: CGFloat = 16
    
    private var portFormatter: NumberFormatter {
        let nf = NumberFormatter()
        nf.numberStyle = .none
        nf.minimum = 1
        nf.maximum = 65535
        return nf
    }
    
    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 48
            let verticalPadding: CGFloat = 10
            let columnSpacing: CGFloat = 36
            let qrMinSide: CGFloat = 280
            let qrScale: CGFloat = 0.28
            let qrMaxSide: CGFloat = 460
            let qrSide = min(max(qrMinSide, geometry.size.width * qrScale), qrMaxSide)
            let qrColumnWidth = qrSide + 40
            
            HStack(alignment: .top, spacing: columnSpacing) {
                //Left Column
                qrPanel(size: qrSide, width: qrColumnWidth)
                //Right Column
                dxClusterEditorColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .task {
            vm.ensureDXClusterQRCode()
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func qrPanel(size: CGFloat, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let qrCodeDXClusterURLImage = vm.qrDXClusterURLImage {
                Image(uiImage: qrCodeDXClusterURLImage)
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
            
            Text("List of DX Clusters")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: size, alignment: .leading)
            
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
    }
    
    private var dxClusterEditorColumn: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $vm.editName, prompt: Text("DX Cluster Name, like: My DXC"))
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
            }
            
            Section("Host") {
                TextField("Host", text: $vm.editHost, prompt: Text("DX Cluster Host, like: dxc.example.net"))
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            
            Section("Port") {
                TextField("Port", value: $vm.editPort, formatter: portFormatter)
                    .textFieldStyle(.plain)
                    .keyboardType(.numberPad)
            }
            
            HStack(spacing: 150) {
                Button("New/Clean") {
                    vm.beginNewCluster()
                }
                .buttonStyle(.plain)
                
                Button("Remove") {
                    vm.removeEditedCluster()
                }
                .buttonStyle(.plain)
                
                Button("Save") {
                    vm.saveEditedCluster()
                }
                .buttonStyle(.plain)
                .disabled(!vm.canSaveEditedCluster)
            }
            .background(Color.clear)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, buttonRowLeadingInset)
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            vm.beginEditSelectedCluster()
        }
    }
}

#Preview {
    SettingsTabView()
}
