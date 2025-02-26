# Drift

Drift is a native macOS menu bar application designed to enhance productivity through customizable keyboard shortcuts and quick actions. It provides a leader key-based system for executing various actions with simple key sequences.

## Features

- **Leader Key System**: Use a customizable leader key (with modifiers) to activate leader mode, then type sequences to trigger actions
- **Quick Application Switching**: Rapidly switch between applications with custom key bindings
- **Status Bar Integration**: Unobtrusive menu bar icon with visual feedback when in leader mode
- **Customizable Configuration**: Define your own key sequences for various actions
- **Accessibility Features**: Seamless integration with macOS accessibility framework
- **Privacy-Focused**: Secure logging with privacy protection for sensitive information
- **Lightweight & Efficient**: Low system resource usage, designed for minimal overhead

## Requirements

- macOS 12.0+
- Xcode 14.0+ (for development only)
- Swift 5.7+ (for development only)

## Installation

### Option 1: Download the Release

1. Go to the [Releases](https://github.com/braydenm/Drift/releases) page
2. Download the latest version of Drift.app
3. Move to your Applications folder
4. Launch the app

### Option 2: Build from Source

1. Clone the repository
```bash
git clone https://github.com/braydenm/Drift.git
```

2. Open the Xcode project
```bash
cd Drift
open Drift.xcodeproj
```

3. Build the app (⌘+B) and run (⌘+R) in Xcode

## Usage

### First Launch

When you first launch Drift, it will:
1. Request accessibility permissions (required to monitor keyboard input)
2. Add itself to your login items (optional, can be disabled in preferences)
3. Show a brief introduction to the leader key system

### Basic Controls

- **Default Leader Key**: `⌥ + Space` (Option + Space)
- **Enter Leader Mode**: Press the leader key combination
- **Exit Leader Mode**: Press `Escape` or wait for the timeout
- **Access Menu**: Click the Drift icon in the menu bar

### Example Key Sequences

After pressing the leader key (⌥ + Space by default):

- `s` → Open System Preferences
- `c` → Open Calculator
- `m` → Open Mail
- `b` → Open default web browser

You can customize these sequences in the configuration.

## Configuration

Drift uses a configuration file located at `~/Library/Application Support/Drift/config.json`. You can:

1. Edit this file directly
2. Use the configuration UI (accessible from the menu bar icon)

Example configuration:
```json
{
  "globalSettings": {
    "quickSwitchEnabled": true,
    "leaderKey": "space",
    "leaderModifiers": {
      "command": false,
      "option": true,
      "control": false,
      "shift": false
    }
  },
  "keySequences": [
    {
      "sequence": "c",
      "action": "openApplication",
      "target": "Calculator"
    }
  ]
}
```

## Project Structure

- `Drift/` - Main application source code
  - `AppDelegate.swift` - App lifecycle and event handling
  - `DriftApp.swift` - SwiftUI app entry point
- `Drift/Managers/` - Core functionality managers
  - `AppManager.swift` - Keyboard input processing and action execution
  - `ConfigManager.swift` - Configuration loading and saving
  - `HotKeyManager.swift` - Global hotkey registration
  - `StatusBarController.swift` - Menu bar interface
  - `NotificationManager.swift` - User notification handling
- `Drift/Models/` - Data models
  - `Config.swift` - Configuration data structures
- `Drift/Utils/` - Utility functions and helpers

## Troubleshooting

### Common Issues

1. **Accessibility Permissions**
   If Drift isn't responding to your keyboard shortcuts, verify that it has accessibility permissions in System Preferences → Security & Privacy → Privacy → Accessibility.

2. **Menu Bar Icon Missing**
   If the menu bar icon disappears, try restarting the app or checking if it's hidden by the system.

3. **Configuration Not Saving**
   Ensure Drift has write permissions to `~/Library/Application Support/Drift/`.

## Contributing

Contributions are welcome! To contribute:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please ensure your code follows the project's style guidelines and includes appropriate tests.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- [HotKey](https://github.com/soffes/HotKey) - Swift library for system-wide keyboard shortcuts
- The Vim and Emacs communities for inspiration on modal editing and leader key concepts

## Contact

Brayden Moon

[@0x1f99d](https://x.com/0x1f99d) on X 