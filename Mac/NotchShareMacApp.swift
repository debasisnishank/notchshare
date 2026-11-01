import SwiftUI
import AppKit
import UserNotifications
import NotchShareKit

enum NotchState { case idle, ready, transferring, done }

final class NotchModel: ObservableObject {
    @Published var state: NotchState = .idle
    @Published var fileName = ""
    @Published var progress: Double = 0
}

final class MacController: ObservableObject {
    let model = NotchModel()
    let peers = PeerSession(role: .mac, displayName: Host.current().localizedName ?? "Mac")
    let transfer: FileTransferManager
    let overlay: NotchOverlayWindow
    let beacon = BLEBeacon()
    @Published var connectedName: String?
    private var progressObs: NSKeyValueObservation?
    private var lastState: NotchState = .idle

    init() {
        transfer = FileTransferManager(peerSession: peers)
        overlay = NotchOverlayWindow(model: model)
        peers.onPeerConnected = { [weak self] p in DispatchQueue.main.async { self?.connectedName = p.displayName } }
        peers.onPeerDisconnected = { [weak self] _ in DispatchQueue.main.async { self?.connectedName = nil } }
        peers.onMessage = { [weak self] msg, _ in
            DispatchQueue.main.async {
                switch msg.kind {
                case .near: self?.model.state = .ready; Self.play("Tink")
                case .far: if self?.model.state == .ready { self?.model.state = .idle }
                default: break
                }
            }
        }
        peers.onResourceStarted = { [weak self] name, _, progress in
            DispatchQueue.main.async {
                self?.model.fileName = name
                self?.model.progress = 0
                self?.model.state = .transferring
                self?.progressObs = progress.observe(\.fractionCompleted) { p, _ in
                    DispatchQueue.main.async { self?.model.progress = p.fractionCompleted }
                }
            }
        }
        transfer.onFileReceived = { [weak self] url in self?.finish(url) }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        NotificationCenter.default.addObserver(forName: .notchZoneEntered, object: nil, queue: .main) { [weak self] _ in
            self?.triggerReady()
        }
        peers.start()
        beacon.start()
    }

    /// Notch zone entered (UWB, BLE fallback, or the debug menu item).
    func triggerReady() {
        model.state = .ready
        peers.send(NotchShareMessage(.ready))
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.model.state == .ready { self?.model.state = .idle }
        }
    }

    static func play(_ name: String) { NSSound(named: NSSound.Name(name))?.play() }

    private func notifyReceived(_ url: URL) {
        let c = UNMutableNotificationContent()
        c.title = "Received from \(connectedName ?? "iPhone")"
        c.body = url.lastPathComponent
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    private func finish(_ url: URL) {
        model.progress = 1
        Self.play("Glass")
        notifyReceived(url)
        model.state = .done
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.model.state = .idle }
    }
}

@main
struct NotchShareMacApp: App {
    @StateObject private var controller = MacController()

    var body: some Scene {
        MenuBarExtra("NotchShare", systemImage: "iphone.radiowaves.left.and.right") {
            Text(controller.connectedName.map { "Connected: \($0)" } ?? "Waiting for iPhone…")
            Divider()
            Button("Simulate notch trigger") { controller.triggerReady() }
            Button("Open received files") {
                let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("NotchShare")
                NSWorkspace.shared.open(url)
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
