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
- Optional notification when a cartridge is running low
- Privacy policy and a support link in Settings
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

## Bluetooth

The app offers the built-in Demo Diffuser alongside real diffusers found over Bluetooth
(`CombinedDiffuserService`). Bluetooth starts only when the user first searches for a diffuser,
so iOS asks for permission then.

```
Screens ─ DiffuserStore ─ DiffuserService
                           ├─ SimulatedDiffuserService      (Demo Diffuser)
                           └─ BluetoothDiffuserService      (requests, replies, timeouts)
                                ├─ DiffuserCodec            (requests ⇄ bytes)
                                └─ BLETransport             (bytes ⇄ radio)
                                     ├─ CoreBluetoothTransport  (real iPhone)
                                     └─ MockBLETransport        (tests)
```

`DiffuserStore` reconnects automatically when a connection drops (five attempts, 1 to 16 seconds
apart), waits while Bluetooth is off and reconnects when it comes back on, and shows a notice
with a link to Settings when Bluetooth is off or not allowed.

**Placeholders to replace with the manufacturer's protocol document:**

- `Services/Bluetooth/BLETransport.swift`, `DiffuserBLEIdentifiers`: service and characteristic
  identifiers (currently the common Nordic UART Service).
- `Services/Bluetooth/PlaceholderDiffuserCodec.swift`: the byte format. Write a new
  `DiffuserCodec` for the real format and pass it to `BluetoothDiffuserService` in
  `AuraDriveApp.swift`.

### Firmware updates (OTA)

Details → Firmware update checks for, installs and follows an update. `FirmwareUpdateMachine`
(`Models/FirmwareUpdate.swift`) holds the allowed steps: checking, available, preparing,
transferring (with progress), verifying, then completed or failed with a reason. The firmware is
sent in chunks with a CRC-32 checksum, the diffuser checks it before installing, and the user can
cancel while it's being sent. The diffuser can't be controlled during an update.

**Placeholders:** `PlaceholderFirmwareSource` offers a made-up update (1.1.0) for the Demo Diffuser
only. Real firmware has to come from the manufacturer, and the update messages in
`PlaceholderDiffuserCodec` must be replaced with their update method.

**Not yet tested on hardware.** The simulator has no Bluetooth, so `CoreBluetoothTransport` is
only known to compile. Everything above it is tested against `MockBLETransport`. Still to do:
writing messages longer than the Bluetooth packet size, faster firmware transfer (the
placeholder waits for a reply after every 128-byte chunk), and reconnecting while the app is in
the background.

## Renaming the app

The name "AuraDrive" is a placeholder. To change only what users see, edit
`INFOPLIST_KEY_CFBundleDisplayName` in the target's build settings. To rename the project and
targets, use Xcode's rename (click the project name in the navigator).

## Still to do before release

- Bluetooth implementation of `DiffuserService` (see above)
- Replace the placeholder support address in `AuraDrive/App/AppLinks.swift`
- Replace the placeholder app icon (`scripts/generate_app_icon.py` draws the current one)
- Fill in and publish `docs/PRIVACY_POLICY.md`; complete `docs/APP_STORE_LISTING.md`
- Set the signing team and the real bundle identifier
