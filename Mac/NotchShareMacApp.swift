import SwiftUI
import Combine
import AppKit
import UserNotifications
import NotchShareKit

enum NotchState { case idle, ready, dropTarget, sending, transferring, done }

final class NotchModel: ObservableObject {
    @Published var state: NotchState = .idle
    @Published var fileName = ""
    @Published var progress: Double = 0
    @Published var doneText = "Received"
}

final class MacController: ObservableObject {
    let model = NotchModel()
    let peers = PeerSession(role: .mac, displayName: Host.current().localizedName ?? "Mac")
    let transfer: FileTransferManager
    let overlay: NotchOverlayWindow
    let beacon = BLEBeacon()
    @Published var connectedName: String?
    private var progressObs: NSKeyValueObservation?
    private var acksPending = 0
    private var bag = Set<AnyCancellable>()

    init() {
        transfer = FileTransferManager(peerSession: peers)
        overlay = NotchOverlayWindow(model: model)
        overlay.onDrop = { [weak self] urls in self?.sendToPhone(urls) }
        transfer.$fractionCompleted.removeDuplicates().sink { [weak self] f in
            guard let self, self.model.state == .sending else { return }
            self.model.progress = f
        }.store(in: &bag)
        peers.onPeerConnected = { [weak self] p in
            DispatchQueue.main.async { self?.connectedName = p.displayName; self?.overlay.dropEnabled = true }
        }
        peers.onPeerDisconnected = { [weak self] _ in
            DispatchQueue.main.async { self?.connectedName = nil; self?.overlay.dropEnabled = false }
        }
        peers.onMessage = { [weak self] msg, _ in
            DispatchQueue.main.async {
                switch msg.kind {
                case .near: self?.model.state = .ready; Self.play("Tink")
                case .far: if self?.model.state == .ready { self?.model.state = .idle }
                case .ack: self?.sentAck()
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

    /// Mac -> iPhone. Used by the menu item and by dropping files on the notch.
    func sendToPhone(_ urls: [URL]) {
        guard let phone = peers.connectedPeers.first, !urls.isEmpty else { model.state = .idle; return }
        acksPending = urls.count
        model.fileName = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        model.progress = 0
        model.state = .sending
        transfer.send(files: urls, to: phone)
    }

    func chooseFilesToSend() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] r in
            if r == .OK { self?.sendToPhone(panel.urls) }
        }
    }

    private func sentAck() {
        guard model.state == .sending else { return }
        acksPending -= 1
        guard acksPending <= 0 else { return }
        model.progress = 1
        model.doneText = "Sent to \(connectedName ?? "iPhone")"
        Self.play("Glass")
        model.state = .done
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.model.state = .idle }
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
        model.doneText = "Received"
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
            Button("Send file to iPhone…") { controller.chooseFilesToSend() }
                .disabled(controller.connectedName == nil)
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
