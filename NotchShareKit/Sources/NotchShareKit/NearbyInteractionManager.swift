import Foundation
#if os(iOS)
import NearbyInteraction
import simd


/// UWB ranging + notch-zone detection. Thresholds are mutable for on-device calibration.
public final class NearbyInteractionManager: NSObject, ObservableObject, NISessionDelegate {
    @Published public private(set) var distance: Float?
    @Published public private(set) var direction: SIMD3<Float>?
    @Published public private(set) var supported: Bool

    public var maxDistance: Float = 0.20
    public var minY: Float = 0.70
    public var maxAbsX: Float = 0.30
    public var debounce: TimeInterval = 0.3
    /// Fires on the main queue after the zone has held for `debounce` seconds.
    public var onZoneEntered: (() -> Void)?

    private var session: NISession?
    private var zoneSince: Date?
    private var fired = false
    private var supportsDirection: Bool

    public override init() {
        let caps = NISession.deviceCapabilities
        supported = caps.supportsPreciseDistanceMeasurement
        supportsDirection = caps.supportsDirectionMeasurement
        super.init()
    }

    /// Local discovery token to send to the peer. Creates the session.
    public func makeLocalToken() -> Data? {
        guard supported else { return nil }
        let s = NISession()
        s.delegate = self
        session = s
        guard let token = s.discoveryToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    public func start(withPeerTokenData data: Data) {
        guard supported,
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
        else { return }
        if session == nil { _ = makeLocalToken() }
        session?.run(NINearbyPeerConfiguration(peerToken: token))
    }

    public func stop() { session?.invalidate(); session = nil; distance = nil; direction = nil }

    public func session(_ session: NISession, didUpdate objects: [NINearbyObject]) {
        guard let peer = objects.first else { return }
        distance = peer.distance
        direction = peer.direction
        evaluate()
    }

    public func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject],
                        reason: NINearbyObject.RemovalReason) {
        distance = nil; direction = nil; zoneSince = nil; fired = false
    }

    private func evaluate() {
        guard let d = distance else { return }
        var inZone = d < maxDistance
        if inZone, supportsDirection {
            // U2 devices on iOS 26 report no direction -> distance-only fallback.
            if let v = direction { inZone = v.y > minY && abs(v.x) < maxAbsX }
        }
        if !inZone { zoneSince = nil; fired = false; return }
        let since = zoneSince ?? Date()
        zoneSince = since
        if !fired, Date().timeIntervalSince(since) >= debounce {
            fired = true
            DispatchQueue.main.async {
                self.onZoneEntered?()
                NotificationCenter.default.post(name: .notchZoneEntered, object: nil)
            }
        }
    }
}

#endif
