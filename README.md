# AuraDrive (working title)

iOS app for controlling a Bluetooth car fragrance diffuser. Native SwiftUI, English only.

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
  Features/             One folder per feature (Welcome, later Pairing, Control, Schedules…)
  DesignSystem/
    Theme/              Colour, typography and spacing tokens
    Components/         Reusable, accessible UI components (buttons, cards, badges)
    Accessibility/      Accessibility identifiers and helpers (e.g. Reduce Motion)
  Resources/            Assets.xcassets (app icon, brand and status colours)
AuraDriveTests/         Unit tests (Swift Testing), incl. WCAG colour-contrast checks
AuraDriveUITests/       UI tests (XCTest), incl. Xcode accessibility audits
docs/ACCESSIBILITY.md   Accessibility rules every screen must follow
```

## Renaming the app

The name "AuraDrive" is a placeholder. To change only what users see, edit
`INFOPLIST_KEY_CFBundleDisplayName` in the target's build settings. To rename the project and
targets, use Xcode's rename (click the project name in the navigator).

## Still to do before release

- App icon (1024 × 1024) in `Assets.xcassets/AppIcon`
- Bluetooth layer (CoreBluetooth) once the device protocol document is available
