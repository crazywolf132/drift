//
//  AppManager.swift
//  Drift
//
//  Created by Brayden Moon on 25/2/2025.
//

import SwiftUI
import UserNotifications
import AppKit
import Foundation

/// Core manager class that handles keyboard input processing and action execution.
/// This class is responsible for:
/// - Registering key sequences from configuration
/// - Setting up and managing the event tap for keyboard monitoring
/// - Processing key sequences in leader mode
/// - Executing actions (applications, URLs, commands, folders)
/// - Logging with privacy protection
class AppManager {
    static let shared = AppManager()
    
    // MARK: - Logging
    
    // Controls whether debug logs are printed
    #if DEBUG
    private static let debugLoggingEnabled = true
    #else
    private static let debugLoggingEnabled = false
    #endif
    
    /// Privacy levels for logging to protect user data
    enum LogPrivacyLevel {
        case normal    // Non-sensitive info, safe to log
        case sensitive // Potentially private info (paths, URLs, commands)
        case critical  // Important errors, minimally sanitized
    }
    
    /// Logs messages with appropriate privacy protection based on content sensitivity
    /// - Parameters:
    ///   - message: The message to log
    ///   - privacy: The privacy level to apply when logging
    func secureLog(_ message: String, privacy: LogPrivacyLevel = .normal) {
        // Only log if debugging is enabled or it's a critical message
        guard AppManager.debugLoggingEnabled || privacy == .critical else { return }
        
        // For sensitive data, we redact or hash it
        switch privacy {
            case .normal:
                print("[Drift] \(message)")
            case .sensitive:
                // For sensitive data, log only that an action occurred
                print("[Drift] \(message.split(separator: ":").first ?? "Action performed"): <redacted>")
            case .critical:
                // Critical messages are always logged but may be sanitized
                print("[Drift] CRITICAL: \(message)")
        }
    }
    
    /// Sanitizes a path for logging by removing username and sensitive directories
    /// - Parameter path: The path to sanitize
    /// - Returns: A sanitized version of the path
    private func sanitizePath(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count > 3 && components[1] == "Users" {
            // Replace username with <user>
            var sanitized = components
            sanitized[2] = "<user>"
            return sanitized.joined(separator: "/")
        }
        return "<path>"
    }
    
    // Indicates whether leader mode is active.
    private(set) var isLeaderModeActive = false
    // Holds the accumulated key sequence - use a more efficient capacity hint
    private(set) var commandBuffer = ""
    
    // CGEvent tap properties.
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    // Timer to cancel leader mode after inactivity.
    private var leaderTimeoutTimer: Timer?
    // Timer to delay execution if the sequence is ambiguous.
    private var pendingCommandTimer: Timer?
    
    // Config to use - make this non-optional with a default empty config
    var config = DriftConfiguration(
        settings: GlobalSettings(
            quickSwitchEnabled: true,
            leaderKey: "space",
            leaderModifiers: KeyModifiers(option: true, control: true)
        ),
        actions: []
    )
    
    // Flag to track if the event tap is set up
    private var eventTapSetup = false
    
    // Command mapping: keys are sequences and values are actions - use a more efficient initial capacity
    var commandMapping = [String: () -> Void](minimumCapacity: 50)
    
    // Cache commonly accessed status controller
    private weak var statusController: StatusBarController?
    
    // Notification content is reused to reduce allocations
    private let notificationContent = UNMutableNotificationContent()
    
    private init() {
        statusController = StatusBarController.shared
    }
    
    deinit {
        cleanup()
    }
    
    // Clean up all resources to prevent leaks
    func cleanup() {
        // Clean up event tap
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        
        // Clean up timers
        leaderTimeoutTimer?.invalidate()
        leaderTimeoutTimer = nil
        
        pendingCommandTimer?.invalidate()
        pendingCommandTimer = nil
        
        // Clear the command mapping to free up memory
        commandMapping.removeAll(keepingCapacity: false)
    }
    
    /// Registers key sequences from the provided configuration
    /// - Parameter config: The configuration containing actions to register
    func registerKeys(config: DriftConfiguration) {
        secureLog("Registering keys...", privacy: .normal)
        self.config = config
        
        // Clear existing mapping but maintain capacity for efficiency
        commandMapping.removeAll(keepingCapacity: true)
        
        // Only continue if we have a valid config
        guard !config.actions.isEmpty else {
            secureLog("Warning: No actions registered in configuration", privacy: .critical)
            return
        }
        
        // Create these closures once to avoid repeated allocations
        let fileManager = FileManager.default
        
        // Use a stack-based approach instead of recursion to avoid stack overflow for deep hierarchies
        // Use a more realistic initial capacity to avoid resizing
        var stack = [(action: ActionOrGroup, prefix: String)]()
        stack.reserveCapacity(20)
        
        // Add initial actions to stack
        for mapping in config.actions {
            stack.append((action: mapping, prefix: ""))
        }
        
        // Process stack iteratively
        while !stack.isEmpty {
            let current = stack.removeLast()
            
            switch current {
            case (action: .action(let action), prefix: let prefix):
                registerAction(action, prefix: prefix, fileManager: fileManager)
            case (action: .group(let group), prefix: let prefix):
                // Skip groups with empty keys
                guard !group.key.isEmpty else {
                    secureLog("Warning: Skipping group with empty key", privacy: .critical)
                    continue
                }
                
                // More efficient string handling
                let firstChar = group.key.prefix(1).lowercased()
                let groupPrefix = prefix + firstChar
                
                // Add nested actions to stack
                for action in group.actions {
                    stack.append((action: action, prefix: groupPrefix))
                }
            }
        }
        
        secureLog("Registered \(commandMapping.count) key sequences", privacy: .normal)
    }
    
    /// Registers a single action with its key sequence
    /// - Parameters:
    ///   - action: The action to register
    ///   - prefix: The key prefix from parent groups
    ///   - fileManager: File manager instance for path operations
    private func registerAction(_ action: Action, prefix: String, fileManager: FileManager) {
        // Validate the key to prevent crashes
        guard !action.key.isEmpty else {
            secureLog("Warning: Skipping action with empty key", privacy: .critical)
            return
        }
        
        // Only allocate the string once
        let key = prefix + String(action.key.prefix(1)).lowercased()
        secureLog("Registering key sequence: \(key)", privacy: .normal)
        
        // Use weak self in closure to prevent reference cycles
        commandMapping[key] = { [weak self] in
            guard let self = self else { return }
            
            secureLog("Executing command for key sequence: \(key)", privacy: .normal)
            
            // Execute the action based on its type
            switch action.type {
            case .application:
                self.executeApplicationAction(action.value, fileManager: fileManager)
            case .url:
                self.executeURLAction(action.value)
            case .command:
                self.executeCommandAction(action.value)
            case .folder:
                self.executeFolderAction(action.value)
            default:
                self.secureLog("Unsupported action type: \(action.type)", privacy: .critical)
            }
        }
    }
    
    // MARK: - Event Tap Setup
    
    /// Sets up the event tap to monitor keyboard events
    func setupEventTap() {
        // Prevent multiple setups
        if eventTapSetup {
            secureLog("Event tap already set up, skipping", privacy: .normal)
            return
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        // Check if the process is trusted for accessibility first
        if !AXIsProcessTrusted() {
            secureLog("Accessibility permissions not granted. Event tap cannot be created.", privacy: .critical)
            // Notify the user through the status bar
            DispatchQueue.main.async {
                StatusBarController.shared.updateForDisabledState()
            }
            return
        }
        
        // Clean up any existing event tap first
        cleanup()
        
        // Create the event tap - no try-catch needed since CGEvent.tapCreate doesn't throw
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        guard let eventTap = eventTap else {
            secureLog("Failed to create event tap. Ensure Accessibility permissions are enabled.", privacy: .critical)
            DispatchQueue.main.async {
                StatusBarController.shared.updateForDisabledState()
            }
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        
        guard let runLoopSource = runLoopSource else {
            secureLog("Failed to create run loop source.", privacy: .critical)
            DispatchQueue.main.async {
                StatusBarController.shared.updateForDisabledState()
            }
            return
        }
        
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        eventTapSetup = true
        secureLog("Event tap successfully created and added to main run loop.", privacy: .normal)
        
        // Verify the event tap works by checking its enabled status
        if !CGEvent.tapIsEnabled(tap: eventTap) {
            secureLog("Warning: Event tap was created but is not enabled.", privacy: .critical)
            DispatchQueue.main.async {
                StatusBarController.shared.updateForDisabledState()
            }
        }
    }
    
    /// Callback function for the CGEvent tap
    let eventTapCallback: CGEventTapCallBack = { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
        // Get the manager instance without using autoreleasepool - not needed here
        guard let userInfo = userInfo else {
            return Unmanaged.passUnretained(event)
        }
        
        let manager = Unmanaged<AppManager>.fromOpaque(userInfo).takeUnretainedValue()
        
        // Only process if it's a key down event and leader mode is active
        if type == .keyDown && manager.isLeaderModeActive {
            // Handle the key on the main thread - use a more efficient dispatch method
            DispatchQueue.main.async {
                manager.handleKeyDown(event: event)
            }
            
            // Return nil to block the event
            return nil
        }
        
        // If not a key event we care about, pass it through
        return Unmanaged.passUnretained(event)
    }
    
    /// Activates leader mode to begin capturing key sequences
    func startLeaderMode() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.startLeaderMode()
            }
            return
        }
        
        isLeaderModeActive = true
        commandBuffer.removeAll(keepingCapacity: true)
        secureLog("Starting leader mode", privacy: .normal)
        
        // Update AppDelegate's leader mode state
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.updateLeaderMode(true)
        } else {
            // Fallback if AppDelegate can't be accessed
            DispatchQueue.main.async {
                StatusBarController.shared.updateForLeaderMode()
            }
        }
        
        restartLeaderTimeoutTimer()
    }
    
    /// Processes keyboard events when in leader mode
    /// - Parameter event: The CGEvent containing the key press information
    func handleKeyDown(event: CGEvent) {
        // Always process key events on the main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.handleKeyDown(event: event)
            }
            return
        }
        
        // Make sure we can create an NSEvent from the CGEvent
        guard let nsEvent = NSEvent(cgEvent: event) else { 
            secureLog("Failed to create NSEvent from CGEvent", privacy: .critical)
            return 
        }
        
        guard let characters = nsEvent.charactersIgnoringModifiers, !characters.isEmpty else { 
            secureLog("No characters in event", privacy: .normal)
            return 
        }
        
        // Cancel any existing pending timer
        pendingCommandTimer?.invalidate()
        pendingCommandTimer = nil
        
        // Update command buffer with the new character
        commandBuffer.append(characters)
        // Don't log the actual keys pressed - just log that input was received
        self.secureLog("Command buffer updated", privacy: .normal)
        
        // Restart the timeout timer
        restartLeaderTimeoutTimer()
        
        // Check if we have an exact match for the current buffer
        if let action = commandMapping[commandBuffer] {
            // Check if the current command is ambiguous (has longer commands that start with it)
            let ambiguous = commandMapping.keys.contains { $0 != commandBuffer && $0.hasPrefix(commandBuffer) }
            
            if ambiguous {
                // If ambiguous, set a timer to execute after a short delay
                self.secureLog("Ambiguous command, waiting for more input", privacy: .normal)
                pendingCommandTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.secureLog("Executing ambiguous command", privacy: .normal)
                    // Execute the action on the main thread
                    DispatchQueue.main.async {
                        action()
                        self.endLeaderMode()
                    }
                }
            } else {
                // If not ambiguous, execute immediately
                self.secureLog("Executing command", privacy: .normal)
                // Execute the action on the main thread
                DispatchQueue.main.async {
                    action()
                    self.endLeaderMode()
                }
                return
            }
        } else {
            // Check if current buffer is a prefix of any command
            let validPrefix = commandMapping.keys.contains { $0.hasPrefix(commandBuffer) }
            if !validPrefix {
                // If not a valid prefix, end leader mode
                self.secureLog("Invalid command", privacy: .normal)
                endLeaderMode()
            }
        }
    }
    
    /// Restarts the timer for leader mode timeout
    private func restartLeaderTimeoutTimer() {
        stopLeaderTimeoutTimer()
        
        // Create a new timer that will end leader mode after a delay
        leaderTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.endLeaderMode()
        }
    }
    
    /// Stops the leader timeout timer
    private func stopLeaderTimeoutTimer() {
        // Clean up timers
        leaderTimeoutTimer?.invalidate()
        leaderTimeoutTimer = nil
    }
    
    /// Ends leader mode and processes the current command buffer
    func endLeaderMode() {
        isLeaderModeActive = false
        secureLog("Ending leader mode, final buffer: \(commandBuffer)", privacy: .normal)
        
        // Update AppDelegate's leader mode state
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.updateLeaderMode(false)
        } else {
            // Fallback if AppDelegate can't be accessed
            DispatchQueue.main.async {
                StatusBarController.shared.updateForNormalState()
            }
        }
        
        // Process the command if we have one in the buffer
        processCommand()
        commandBuffer.removeAll(keepingCapacity: true)
        stopLeaderTimeoutTimer()
    }
    
    /// Process the command in the buffer
    private func processCommand() {
        // Skip if buffer is empty
        if commandBuffer.isEmpty {
            return
        }
        
        // Log that we're processing a command
        secureLog("Processing command: \(commandBuffer)", privacy: .normal)
        
        // Look up and execute command if found
        if let action = commandMapping[commandBuffer] {
            secureLog("Executing command for: \(commandBuffer)", privacy: .normal)
            // Execute on main thread without autoreleasepool for simpler code
            DispatchQueue.main.async {
                action()
            }
        } else {
            secureLog("No command found for: \(commandBuffer)", privacy: .normal)
        }
    }
    
    /// Shows a notification to the user
    /// - Parameters:
    ///   - title: The notification title
    ///   - message: The notification message (will be sanitized for privacy)
    func showNotification(title: String, message: String) {
        // Log the notification, but protect potentially sensitive message content
        secureLog("Showing notification: \(title)", privacy: .normal)
        
        DispatchQueue.main.async {
            // Sanitize message to avoid exposing sensitive information
            let sanitizedMessage = self.sanitizeMessageForNotification(message)
            
            // Reuse the notification content to reduce allocations
            self.notificationContent.title = title
            self.notificationContent.body = sanitizedMessage
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: self.notificationContent,
                trigger: nil
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    self.secureLog("Error showing notification: \(error.localizedDescription)", privacy: .critical)
                }
            }
        }
    }
    
    /// Sanitizes messages for notifications to remove sensitive data
    /// - Parameter message: The message to sanitize
    /// - Returns: A sanitized version of the message
    private func sanitizeMessageForNotification(_ message: String) -> String {
        // Avoid exposing full file paths - replace with sanitized versions
        if message.contains("/Users/") || message.contains("/home/") {
            // Paths in messages can contain usernames, home directories, etc.
            var sanitized = message
            
            // Replace home directories with generic text
            let homePathPattern = "(/Users/[^/]+|/home/[^/]+)"
            if let regex = try? NSRegularExpression(pattern: homePathPattern, options: []) {
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    options: [],
                    range: NSRange(location: 0, length: sanitized.utf16.count),
                    withTemplate: "<home directory>"
                )
            }
            
            return sanitized
        }
        
        return message
    }
    
    // MARK: - Action Execution
    
    /// Executes an application action by opening the specified application
    /// - Parameters:
    ///   - path: Path to the application
    ///   - fileManager: File manager for verifying paths
    private func executeApplicationAction(_ path: String, fileManager: FileManager) {
        // Verify the path is not empty
        guard !path.isEmpty else {
            secureLog("Application path is empty", privacy: .critical)
            showNotification(title: "Drift Error", message: "Invalid application path")
            return
        }
        
        secureLog("Attempting to launch application", privacy: .sensitive)
        
        // Check if file exists
        if fileManager.fileExists(atPath: path) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                // Additional validation - ensure it's an app bundle or executable
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue {
                    // It's a directory, verify it's an app bundle
                    let isAppBundle = path.hasSuffix(".app")
                    if !isAppBundle {
                        self.secureLog("Path is not an application bundle", privacy: .critical)
                        self.showNotification(title: "Drift Error", message: "Path is not a valid application")
                        return
                    }
                }
                
                // Use the newer API for macOS 11+
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.hidesOthers = false
                
                let appURL = URL(fileURLWithPath: path)
                self.secureLog("Opening application", privacy: .normal)
                
                NSWorkspace.shared.openApplication(
                    at: appURL,
                    configuration: configuration
                ) { (app, error) in
                    if let error = error {
                        self.secureLog("Error launching application: \(error.localizedDescription)", privacy: .critical)
                        self.secureLog("Failed to launch application: \(error.localizedDescription)", privacy: .critical)
                        self.showNotification(title: "Drift Error", message: "Failed to launch application: \(error.localizedDescription)")
                    } else if let app = app {
                        self.secureLog("Successfully launched application: \(app.localizedName ?? "Unknown")", privacy: .normal)
                    } else {
                        self.secureLog("Application launched but no reference returned", privacy: .normal)
                    }
                }
            }
        } else {
            secureLog("Application file does not exist: \(path)", privacy: .critical)
            showNotification(title: "Drift Error", message: "Application not found")
        }
    }
    
    /// Executes a URL action by opening the specified URL
    /// - Parameter urlString: The URL to open
    private func executeURLAction(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            secureLog("Invalid URL format", privacy: .critical)
            showNotification(title: "Drift Error", message: "Invalid URL format")
            return
        }
        
        // Sanitize URL for privacy - only log domain, not full URL
        if let host = url.host {
            secureLog("Opening URL with domain: \(host)", privacy: .sensitive)
        } else {
            secureLog("Opening URL", privacy: .normal)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Executes a shell command
    /// - Parameter command: The command to execute
    private func executeCommandAction(_ command: String) {
        // Validate the command
        guard !command.isEmpty else {
            secureLog("Command is empty", privacy: .critical)
            showNotification(title: "Drift Error", message: "Empty command")
            return
        }
        
        secureLog("Executing command", privacy: .sensitive)
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            let task = Process()
            task.launchPath = "/bin/zsh"
            task.arguments = ["-c", command]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            // Timeout for commands in seconds
            let commandTimeout: TimeInterval = 60.0
            
            // Setup timeout
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self, task.isRunning else { return }
                task.terminate()
                self.secureLog("Command execution timed out after \(commandTimeout) seconds", privacy: .critical)
                self.showNotification(title: "Drift Warning", message: "Command execution timed out")
            }
            
            // Schedule timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + commandTimeout, execute: timeoutWorkItem)
            
            do {
                try task.run()
                
                // Add termination handler to capture output
                task.terminationHandler = { [weak self] process in
                    guard let self = self else { return }
                    // Cancel timeout since the process completed
                    timeoutWorkItem.cancel()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    
                    if process.terminationStatus != 0 {
                        if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                            self.secureLog("Command failed with status \(process.terminationStatus)", privacy: .critical)
                            
                            // Only show notification for actual errors, not just non-zero exits
                            if process.terminationStatus > 1 {
                                self.showNotification(
                                    title: "Drift Warning", 
                                    message: "Command completed with errors"
                                )
                            }
                        }
                    } else {
                        self.secureLog("Command executed successfully", privacy: .normal)
                    }
                }
            } catch {
                // Cancel timeout since there was an error starting the process
                timeoutWorkItem.cancel()
                self.secureLog("Failed to execute command: \(error.localizedDescription)", privacy: .critical)
                self.secureLog("Failed to execute command", privacy: .critical)
                self.showNotification(title: "Drift Error", message: "Failed to execute command: \(error.localizedDescription)")
            }
        }
    }
    
    /// Executes a folder action by opening the specified folder
    /// - Parameter path: Path to the folder
    private func executeFolderAction(_ path: String) {
        // Verify the path is not empty
        guard !path.isEmpty else {
            secureLog("Folder path is empty", privacy: .critical)
            showNotification(title: "Drift Error", message: "Invalid folder path")
            return
        }
        
        // Verify the folder exists
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        
        if exists && isDirectory.boolValue {
            secureLog("Opening folder", privacy: .sensitive)
            DispatchQueue.global(qos: .userInitiated).async {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            }
        } else {
            let errorMessage = exists ? "Path is not a directory" : "Directory does not exist"
            secureLog("\(errorMessage): \(path)", privacy: .critical)
            showNotification(title: "Drift Error", message: errorMessage)
        }
    }
    
    private func resetConfig() {
        config = DriftConfiguration(
            settings: GlobalSettings(
                quickSwitchEnabled: true,
                leaderKey: "space",
                leaderModifiers: KeyModifiers(command: false, option: true, control: true, shift: false),
                statusEmojis: StatusEmojis(normal: "⚡️", active: "🚀", disabled: "⚠️"),
                useSystemIcons: true
            ),
            actions: []
        )
        
        // Get ConfigManager to save the config
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.configManager.saveConfig()
        }
    }
}

