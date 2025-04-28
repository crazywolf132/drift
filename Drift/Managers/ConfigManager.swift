//
//  ConfigManager.swift
//  Drift
//
//  Created by Brayden Moon on 20/2/2025.
//

import Foundation

/// Manages configuration loading, saving, and monitoring for changes
/// Handles reading/writing to the JSON configuration file and provides defaults
class ConfigManager {
    /// Shared instance for easy access
    static let shared = ConfigManager()
    /// Current active configuration
    var config = DriftConfiguration(
        settings: GlobalSettings(quickSwitchEnabled: true),
        actions: [] // Start with an empty configuration
    )

    /// Path to the configuration file, computed lazily
    lazy var configURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/drift/config.json")
    }()

    /// File monitor for detecting configuration changes
    private var fileMonitor: FileMonitor?

    /// Flag to prevent multiple simultaneous loading operations
    private var isLoading = false

    /// Dedicated queue for file operations to avoid blocking the main thread
    private static let fileQueue = DispatchQueue(label: "com.drift.config.fileOperations", qos: .utility)

    /// Initialize the config manager and ensure directory exists
    init() {
        createConfigDirectoryIfNeeded()
    }

    /// Creates the configuration directory if it doesn't exist
    private func createConfigDirectoryIfNeeded() {
        let directoryURL = configURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("Warning: Could not create config directory: \(error.localizedDescription)")
        }
    }

    /// Loads the configuration from disk
    /// - Parameter completion: Optional callback with the loaded configuration
    func loadConfig(completion: ((DriftConfiguration) -> Void)? = nil) {
        // Prevent multiple simultaneous loads
        guard !isLoading else {
            print("Config already loading, skipping duplicate load request")
            return
        }

        isLoading = true

        // Use the dedicated file queue to avoid blocking
        ConfigManager.fileQueue.async { [weak self] in
            guard let self = self else { return }

            // Reset flag when done
            defer { self.isLoading = false }

            do {
                // Check if the file exists first
                let fileManager = FileManager.default
                if !fileManager.fileExists(atPath: self.configURL.path) {
                    print("Config file doesn't exist, creating default configuration")
                    try self.defaultConfig()
                }

                // Read data with buffer size control to limit memory usage
                let data = try Data(contentsOf: self.configURL, options: .mappedIfSafe)

                // Use a more efficient decoder with memory limits
                let decoder = JSONDecoder()
                let loadedConfig = try decoder.decode(DriftConfiguration.self, from: data)

                // Update on main thread if needed for UI
                DispatchQueue.main.async {
                    self.config = loadedConfig
                    completion?(loadedConfig)
                }

                print("Successfully loaded configuration")

                // Setup file monitoring after successful load
                self.setupFileMonitoring()
            } catch {
                print("Error loading configuration: \(error.localizedDescription)")

                // Continue with default config on error
                DispatchQueue.main.async {
                    completion?(self.config)
                }
            }
        }
    }

    /// Saves the current configuration to disk
    /// Uses atomic write operations to prevent corruption
    func saveConfig() {
        do {
            // Create directory if needed
            createConfigDirectoryIfNeeded()

            // Use a more efficient encoder
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            // Use a more memory-efficient way of writing data
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: [.atomic])

            print("Successfully saved configuration to: \(configURL.path)")
        } catch {
            print("Error saving configuration: \(error.localizedDescription)")
        }
    }

    /// Creates and saves a default configuration file
    /// - Throws: Error if the file cannot be created or written
    func defaultConfig() throws {
        let defaultConfig = """
        {
          "settings": {
            "quickSwitchEnabled": true,
            "leaderKey": {
              "key": "space",
              "modifiers": {
                "command": false,
                "option": true,
                "control": false,
                "shift": false
              }
            },
            "statusEmojis": {
              "normal": "⚡️",
              "active": "🚀",
              "disabled": "⚠️"
            },
            "useSystemIcons": true
          },
          "actions": [
            { "key": "T", "type": "application", "label": "Terminal", "value": "/Applications/Utilities/Terminal.app", "windowCycleMethod": "next" },
            { "key": "S", "type": "application", "label": "Safari", "value": "/Applications/Safari.app", "windowCycleMethod": "stack" },
            {
              "key": "L", "type": "group", "label": "Launcher",
              "actions": [
                { "key": "S", "type": "application", "label": "Safari", "value": "/Applications/Safari.app", "windowCycleMethod": "stack" },
                { "key": "M", "type": "application", "label": "Mail", "value": "/Applications/Mail.app", "windowCycleMethod": "minimize" }
              ]
            }
          ]
        }
        """
        guard let data = defaultConfig.data(using: .utf8) else {
            throw NSError(domain: "ConfigManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create data from default config string"])
        }

        do {
            try data.write(to: configURL, options: [.atomic])

            // Load the newly written config into memory
            let decoder = JSONDecoder()
            self.config = try decoder.decode(DriftConfiguration.self, from: data)

            print("Created and loaded default config at \(configURL.path)")
        } catch {
            print("Error writing default config: \(error.localizedDescription)")
            throw error
        }
    }

    /// Starts monitoring the configuration file for changes
    func startWatching() {
        // Stop any existing file monitor first
        fileMonitor?.stopMonitoring()
        fileMonitor = nil

        // Only start monitoring if the file exists
        if FileManager.default.fileExists(atPath: configURL.path) {
            fileMonitor = FileMonitor()
            fileMonitor?.startMonitoring(fileURL: configURL) { [weak self] in
                print("Config file changed. Reloading...")
                self?.loadConfig()
            }
        }
    }

    /// Sets up file monitoring for configuration changes
    private func setupFileMonitoring() {
        // Start watching for changes regardless of whether loading succeeded
        startWatching()
    }
}
