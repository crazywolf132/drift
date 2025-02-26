# Drift

A powerful macOS productivity tool that enhances keyboard-driven workflows with custom keybindings and actions.

## Features

- Leader key sequences for triggering custom actions
- Quick application launching
- Command execution
- Customizable status bar indicator
- Configurable settings via a simple interface

## Requirements

- macOS 12.0+
- Xcode 13.0+ (for development)

## Installation

1. Download the latest release from the [Releases](https://github.com/crazywolf132/drift/releases) page.
2. Move the app to your Applications folder.
3. Launch Drift.
4. Grant the necessary Accessibility permissions when prompted.

## Usage

Drift works by intercepting key events and triggering actions based on configured key sequences.

### Configuration

Drift can be configured by modifying the configuration file.

### Key Concepts

- **Leader Mode**: Activated by pressing the leader key, this mode allows subsequent keystrokes to trigger actions.
- **Actions**: Commands or applications that are executed when their associated key sequence is pressed.

## Development

### Building from Source

1. Clone the repository:
   ```
   git clone https://github.com/crazywolf132/drift.git
   ```
2. Open `Drift.xcodeproj` in Xcode.
3. Build and run the project.

### Project Structure

- `Managers/`: Contains controller classes for the app's functionality
- `Models/`: Contains data models
- `Utils/`: Utility classes and extensions
- `Views/`: UI components

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by similar tools like [Karabiner-Elements](https://karabiner-elements.pqrs.org/) and Vim's leader key concept. 