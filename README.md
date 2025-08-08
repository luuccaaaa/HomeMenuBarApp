# HomeKit Menu Bar App

[![macOS](https://img.shields.io/badge/macOS-12.0+-blue.svg)](https://www.apple.com/macos/)
[![Xcode](https://img.shields.io/badge/Xcode-14.0+-green.svg)](https://developer.apple.com/xcode/)
[![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)](https://swift.org/)
[![License](https://img.shields.io/badge/License-GPL%20v3-yellow.svg)](LICENSE)

## Download

**Available on the Mac App Store:**

[![Download on the Mac App Store](https://developer.apple.com/app-store/marketing/guidelines/images/badge-download-on-the-mac-app-store.svg)](https://apps.apple.com/ch/app/homemenubar/id6749576769)


![App Store Banner](https://i.imgur.com/Q8l7WNY.jpeg)

Control your HomeKit accessories from the macOS menu bar. A responsive, low-overhead controller that feels native on macOS.



## Features

- **One-click control** for lights, switches, outlets, sensors, and scenes
- **Professional color controls** with HSV color wheel, brightness, and saturation
- **Auto-grouping by room** with live state updates and reachability indicators
- **Native macOS menu bar UX** with context-aware menu items
- **Robust architecture**: Mac Catalyst app + macOS bundle + Shared framework

## Quick Start

**Prerequisites:**
- macOS 12+ and Xcode 14+
- HomeKit home with accessories
- Grant HomeKit permissions on first run

**Build and run:**
```bash
git clone https://github.com/luuccaaaa/HomeMenuBar.git
cd HomeMenuBar
open HomeMenuBar.xcodeproj
```

Select the HomeMenuBar scheme and press Cmd+R. Grant HomeKit access when prompted.

## Usage

- Click the menu bar icon to view accessories grouped by room
- Toggle power, adjust brightness, and change colors for supported devices
- Scenes and room-level controls available in Settings

## Architecture

**Hybrid design:**
- **Mac Catalyst app**: HomeKit communication and coordination
- **macOSBridge bundle**: Native menu bar UI and AppKit rendering  
- **Shared module**: Protocols, types, and device state management

## Development

```bash
# Build
xcodebuild -project HomeMenuBar.xcodeproj -scheme HomeMenuBar -configuration Debug build
```

## Contributing

Fork, create a feature branch, and submit a PR. Follow Swift API Design Guidelines and add tests for critical logic.

## License

GPL v3 — see [LICENSE](LICENSE).
