# AuraDrive (working title)

iOS app for controlling a car fragrance diffuser. Native SwiftUI, English only.

> **Demo mode:** this version controls a built-in simulated diffuser. Real Bluetooth control
> needs the diffuser manufacturer's protocol document; see "Connecting real hardware" below.

## What the app does

- Welcome screen on first launch
- Add a diffuser (search, then tap to add), rename it, or forget it
- Power on/off and intensity levels 1–5
- Interval mode (run for X seconds, pause for Y seconds)
- Sleep timer (15 minutes to 2 hours)
- Fragrance level with a low-cartridge warning and a reset after replacing the cartridge
- Settings are saved on the phone between launches

## Requirements

- Xcode 16 or later
- iOS 17.0+ deployment target, iPhone only
- Swift 6 language mode (strict concurrency)

## Getting started

1. Open `AuraDrive.xcodeproj` in Xcode.
2. Select the **AuraDrive** target → *Signing & Capabilities*, choose your team, and change the
   bundle identifier (`com.yourcompany.auradrive` is a placeholder).
3. Run the **AuraDrive** scheme on a simulator or device. Press **⌘U** to run the tests.

## Project structure

```
AuraDrive/
  App/                  App entry point and root navigation
  Models/               Diffuser, its settings and commands
  Services/             DiffuserStore (app state), DiffuserService (link to the hardware),
                        the simulated diffuser, and on-device storage
  Features/             One folder per screen: Welcome, DiffuserList, AddDiffuser, Control, Settings
  DesignSystem/
    Theme/              Colour, typography and spacing tokens
    Components/         Reusable, accessible UI components (buttons, cards, badges)
    Accessibility/      Accessibility identifiers and helpers (e.g. Reduce Motion)
  Resources/            Assets.xcassets (app icon, brand and status colours)
AuraDriveTests/         Unit tests (Swift Testing): app logic and WCAG colour-contrast checks
AuraDriveUITests/       UI tests (XCTest): the main user flow and Xcode accessibility audits
docs/ACCESSIBILITY.md   Accessibility rules every screen must follow
scripts/                generate_project.rb rebuilds AuraDrive.xcodeproj from the folders above
.github/workflows/      Builds the app and runs all tests on every pull request
```

## Connecting real hardware

Every screen talks to the `DiffuserService` protocol, never to the hardware directly.
`SimulatedDiffuserService` is the only implementation today. To support a real diffuser, add a
CoreBluetooth implementation of `DiffuserService` and pass it to `DiffuserStore` in
`AuraDriveApp.swift`. No screen needs to change. This needs the device's Bluetooth protocol
document (service and characteristic UUIDs, command format) and a test unit.

## Renaming the app

The name "AuraDrive" is a placeholder. To change only what users see, edit
`INFOPLIST_KEY_CFBundleDisplayName` in the target's build settings. To rename the project and
targets, use Xcode's rename (click the project name in the navigator).

## Still to do before release

- App icon (1024 × 1024) in `Assets.xcassets/AppIcon`
- Bluetooth implementation of `DiffuserService` (see above)
- Privacy policy URL and App Store listing
