//
//  HAMBoardApp.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 17/11/2025.
//

import SwiftUI
import SwiftData

/// App entry point for HAMBoard – a real-time DX cluster monitor and propagation dashboard.
///
/// Handles global app lifecycle, particularly disabling the system screensaver/idle timer
/// when the user enables the option and the app is in the foreground.
@main
struct HAMBoardApp: App {
    
    /// Tracks current scene phase (active, inactive, background)
    @Environment(\.scenePhase) private var scenePhase
    
    /// User preference – when true, prevents the device from sleeping while the app is active
    @AppStorage("settings.display.disableScreensaver") private var disableScreensaver: Bool = true
    
    var body: some Scene {
        WindowGroup {
            MainWindow()
                // Apply initial policy when the app launches
                .onAppear { applyIdleTimerPolicy(for: scenePhase) }
                // Generating QR codes for urls
                .task(priority: .background) {
                    QRCodeCache.shared.preloadOnFirstLoad()
                }
                
                // Re-apply when the user toggles the "Disable screensaver" setting
                .onChange(of: disableScreensaver) { _, _ in
                    applyIdleTimerPolicy(for: scenePhase)
                }
                
                // Re-apply when the app becomes active, goes to background, or returns to foreground
                .onChange(of: scenePhase) { _, newPhase in
                    applyIdleTimerPolicy(for: newPhase)
                }
        }
    }
}

// MARK: - Screensaver / Idle Timer Management

/// Private extension containing logic to control the system's idle timer (screensaver/sleep).
private extension HAMBoardApp {
    
    /// Enables or disables the idle timer based on current scene phase and user preference.
    ///
    /// - Parameter phase: Current ScenePhase (.active, .inactive, .background)
    ///
    /// The idle timer is disabled only when:
    /// - The user has enabled "Disable screensaver while running"
    /// - The app is in the active foreground state
    ///
    /// This is especially useful on Apple TV and wall-mounted iPads used as permanent shack displays.
    func applyIdleTimerPolicy(for phase: ScenePhase) {
        let active = (phase == .active)
        let shouldDisable = disableScreensaver && active
        
        // UIApplication.isIdleTimerDisabled must be set on the main thread
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = shouldDisable
        }
    }
}
