import SwiftUI
import AppKit
import NotchShareKit

enum NotchState { case idle, ready, transferring, done }

final class NotchModel: ObservableObject {
    @Published var state: NotchState = .idle
    @Published var fileName = ""
}

final class MacController: ObservableObject {
    let model = NotchModel()
    let peers = PeerSession(role: .mac, displayName: Host.current().localizedName ?? "Mac")
    let transfer: FileTransferManager
    let overlay: NotchOverlayWindow
    let beacon = BLEBeacon()
    @Published var connectedName: String?

    init() {
        transfer = FileTransferManager(peerSession: peers)
        overlay = NotchOverlayWindow(model: model)
        peers.onPeerConnected = { [weak self] p in DispatchQueue.main.async { self?.connectedName = p.displayName } }
        peers.onPeerDisconnected = { [weak self] _ in DispatchQueue.main.async { self?.connectedName = nil } }
        peers.onMessage = { [weak self] msg, _ in
            DispatchQueue.main.async {
                switch msg.kind {
                case .near: self?.model.state = .ready
                case .far: if self?.model.state == .ready { self?.model.state = .idle }
                default: break
                }
            }
        }
        peers.onResourceStarted = { [weak self] name, _, _ in
            DispatchQueue.main.async { self?.model.fileName = name; self?.model.state = .transferring }
        }
        transfer.onFileReceived = { [weak self] _ in self?.finish() }
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

    private func finish() {
        model.state = .done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.model.state = .idle }
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
