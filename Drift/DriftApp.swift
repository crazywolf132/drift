//
//  DriftApp.swift
//  Drift
//
//  Created by Brayden Moon on 20/2/2025.
//

import SwiftUI
import os.log

/**
 * Main entry point for the Drift application.
 * This is a macOS menu bar app with no visible UI except for the status bar icon.
 * It uses key sequences prefixed by a leader key to trigger various actions.
 */
@main
struct DriftApp: App {
    // Connect the AppDelegate to handle application lifecycle
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible UI—using an empty Settings scene
        Settings {
            EmptyView()
                .onAppear {
                    // Log when the settings scene appears for debugging
                    print("[Drift] Settings scene appeared")
                }
        }
    }
}

