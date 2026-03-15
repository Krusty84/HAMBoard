//
//  PropagationTabView.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 19/11/2025.
//

import SwiftUI

/// Propagation tab view displaying real-time ionospheric maps from prop.kc2g.com.
struct PropagationTabView: View {

    @StateObject private var vm = PropagationTabViewModel()
    
    var body: some View {
        // Parent view (usually MainWindow or tab container) provides NavigationStack
        Group {
            // tvOS-specific layout – segmented control below the system top menu
            VStack(spacing: 5) {
                // Centered segmented control with breathing room from the top menu
                HStack {
                    Spacer()
                    Picker("Propagation pages", selection: $vm.selectedPage) {
                        ForEach(vm.pages) { page in
                            Text(page.title)
                                .tag(page)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .labelsHidden()
                    .frame(maxWidth: 600)
                    Spacer()
                }
                .padding(.top, 8)       // Small gap from tvOS top menu
                .padding(.horizontal, 24)
                
                // Main map content
                content
                    .padding(.top, 0)
            }
            .background(Color.black.ignoresSafeArea())
        }
    }
    
    // MARK: - Content (TabView with SVG maps)
    
    /// The actual page-based TabView containing the three SVG maps
    private var content: some View {
        TabView(selection: $vm.selectedPage) {
            SolarConditionsView()
                .tag(PropagationPage.general)
            mapPage(for: .muf)
                .tag(PropagationPage.muf)
            mapPage(for: .fof2)
                .tag(PropagationPage.fof2)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        .background(Color.black) // Consistent black background behind all pages
    }

    @ViewBuilder
    private func mapPage(for page: PropagationPage) -> some View {
        if let url = page.mapURL {
            PropagationMapSVGLoader(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        } else {
            Color.black
                .overlay {
                    Text("Map URL is unavailable")
                        .foregroundColor(.white.opacity(0.85))
                        .font(.title3.monospaced())
                }
        }
    }
}

// MARK: - Preview

#Preview {
    // Wrap in NavigationStack so the toolbar and title are visible in preview
    NavigationStack {
        PropagationTabView()
    }
}
