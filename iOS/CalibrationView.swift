import SwiftUI
import NotchShareKit

/// Debug screen: live RSSI + sliders for the near/far thresholds (persisted).
struct CalibrationView: View {
    @ObservedObject var ble: BLEProximityScanner
    @AppStorage("nearThreshold") private var near = -50.0
    @AppStorage("hysteresis") private var hyst = 8.0

    var body: some View {
        Form {
            Section("Live") {
                LabeledContent("RSSI", value: ble.rssi.map { "\($0) dBm" } ?? "—")
                LabeledContent("State", value: ble.isNear ? "Near" : "Far")
            }
            Section("Near threshold: \(Int(near)) dBm") {
                Slider(value: $near, in: -90 ... -20, step: 1)
            }
            Section("Hysteresis: \(Int(hyst)) dB") {
                Slider(value: $hyst, in: 2 ... 20, step: 1)
            }
            Text("Hold the iPhone at the Mac's notch, note the RSSI, then set the threshold just below it.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onChange(of: near) { ble.nearThreshold = Int($0) }
        .onChange(of: hyst) { ble.hysteresis = Int($0) }
        .onAppear { ble.nearThreshold = Int(near); ble.hysteresis = Int(hyst) }
    }
}
