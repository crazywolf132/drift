//
//  Extensions.swift
//  Drift
//
//  Created by Brayden Moon on 20/2/2025.
//

import Cocoa
import Foundation
import os.log

extension NSView {
    func firstSubview<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let view = subview as? T { return view }
            if let found = subview.firstSubview(ofType: type) { return found }
        }
        return nil
    }
}

// Logger extension for improved error reporting
extension OSLog {
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.drift.app"
    
    static let appLifecycle = OSLog(subsystem: subsystem, category: "appLifecycle")
    static let accessibility = OSLog(subsystem: subsystem, category: "accessibility")
    static let configuration = OSLog(subsystem: subsystem, category: "configuration")
    static let eventTap = OSLog(subsystem: subsystem, category: "eventTap")
    static let statusBar = OSLog(subsystem: subsystem, category: "statusBar")
}

// Debugging utility
func driftLog(_ message: String, type: OSLogType = .default, log: OSLog = .default) {
    os_log("%{public}@", log: log, type: type, message)
    #if DEBUG
    print("[Drift] \(message)")
    #endif
}

/**
 * Execute a function safely.
 * For non-throwing functions:
 * ```
 * safeExecute(operation: "Operation name") {
 *     // Your non-throwing code here
 * }
 * ```
 *
 * For throwing functions:
 * ```
 * safeExecuteThrowing(operation: "Operation name") {
 *     try someThrowingFunction()
 * }
 * ```
 */
func safeExecute(operation: String, log: OSLog = .default, action: () -> Void) {
    // Since action doesn't throw, we can just call it directly
    action()
}

/**
 * Execute a throwing function and handle any errors.
 * This will catch and log any errors thrown by the provided action.
 */
func safeExecuteThrowing(operation: String, log: OSLog = .default, action: () throws -> Void) {
    do {
        try action()
    } catch {
        driftLog("Error during \(operation): \(error.localizedDescription)", type: .error, log: log)
    }
}

// Safely execute a background task
func safeAsync(on queue: DispatchQueue = .main, after delay: TimeInterval = 0, execute work: @escaping () -> Void) {
    queue.asyncAfter(deadline: .now() + delay) {
        // Execute the work directly as it doesn't throw
        work()
    }
}
