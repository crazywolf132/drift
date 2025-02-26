//
//  FileMonitor.swift
//  Drift
//
//  Created by Brayden Moon on 20/2/2025.
//

import Foundation

class FileMonitor {
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    
    deinit {
        stopMonitoring()
    }
    
    func startMonitoring(fileURL: URL, callback: @escaping () -> Void) {
        // Stop any existing monitoring first
        stopMonitoring()
        
        // Check if the file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("Unable to monitor file - it doesn't exist: \(fileURL.path)")
            return
        }
        
        // Open the file for monitoring
        fileDescriptor = open(fileURL.path, O_EVTONLY)
        if fileDescriptor == -1 {
            print("Unable to open file for monitoring: \(fileURL.path)")
            return
        }
        
        // Create and configure the dispatch source
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.global()
        )
        
        // Set up the event handler with proper error handling
        source?.setEventHandler { [weak self] in
            guard let _ = self else { return }
            
            // Execute the callback on the main thread
            DispatchQueue.main.async {
                callback()
            }
        }
        
        // Configure cancellation handler to clean up resources
        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
            }
            self?.fileDescriptor = -1
        }
        
        // Start monitoring
        source?.resume()
    }
    
    func stopMonitoring() {
        // Cancel the source if it exists
        if let source = source {
            if !source.isCancelled {
                source.cancel()
            }
            self.source = nil
        }
        
        // Close the file descriptor if it's open
        if fileDescriptor != -1 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }
}
