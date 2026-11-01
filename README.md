# NotchShare

Hold your iPhone near your Mac's notch to send files to it.

- `NotchShareKit/` – shared Swift package (Multipeer, file transfer, BLE proximity, Live Activity attributes)
- `iOS/` – iPhone app (document picker, BLE scanner, Live Activity controller)
- `Widget/` – Dynamic Island / Lock Screen Live Activity extension
- `Mac/` – menu-bar app with the notch glow overlay
- `docs/` – implementation plan

## Build

```sh
brew install xcodegen
xcodegen generate
open NotchShare.xcodeproj
```

Set your signing team for each target. Proximity uses BLE RSSI (the Mac has no public NearbyInteraction API); calibrate `BLEProximityScanner.nearThreshold` on device.
