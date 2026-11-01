import Foundation
import CoreBluetooth

public enum NotchShareBLE {
    public static let serviceUUID = CBUUID(string: "6E7C5B10-4E53-4A41-9C0B-4E6F74636853")
}

/// Mac side: advertises the NotchShare service so iPhones can measure RSSI.
public final class BLEBeacon: NSObject, CBPeripheralManagerDelegate {
    private var manager: CBPeripheralManager?
    public override init() { super.init() }

    public func start() { manager = CBPeripheralManager(delegate: self, queue: nil) }
    public func stop() { manager?.stopAdvertising(); manager = nil }

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [NotchShareBLE.serviceUUID]])
    }
}

/// iPhone side: scans for the Mac beacon and reports a smoothed RSSI + near/far state.
public final class BLEProximityScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published public private(set) var rssi: Int?
    @Published public private(set) var isNear = false

    /// Enter "near" above this value, leave below `nearThreshold - hysteresis`. Calibrate on device.
    public var nearThreshold = -50
    public var hysteresis = 8
    public var onNearChanged: ((Bool) -> Void)?

    private var central: CBCentralManager?
    private var smoothed: Double?
    private var lastSeen = Date.distantPast
    private var timer: Timer?

    public override init() { super.init() }

    public func start() {
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "notchshare.central"])
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.lastSeen) > 3 else { return }
            self.set(near: false)   // beacon went silent
        }
    }

    public func stop() { central?.stopScan(); timer?.invalidate(); central = nil }

    public func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { return }
        c.scanForPeripherals(withServices: [NotchShareBLE.serviceUUID],
                             options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    public func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {}

    public func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let v = RSSI.doubleValue
        guard v < 0 else { return }          // 127 = unavailable
        lastSeen = Date()
        smoothed = smoothed.map { $0 * 0.7 + v * 0.3 } ?? v   // low-pass filter
        let r = Int(smoothed!.rounded())
        rssi = r
        if isNear { if r < nearThreshold - hysteresis { set(near: false) } }
        else if r > nearThreshold { set(near: true) }
    }

    private func set(near: Bool) {
        guard near != isNear else { return }
        isNear = near
        if !near { smoothed = nil }
        onNearChanged?(near)
    }
}
