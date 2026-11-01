# NotchShare — Implementation Plan

Nov 1, 2026 · @Dev

## Architecture overview

Two apps, one shared experience. The iPhone measures its own proximity to the Mac over UWB; the Mac's Notch Zone Detector fires when distance drops below 20 cm at the right angle; a Multipeer trigger message prompts the iPhone to open its file picker; the file then travels back over MultipeerConnectivity.

&#91;embedded content: 4 components per device · 3 inter-device connections\]

Three inter-device channels do the work: UWB ranging tells the Mac where the iPhone is (bidirectional, accent), a Multipeer trigger message goes from Mac to iPhone when the notch zone is entered (dashed), and the file payload flows iPhone to Mac (solid arrow).

## Phase 1 — Xcode workspace scaffold

Create a single `.xcworkspace` containing three targets. Shared code lives in a local Swift Package so both apps import it without duplication.

| Target | Type | Min OS |
| --- | --- | --- |
| `NotchShareKit` | Swift Package (local) | iOS 16 / macOS 13 |
| `NotchShare iOS` | iOS App (SwiftUI) | iOS 16 |
| `NotchShare Mac` | macOS App (SwiftUI, **not** Catalyst) | macOS 13 |

**What goes in `NotchShareKit`**

- `PeerSession.swift` — shared Multipeer session logic (advertise, browse, connect)
- `FileTransferManager.swift` — send/receive file payloads, progress callbacks
- `NotchShareMessage.swift` — Codable message envelope (`ready`, `cancel`, `ack`)

**Entitlements required** (apply for both targets)

- `com.apple.developer.nearby-interaction` — requires Apple approval via the NI entitlement request form before submission
- `com.apple.security.network.client` + `server`
- `NSLocalNetworkUsageDescription` in Info.plist
- `NSBluetoothAlwaysUsageDescription` in Info.plist

* `com.apple.developer.nearby-interaction.background` — required for UWB ranging to continue when the app is backgrounded (iOS 18.4+). Also requires a Live Activity to be active at the time. Apply alongside the standard NI entitlement.

**Key `Package.swift` dependencies**

```swift
dependencies: [
    // no external deps — NearbyInteraction and
    // MultipeerConnectivity are system frameworks
]
```

Both apps link system frameworks directly: `NearbyInteraction`, `MultipeerConnectivity`, and `ActivityKit` (iOS only).

## Phase 2 — Peer discovery (MultipeerConnectivity)

Both apps run as advertiser **and** browser simultaneously. This is the bootstrap layer — no UWB until a Multipeer session exists, because UWB tokens are exchanged over it.

```swift
// In NotchShareKit / PeerSession.swift
let serviceType = "notchshare"  // max 15 chars, lowercase, hyphens ok
let peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
let advertiser = MCNearbyServiceAdvertiser(peer: peerID,
    discoveryInfo: ["role": "mac"],  // or "iphone"
    serviceType: serviceType)
let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
```

**Connection handshake**

1. Browser finds peer → auto-invites (no UI prompt needed for same-owner devices)
2. `MCSessionDelegate.session(_:peer:didChangeState:)` fires with `.connected`
3. Both sides immediately send their `NIDiscoveryToken` wrapped in a `NotchShareMessage.tokenExchange` payload
4. Receipt of the peer's token is the signal to start the NI session (Phase 3)

**Data encoding** — use `JSONEncoder` on `NotchShareMessage`; send via `MCSession.send(_:toPeers:with:)` using `.reliable` mode for control messages and `.sendResource(at:)` for actual files.

**Key gotcha** — `MCSession` must be kept alive in a long-lived object (an `@Observable` or singleton). If it's released, the session drops silently.

## Phase 3 — UWB ranging and notch-zone detection

Once both sides have each other's `NIDiscoveryToken`, create an `NISession` on each device and start ranging.

```swift
// Mac side — NearbyInteractionManager.swift
func startSession(with peerToken: NIDiscoveryToken) {
    let config = NINearbyPeerConfiguration(peerToken: peerToken)
    niSession.run(config)
}

func session(_ session: NISession, didUpdate objects: [NINearbyObject]) {
    guard let peer = objects.first,
          let distance = peer.distance,
          let direction = peer.direction else { return }

    let isClose     = distance < 0.20            // within 20 cm
    let isTopCentre = direction.y > 0.70         // aimed upward
                   && abs(direction.x) < 0.30    // and centred horizontally

    if isClose && isTopCentre {
        NotificationCenter.default.post(name: .notchZoneEntered, object: nil)
    }
}
```

**How the direction vector maps to the notch**

- `direction.y` is the elevation component (positive = iPhone camera facing Mac's top edge)
- `direction.x` is the azimuth (negative = left, positive = right)
- Threshold `y > 0.70` with `|x| < 0.30` carves out roughly the top-centre 30° cone — where the notch is
- These values need **calibration on real devices**; expose them as sliders in a debug build

**Important Mac-specific constraint** — `NINearbyPeerConfiguration` is available on macOS 13+ on Apple Silicon only. Call `NISession.deviceCapabilities.supportsPreciseDistanceMeasurement` at launch and gate the feature gracefully.

**Debouncing** — add a 300 ms debounce before firing the notch trigger to avoid flickering when the iPhone wobbles near the threshold.

**Background UWB (iOS 18.4+)** — by default, `NISession` is suspended the moment the app leaves the foreground. With the `com.apple.developer.nearby-interaction.background` entitlement and an **active Live Activity**, UWB ranging continues in the background. This is the architecture to target: start a persistent "armed" Live Activity at app launch, keep it running, and UWB stays alive even with the screen off. Without iOS 18.4+, the app must be foregrounded for the gesture to work.

## Phase 4 — File transfer flow

The full round-trip from notch trigger to file landing on Mac:

1. **Mac detects notch zone** → sends `NotchShareMessage.ready` over Multipeer to iPhone
2. **iPhone receives `.ready`** → presents `UIDocumentPickerViewController` (supports multi-file)
3. **User picks file(s)** → iPhone calls `startAccessingSecurityScopedResource()`, copies to a temp URL
4. **iPhone sends file** via `MCSession.sendResource(at:withName:toPeer:withCompletionHandler:)` — this streams and reports progress via `NSProgress`
5. **Mac receives** in `session(_:didFinishReceivingResourceWithName:fromPeer:at:error:)` → moves from temp URL to `~/Downloads/NotchShare/`
6. **Mac sends `.ack`** → iPhone ends the Live Activity

```swift
// iOS — FileTransferManager.swift
func send(fileURL: URL, to peer: MCPeerID) {
    let progress = session.sendResource(
        at: fileURL,
        withName: fileURL.lastPathComponent,
        toPeer: peer
    ) { error in
        // completion: error == nil means success
    }
    self.transferProgress = progress  // drive Dynamic Island
}

// macOS — FileTransferManager.swift
func session(_ session: MCSession,
             didFinishReceivingResourceWithName name: String,
             fromPeer: MCPeerID, at localURL: URL?, withError error: Error?) {
    guard let src = localURL, error == nil else { return }
    let dest = downloadsFolder.appendingPathComponent(name)
    try? FileManager.default.moveItem(at: src, to: dest)
    // post .ack back to iPhone
}
```

**Multiple files** — wrap each `sendResource` call sequentially; use a queue so the Live Activity progress reflects the current file index out of total.

## Phase 5 — Dynamic Island Live Activity (iOS)

The Live Activity does **two jobs**, not one. Job one: keep the app alive in the background so UWB keeps ranging (the "armed" state). Job two: show transfer progress once a file is in flight. Design both states upfront.

```swift
// NotchShareActivityAttributes.swift (in NotchShareKit, iOS only)
import ActivityKit

struct NotchShareActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var fileName: String
        var progress: Double      // 0.0 – 1.0
        var totalFiles: Int
        var currentFileIndex: Int
    }
    var macName: String
}
```

**Lifecycle**

```swift
// Start when Mac sends .ready
let activity = try Activity<NotchShareActivityAttributes>.request(
    attributes: NotchShareActivityAttributes(macName: peerName),
    content: .init(state: initialState, staleDate: nil),
    pushType: nil)

// Update as NSProgress fraction changes
await activity.update(.init(state: updatedState, staleDate: nil))

// End on .ack received
await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(3))
```

**Widget views** — implement `DynamicIsland` in a Widget Extension target (separate from the app target). Three sizes needed:

- **Compact leading**: small file icon
- **Compact trailing**: percentage text
- **Expanded**: file name + progress bar + Mac name

**Requires** iPhone 14 Pro or later for Dynamic Island; older iPhones fall back to the Lock Screen Live Activity banner — still functional for background UWB.

**ContentState — two modes in one struct**

```swift
struct ContentState: Codable, Hashable {
    enum Mode: String, Codable { case armed, transferring, done }
    var mode: Mode
    // armed state
    var macName: String
    // transferring state
    var fileName: String?
    var progress: Double?      // 0.0 – 1.0
    var totalFiles: Int?
    var currentFileIndex: Int?
}
```

**Armed state** — start this immediately at app launch and keep it running all day. The Dynamic Island shows a tiny icon (compact leading) indicating readiness. This is what holds the background UWB ranging entitlement open. Update to `.transferring` when a file starts moving; update to `.done` and dismiss after 3 seconds on completion, then restart the armed state.

**Entry points** — because the Live Activity keeps the app backgrounded, users only need to launch the app once. Provide three quick-launch options so first launch is frictionless:

- **Action Button** (iPhone 15 Pro+): set to open NotchShare via a Shortcut
- **Control Center tile** (iOS 18+): a `ControlConfigurationIntent` that launches into armed state
- **Lock Screen widget**: a `.accessoryCircular` widget that deep-links the app

## Phase 6 — Mac notch UI overlay

A transparent, click-through `NSPanel` lives at the top centre of the screen, always on top, sized to the notch area (\~200 × 36 pt). It is invisible by default and animates in when the notch zone fires.

```swift
// NotchOverlayWindow.swift
class NotchOverlayWindow: NSPanel {
    init() {
        let screen = NSScreen.main!
        let w: CGFloat = 200
        let frame = CGRect(
            x: (screen.frame.width - w) / 2,
            y: screen.frame.height - 36,
            width: w, height: 36)
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level          = .screenSaver   // always on top
        isOpaque       = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }
}
```

**Glow animation** — use `CABasicAnimation` on the overlay view's shadow or a `SwiftUI` `.overlay` with `RoundedRectangle` pulsing `.opacity` from 0 → 1 → 0 on a 600 ms ease-in-out loop. Colour: accent blue while waiting, green on transfer start.

**States**

- `idle` — panel hidden, alpha 0
- `ready` — pulsing blue glow (iPhone in notch zone)
- `transferring` — steady green, shows file name in compact text
- `done` — brief green flash, then fade out over 800 ms

**No Dock icon needed** — set `LSUIElement = YES` in Info.plist to run the Mac app as a menu bar agent with no Dock presence.

## Hardware requirements and fallback

| Requirement | Full UWB mode | Fallback (BLE) |
| --- | --- | --- |
| iPhone | iPhone 11+ (U1/U2 chip) | Any iPhone with BLE |
| Mac | Apple Silicon M1+ | Any Mac with BLE |
| iOS | 16+ | 16+ |
| macOS | 13+ (Ventura) | 13+ |
| NI entitlement | Required | Not needed |

**BLE fallback logic** — if `NISession.deviceCapabilities.supportsPreciseDistanceMeasurement` returns `false`, switch to RSSI-based proximity via `CBCentralManager`. This only gives \~1–2 m accuracy, so instead of a notch-zone trigger, the app falls back to a manual tap: iPhone shows a "Send to Mac" button that appears when RSSI exceeds a threshold (roughly arm's-length distance).

**iOS 26 / U2 chip caveat** — Apple disabled `supportsDirectionMeasurement` on iPhone 15 Pro / 16 series on iOS 26. Distance still works, but direction (`azimuthDegrees` / `elevationDegrees`) returns `nil`. On these devices the notch-zone check degrades to distance-only: `distance < 0.20` alone, without the angle test. Less precise but still functional.

**Simulator** — `NearbyInteraction` returns no data in Simulator. All UWB testing requires two physical devices. Use the Multipeer-only path for simulator development (Phases 1–2 and 4 can be fully tested on Simulator).

## Testing milestones and build order

Build and test in this order — each milestone is independently verifiable before the next depends on it.

| # | Milestone | Devices needed | Can use Simulator |
| --- | --- | --- | --- |
| 1 | Multipeer peer discovery — both apps find each other and connect | 1 iPhone + Mac | Yes (two Simulator instances) |
| 2 | Message exchange — send/receive `NotchShareMessage` structs over Multipeer | 1 iPhone + Mac | Yes |
| 3 | File transfer — pick a file on iPhone, receive on Mac in Downloads | 1 iPhone + Mac | Yes |
| 4 | UWB ranging — print distance + direction to console | 1 iPhone 11+ + M1 Mac | **No** |
| 5 | Notch-zone trigger — console log fires when iPhone held near notch | 1 iPhone 11+ + M1 Mac | **No** |
| 6 | End-to-end — gesture triggers picker, file lands on Mac | 1 iPhone 11+ + M1 Mac | **No** |
| 7 | Dynamic Island — Live Activity updates during transfer | iPhone 14 Pro+ | **No** |
| 8 | Notch UI polish — glow animation, state transitions | M1 Mac | Yes (trigger manually) |

**Calibration session (Milestone 5)** — build a debug screen showing live `distance` and `direction` values. Hold the iPhone at the notch, record the vector values, and set the thresholds from real data rather than guesses. Budget 30–60 min for this.

**Background UWB test (add after Milestone 7)** — lock the iPhone screen with the armed Live Activity running, then slowly bring it toward the Mac notch. The trigger should still fire. If it doesn't, the background entitlement isn't wired up correctly. Common causes: Live Activity was dismissed before the lock, or the entitlement profile isn't included in the provisioning profile. This test requires a real iPhone 18.4+ build — Simulator will not reproduce it.

**iOS version matrix to test**

| iOS version | Background UWB | Direction vector | Notes |
| --- | --- | --- | --- |
| iOS 16–18.3 | No | Yes | App must be foregrounded |
| iOS 18.4+ | Yes (with entitlement + Live Activity) | Yes | Target version for background mode |
| iOS 26+ (U2 chip) | Yes | No (distance only) | Falls back to distance-only zone check |
