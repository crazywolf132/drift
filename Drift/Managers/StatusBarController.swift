//
//  StatusBarController.swift
//  Drift
//
//  Created by Brayden Moon on 20/2/2025.
//

import Cocoa
import Foundation
import SwiftUI

/// Controls the menu bar item (status bar) for the Drift application
/// Responsible for displaying the application state and providing user interactions
class StatusBarController: NSObject {
    
    /// Shared singleton instance with thread-safe initialization
    public static let shared: StatusBarController = {
        let instance = StatusBarController()
        // Schedule setup to happen soon after app launch
        DispatchQueue.main.async {
            instance.setupStatusItem()
        }
        return instance
    }()
    
    /// Status bar and button
    private var statusItem: NSStatusItem? = nil
    private var statusBarButton: NSStatusBarButton? = nil
    
    /// Whether to use system symbols (true) or emojis (false)
    private var useSystemSymbols = true
    
    /// System symbol names
    private struct SystemSymbols {
        static let normal = "sparkles"
        static let active = "sparkles.rectangle.stack.fill"
        static let disabled = "exclamationmark.triangle"
    }
    
    /// Status emojis - will be updated from settings if emoji mode is enabled
    private var normalEmoji: String = "⚡️"
    private var activeEmoji: String = "🚀"
    private var disabledEmoji: String = "⚠️"
    
    /// Image shown in normal state
    private lazy var normalImage: NSImage? = {
        if useSystemSymbols {
            return NSImage(systemSymbolName: SystemSymbols.normal, accessibilityDescription: "Drift")
        } else {
            return createImageFromEmoji(normalEmoji)
        }
    }()
    
    /// Image shown when accessibility permissions are missing
    private lazy var disabledImage: NSImage? = {
        if useSystemSymbols {
            return NSImage(systemSymbolName: SystemSymbols.disabled, accessibilityDescription: "Drift disabled")
        } else {
            return createImageFromEmoji(disabledEmoji)
        }
    }()
    
    /// Image shown when in leader mode
    private lazy var activeImage: NSImage? = {
        if useSystemSymbols {
            return NSImage(systemSymbolName: SystemSymbols.active, accessibilityDescription: "Drift active")
        } else {
            return createImageFromEmoji(activeEmoji)
        }
    }()
    
    /// Whether the controller has been initialized
    private var isInitialized = false
    
    /// Queue for status bar updates to ensure thread safety
    private static let updateQueue = DispatchQueue(label: "com.drift.statusbar", qos: .userInteractive)
    
    /// Private initializer for singleton
    private override init() {
        super.init()
        // Don't access other singletons during initialization to avoid circular dependencies
        // Setup will be triggered by the async dispatch in the shared property
    }
    
    /// Setup the status bar item - called externally after app is ready
    func setupStatusItem() {
        // If already initialized, don't initialize again
        if isInitialized {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            self.statusBarButton = self.statusItem?.button
            
            // Set a default image immediately so something shows up
            if self.useSystemSymbols {
                self.statusBarButton?.image = NSImage(systemSymbolName: SystemSymbols.normal, accessibilityDescription: "Drift")
            } else {
                self.statusBarButton?.image = self.createImageFromEmoji(self.normalEmoji)
            }
            
            // Setup menu
            self.constructMenu()
            
            // Now that we have a visible icon, load config and update the state
            self.loadConfigIfNeeded()
            
            if self.isInLeaderMode() {
                self.updateForLeaderMode()
            } else if AppManager.shared.config.settings.quickSwitchEnabled {
                self.updateForNormalState()
            } else {
                self.updateForDisabledState()
            }
            
            self.isInitialized = true
            print("[Drift] Status bar initialized successfully")
        }
    }
    
    /// Creates an NSImage from an emoji string
    private func createImageFromEmoji(_ emoji: String) -> NSImage? {
        let font = NSFont.systemFont(ofSize: 14)
        let string = NSString(string: emoji)
        
        // Create the attributed string
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        
        let attributedString = NSAttributedString(string: emoji, attributes: attributes)
        
        // Calculate size with some padding
        let size = string.size(withAttributes: attributes)
        let paddedSize = NSSize(width: size.width + 2, height: size.height + 2)
        
        // Create image
        let image = NSImage(size: paddedSize)
        
        image.lockFocus()
        
        // Draw the string centered
        let rect = NSRect(origin: NSPoint(x: 1, y: 1), size: size)
        attributedString.draw(in: rect)
        
        image.unlockFocus()
        image.isTemplate = true // This ensures proper appearance in dark mode
        
        return image
    }
    
    /// Updates the emojis used in the status bar
    /// - Parameters:
    ///   - normal: Emoji for normal state
    ///   - active: Emoji for active state
    ///   - disabled: Emoji for disabled state
    func updateEmojis(normal: String, active: String, disabled: String) {
        normalEmoji = normal
        activeEmoji = active
        disabledEmoji = disabled
        
        // Update the current state if using emoji mode
        if !useSystemSymbols {
            if isInLeaderMode() {
                updateForLeaderMode()
            } else if AppManager.shared.config.settings.quickSwitchEnabled {
                updateForNormalState()
            } else {
                updateForDisabledState()
            }
        }
    }
    
    /// Enable or disable emoji mode
    func setEmojiMode(enabled: Bool) {
        useSystemSymbols = !enabled
        // Force update of the status bar
        if isInLeaderMode() {
            updateForLeaderMode()
        } else if AppManager.shared.config.settings.quickSwitchEnabled {
            updateForNormalState()
        } else {
            updateForDisabledState()
        }
    }
    
    /// Updates the emojis used in the status bar from configuration
    func updateEmojisFromConfig() {
        // Get configuration from AppManager directly instead of from AppDelegate
        let config = AppManager.shared.config
        
        // Update system icon preference
        useSystemSymbols = config.settings.useSystemIcons
        
        // Update emoji settings
        normalEmoji = config.settings.statusEmojis.normal
        activeEmoji = config.settings.statusEmojis.active
        disabledEmoji = config.settings.statusEmojis.disabled
        
        // Update the current state based on app state
        if isInLeaderMode() {
            updateForLeaderMode()
        } else if config.settings.quickSwitchEnabled {
            updateForNormalState()
        } else {
            updateForDisabledState()
        }
    }
    
    /// Helper method to check if app is in leader mode by asking AppManager
    private func isInLeaderMode() -> Bool {
        return AppManager.shared.isLeaderModeActive
    }
    
    /// Update the status bar for leader mode
    func updateForLeaderMode() {
        // Ensure we're on the main thread for UI updates
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateForLeaderMode()
            }
            return
        }
        
        // Early return if not initialized yet
        if !isInitialized && statusBarButton == nil {
            return
        }
        
        if useSystemSymbols {
            statusBarButton?.image = NSImage(systemSymbolName: SystemSymbols.active, accessibilityDescription: "Drift active")
        } else {
            statusBarButton?.image = createImageFromEmoji(activeEmoji)
        }
    }
    
    /// Update the status bar for normal state
    func updateForNormalState() {
        // Ensure we're on the main thread for UI updates
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateForNormalState()
            }
            return
        }
        
        // Early return if not initialized yet
        if !isInitialized && statusBarButton == nil {
            return
        }
        
        if useSystemSymbols {
            statusBarButton?.image = NSImage(systemSymbolName: SystemSymbols.normal, accessibilityDescription: "Drift")
        } else {
            statusBarButton?.image = createImageFromEmoji(normalEmoji)
        }
    }
    
    /// Update the status bar for disabled state
    func updateForDisabledState() {
        // Ensure we're on the main thread for UI updates
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateForDisabledState()
            }
            return
        }
        
        // Early return if not initialized yet
        if !isInitialized && statusBarButton == nil {
            return
        }
        
        if useSystemSymbols {
            statusBarButton?.image = NSImage(systemSymbolName: SystemSymbols.disabled, accessibilityDescription: "Drift disabled")
        } else {
            statusBarButton?.image = createImageFromEmoji(disabledEmoji)
        }
    }
    
    /// Load config settings if needed
    private func loadConfigIfNeeded() {
        // Get configuration from AppManager directly
        let config = AppManager.shared.config
        
        // Set icon style preference
        useSystemSymbols = config.settings.useSystemIcons
        
        // Load emoji settings
        normalEmoji = config.settings.statusEmojis.normal
        activeEmoji = config.settings.statusEmojis.active
        disabledEmoji = config.settings.statusEmojis.disabled
    }
    
    // Construct menu with memory optimizations
    private func constructMenu() {
        // Create a blank menu
        let menu = NSMenu()
        
        // Add version info
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            let versionItem = NSMenuItem(title: "Drift v\(version)", action: nil, keyEquivalent: "")
            versionItem.isEnabled = false
            menu.addItem(versionItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        // Add icon style menu item
        let iconStyleMenu = NSMenu()
        let iconStyleItem = NSMenuItem(title: "Icon Style", action: nil, keyEquivalent: "")
        iconStyleItem.submenu = iconStyleMenu
        
        let systemIconItem = NSMenuItem(title: "System Icons", action: #selector(useSystemIcons), keyEquivalent: "")
        systemIconItem.target = self
        systemIconItem.state = useSystemSymbols ? .on : .off
        iconStyleMenu.addItem(systemIconItem)
        
        let emojiIconItem = NSMenuItem(title: "Emoji Icons", action: #selector(useEmojiIcons), keyEquivalent: "")
        emojiIconItem.target = self
        emojiIconItem.state = useSystemSymbols ? .off : .on
        iconStyleMenu.addItem(emojiIconItem)
        
        menu.addItem(iconStyleItem)
        
        // Create menu items with weak self references in closures
        let aboutItem = NSMenuItem(title: "About", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = NSApplication.shared
        menu.addItem(aboutItem)
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)
        
        // Set the menu
        statusItem?.menu = menu
    }
    
    /// Update the menu checkmarks
    private func updateMenuCheck() {
        if let menu = statusItem?.menu,
           let iconStyleItem = menu.items.first(where: { $0.title == "Icon Style" }),
           let submenu = iconStyleItem.submenu {
            
            for item in submenu.items {
                if item.title == "System Icons" {
                    item.state = useSystemSymbols ? .on : .off
                } else if item.title == "Emoji Icons" {
                    item.state = useSystemSymbols ? .off : .on
                }
            }
        }
    }
    
    /// Switch to system icons
    @objc func useSystemIcons() {
        useSystemSymbols = true
        updateMenuCheck()
        
        // Update the configuration
        AppManager.shared.config.settings.useSystemIcons = true
        
        // Save the configuration through ConfigManager singleton
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.configManager.saveConfig()
        }
        
        // Update the current state
        if isInLeaderMode() {
            updateForLeaderMode()
        } else if AppManager.shared.config.settings.quickSwitchEnabled {
            updateForNormalState()
        } else {
            updateForDisabledState()
        }
    }
    
    /// Switch to emoji icons
    @objc func useEmojiIcons() {
        useSystemSymbols = false
        updateMenuCheck()
        
        // Update the configuration
        AppManager.shared.config.settings.useSystemIcons = false
        
        // Save the configuration through ConfigManager singleton
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.configManager.saveConfig()
        }
        
        // Update the current state
        if isInLeaderMode() {
            updateForLeaderMode()
        } else if AppManager.shared.config.settings.quickSwitchEnabled {
            updateForNormalState()
        } else {
            updateForDisabledState()
        }
    }
    
    /**
     * Opens System Settings to the Accessibility section.
     * This is used when the app detects it doesn't have the needed permissions.
     */
    @objc func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    /**
     * Terminates the application.
     */
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
