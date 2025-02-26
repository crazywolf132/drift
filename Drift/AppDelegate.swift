//
//  AppDelegate.swift
//  Drift
//
//  Created by Brayden Moon on 20/2/2025.
//

import Cocoa
import HotKey
import os.log

/**
 * AppDelegate for the Drift application.
 * Handles application lifecycle events, accessibility permissions,
 * and setting up the core functionality of the app.
 */
class AppDelegate: NSObject, NSApplicationDelegate {
    var configManager = ConfigManager()
    private var hotKey: HotKey?  // Stores the reference to the global hotkey
    private var hasAccessibilityPermissions = false
    private var applicationInitialized = false
    private var leaderMode = false
    
    // Add weak reference to status controller to avoid potential retain cycle
    private weak var statusController: StatusBarController?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Set the activation policy early
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize status bar first to ensure UI is responsive
        statusController = StatusBarController.shared
        
        // Check for existing instances and terminate if found
        checkForExistingInstances()
        
        // Request accessibility permissions - with proper handling
        hasAccessibilityPermissions = requestAccessibilityPermissions()
        
        // Mark as initialized to prevent multiple initializations
        applicationInitialized = true
        
        // Use a more efficient initialization approach
        initializeApp()
    }
    
    // More efficient initialization method that avoids creating unnecessary dispatch queues
    private func initializeApp() {
        // Only setup event tap if we have permissions
        if hasAccessibilityPermissions {
            AppManager.shared.setupEventTap()
        } else {
            // Show an alert if we don't have permissions
            guard let statusController = statusController else { return }
            
            print("[Drift] Accessibility permissions not granted, showing alert")
            statusController.updateForDisabledState()
            
            let alert = NSAlert()
            alert.messageText = "Accessibility Permissions Required"
            alert.informativeText = "Drift requires accessibility permissions to function properly. Please grant these permissions in System Settings > Privacy & Security > Accessibility."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open System Settings to the accessibility section
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            } else {
                NSApp.terminate(nil)
            }
        }
        
        // Load config with optimized memory handling - reuse dispatch queues
        print("[Drift] Loading configuration")
        configManager.loadConfig { [weak self] config in
            guard let self = self else { return }
            
            // Only register keys if we have permissions
            if self.hasAccessibilityPermissions {
                AppManager.shared.registerKeys(config: config)
                
                // Create hotkey only if needed
                self.setupHotKey()
            }
        }
    }
    
    // Extracted method for hotkey setup to improve code organization
    private func setupHotKey() {
        // Get leader key from config
        let config = configManager.config
        let keyString = config.settings.leaderKey.lowercased()
        let modifiers = config.settings.leaderModifiers
        
        // Convert key string to Key enum value using special handling for multi-character keys
        var keyValue: Key?
        
        // Special handling for multi-character key names
        switch keyString {
        case "space":
            keyValue = .space
        case "return", "enter":
            keyValue = .return
        case "tab":
            keyValue = .tab
        case "escape", "esc":
            keyValue = .escape
        case "delete", "backspace":
            keyValue = .delete
        default:
            // For single characters, use the first character
            if let keyChar = keyString.first {
                keyValue = HotKeyManager.keyFromCharacter(keyChar)
            }
        }
        
        // Fallback if no valid key was found
        guard let keyValue = keyValue else {
            print("[Drift] Warning: Invalid leader key configured, falling back to space")
            // Fallback to space if invalid key
            let newHotKey = HotKey(key: .space, modifiers: [.control, .option])
            newHotKey.keyDownHandler = {
                print("[Drift] Hotkey triggered, starting leader mode")
                AppManager.shared.startLeaderMode()
            }
            self.hotKey = newHotKey
            return
        }
        
        // Build modifiers flag
        var modifierFlags: NSEvent.ModifierFlags = []
        if modifiers.command { modifierFlags.insert(.command) }
        if modifiers.option { modifierFlags.insert(.option) }
        if modifiers.control { modifierFlags.insert(.control) }
        if modifiers.shift { modifierFlags.insert(.shift) }
        
        // Require at least one modifier for safety
        if modifierFlags.isEmpty {
            print("[Drift] Warning: No modifiers configured for leader key, adding control for safety")
            modifierFlags.insert(.control)
        }
        
        // Create the hotkey with configured values
        let newHotKey = HotKey(key: keyValue, modifiers: modifierFlags)
        
        // Set up the handler without capturing self
        newHotKey.keyDownHandler = {
            print("[Drift] Hotkey triggered, starting leader mode")
            AppManager.shared.startLeaderMode()
        }
        
        // Only assign to the property when everything is set up
        self.hotKey = newHotKey
        print("[Drift] Hotkey setup complete with key: \(keyString) and modifiers: \(modifierFlags)")
    }
    
    // Check for existing instances of the app and terminate them if found
    private func checkForExistingInstances() {
        let runningApps = NSWorkspace.shared.runningApplications
        let myBundleId = Bundle.main.bundleIdentifier ?? ""
        let myProcessID = ProcessInfo.processInfo.processIdentifier
        
        for app in runningApps {
            if let bundleId = app.bundleIdentifier, 
               bundleId == myBundleId && 
               app.processIdentifier != myProcessID {
                print("[Drift] Found existing instance with PID: \(app.processIdentifier), terminating it")
                app.terminate()
            }
        }
    }
    
    // Request accessibility permissions and return the current status
    func requestAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            print("[Drift] Accessibility permissions are not granted")
        } else {
            print("[Drift] Accessibility permissions are granted")
        }
        return trusted
    }
    
    // Clean up resources when the application is terminating
    func applicationWillTerminate(_ notification: Notification) {
        print("[Drift] Application terminating")
        
        // Cancel any scheduled operations
        RunLoop.current.cancelPerformSelectors(withTarget: self)
        
        // Cleanup any resources
        hotKey?.keyDownHandler = nil
        hotKey = nil
        
        // Clean up app manager resources
        AppManager.shared.cleanup()
        
        // Save config synchronously to ensure it completes before exit
        configManager.saveConfig()
        
        // No need for sleep here as we're not doing async operations anymore
    }
    
    // Controls the application termination process
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        print("[Drift] Application asked if it should terminate")
        
        // Perform any cleanup needed before deciding whether to terminate
        AppManager.shared.cleanup()
        
        // Allow the application to terminate
        return .terminateNow
    }
    
    // Update status bar based on leader mode
    func updateLeaderMode(_ active: Bool) {
        leaderMode = active
        if active {
            StatusBarController.shared.updateForLeaderMode()
        } else {
            StatusBarController.shared.updateForNormalState()
        }
    }
    
    // Update the configuration and UI when config changes
    func configUpdated() {
        setupHotKey()
        StatusBarController.shared.updateEmojisFromConfig()
        
        // Update status bar based on quick switch setting
        if !AppManager.shared.config.settings.quickSwitchEnabled {
            StatusBarController.shared.updateForDisabledState()
        } else if !leaderMode {
            StatusBarController.shared.updateForNormalState()
        }
    }
}

