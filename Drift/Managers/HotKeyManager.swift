//
//  HotKeyManager.swift
//  Drift
//
//  Created by Brayden Moon on 20/2/2025.
//

import AppKit
import HotKey

/// Manages global hotkeys for activating Drift functionality
/// Registers and handles keyboard shortcuts based on configuration
class HotKeyManager {
  
    /// Collection of registered hotkeys
    var hotKeys: [HotKey] = []
    
    /// Current configuration
    var config: DriftConfiguration? = nil
    
    /// Whether hotkeys are currently enabled
    var isEnabled: Bool = true
    
    /// Registers hotkeys based on the provided configuration
    /// - Parameter config: The configuration containing hotkey definitions
    func registerKeys(config: DriftConfiguration) {
        print("Registering keys...")
        self.config = config
        print("Config: \(config)")
        
        for mapping in config.actions {
            
            print("Mapping key: \(mapping)")
            
            switch mapping {
            case .action(let action):
                if let firstChar = action.key.first, 
                   let keyCode = HotKeyManager.keyFromCharacter(firstChar) {
                    let hotKey = HotKey(key: keyCode, modifiers: [.command, .control])
                    hotKey.keyDownHandler = {
                        print("Running....")
                    }
                    hotKeys.append(hotKey)
                }
            case .group(_):
                break
            }
        }
    }
    
    /// Convert a character (for example, "T") into the corresponding HotKey Key.
    static func keyFromCharacter(_ char: Character) -> Key? {
        switch char.lowercased() {
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        case "i": return .i
        case "j": return .j
        case "k": return .k
        case "l": return .l
        case "m": return .m
        case "n": return .n
        case "o": return .o
        case "p": return .p
        case "q": return .q
        case "r": return .r
        case "s": return .s
        case "t": return .t
        case "u": return .u
        case "v": return .v
        case "w": return .w
        case "x": return .x
        case "y": return .y
        case "z": return .z
        case "space": return .space
        case "return", "enter": return .return
        case "tab": return .tab
        case "escape", "esc": return .escape
        case "delete", "backspace": return .delete
        case "0": return .zero
        case "1": return .one
        case "2": return .two
        case "3": return .three
        case "4": return .four
        case "5": return .five
        case "6": return .six
        case "7": return .seven
        case "8": return .eight
        case "9": return .nine
        default: return nil
        }
    }
}
