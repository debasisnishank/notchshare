import SwiftUI
import UniformTypeIdentifiers
import Combine
import NotchShareKit

final class PhoneController: ObservableObject {
    let peers = PeerSession(role: .iphone, displayName: UIDevice.current.name)
    let transfer: FileTransferManager
    @Published var macName: String?
    @Published var showPicker = false
    @Published var status = "Searching for Mac…"
    @Published var isNear = false
    @Published var showCalibration = false
    @Published var showPhotos = false
    @Published var sharingEnabled = true
    @Published var received: [URL] = []
    @Published var showShare = false
    private var progressObs: NSKeyValueObservation?
    private var outboxToken: AnyObject?
    private var shareWork: DispatchWorkItem?
    @Published var rssi: Int?
    let ble = BLEProximityScanner()
    let live = LiveActivityController()
    private var bag = Set<AnyCancellable>()

    init() {
        transfer = FileTransferManager(peerSession: peers)
        peers.onPeerConnected = { [weak self] p in
            DispatchQueue.main.async { self?.macName = p.displayName; self?.status = "Connected to \(p.displayName)"; self?.live.arm(macName: p.displayName); self?.flushOutbox() }
        }
        peers.onPeerDisconnected = { [weak self] _ in
            DispatchQueue.main.async { self?.macName = nil; self?.status = "Searching for Mac…" }
        }
        peers.onMessage = { [weak self] msg, _ in
            DispatchQueue.main.async {
                switch msg.kind {
                case .ready: self?.showPicker = true
                case .ack:
                    self?.status = "Delivered ✓"; self?.live.done()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                default: break
                }
            }
        }
        peers.onResourceStarted = { [weak self] name, _, progress in
            DispatchQueue.main.async {
                self?.status = "Receiving \(name)…"
                self?.progressObs = progress.observe(\.fractionCompleted) { p, _ in
                    self?.live.transferring(file: name, progress: p.fractionCompleted, index: 1, total: 1)
                }
            }
        }
        transfer.onFileReceived = { [weak self] url in
            guard let self else { return }
            self.received.append(url)
            self.live.done()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.status = "Received \(self.received.count) file(s) ✓"
            // Wait briefly for further files, then offer one share sheet for the batch.
            self.shareWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.showShare = true }
            self.shareWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
        }
        transfer.onQueueFinished = { [weak self] in self?.status = "Waiting for Mac to confirm…" }
        transfer.$fractionCompleted.removeDuplicates().sink { [weak self] f in
            guard let self, self.transfer.totalFiles > 0 else { return }
            self.live.transferring(file: self.transfer.currentFileName, progress: f,
                                   index: self.transfer.currentIndex, total: self.transfer.totalFiles)
        }.store(in: &bag)
        ble.$rssi.receive(on: DispatchQueue.main).assign(to: &$rssi)
        ble.onNearChanged = { [weak self] near in
            DispatchQueue.main.async {
                self?.isNear = near
                if near {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if UserDefaults.standard.bool(forKey: "autoSendScreenshot") { self?.sendLatestScreenshot() }
                }
                self?.peers.send(NotchShareMessage(near ? .near : .far))
            }
        }
        let d = UserDefaults.standard
        if d.object(forKey: "nearThreshold") != nil { ble.nearThreshold = d.integer(forKey: "nearThreshold") }
        if d.object(forKey: "hysteresis") != nil { ble.hysteresis = d.integer(forKey: "hysteresis") }
        outboxToken = Outbox.observe { [weak self] in self?.flushOutbox() }
        live.endAll()   // clear any stale Live Activity left from a previous run
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.live.endAll() }
        peers.start()
        ble.start()
    }

    /// Master switch: stops Multipeer, Bluetooth scanning and the Live Activity.
    func setSharing(_ on: Bool) {
        sharingEnabled = on
        if on {
            status = "Searching for Mac…"
            peers.start(); ble.start()
        } else {
            peers.stop(); ble.stop()
            live.endAll()
            macName = nil; isNear = false; rssi = nil
            status = "Sharing is off"
        }
    }

    /// Send anything dropped into the Outbox by the share extension.
    func flushOutbox() {
        guard peers.connectedPeers.first != nil, let batch = Outbox.claim() else { return }
        status = "Sending \(batch.files.count) shared file(s)…"
        send(batch.files)                                   // copies synchronously
        try? FileManager.default.removeItem(at: batch.folder)
    }

    func sendLatestScreenshot() {
        guard peers.connectedPeers.first != nil, !transfer.isBusy else { return }
        ScreenshotFinder.latestUnsentScreenshot { [weak self] url, reason in
            DispatchQueue.main.async {
                if let url { self?.status = "Sending latest screenshot…"; self?.send([url]) }
                else if let reason { self?.status = reason }
            }
        }
    }

    func send(_ urls: [URL]) {
        guard let mac = peers.connectedPeers.first else { return }
        status = "Sending \(urls.count) file(s)…"
        transfer.send(files: urls, to: mac)
    }
}

@main
struct NotchShareiOSApp: App {
    @StateObject private var c = PhoneController()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("autoSendScreenshot") private var autoSend = false

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Image(systemName: "macbook.and.iphone").font(.system(size: 56))
                Text(c.status).font(.headline)
                Toggle("Sharing", isOn: Binding(get: { c.sharingEnabled }, set: { c.setSharing($0) }))
                    .padding(.horizontal, 24)
                if c.transfer.totalFiles > 0 {
                    ProgressView(value: c.transfer.fractionCompleted) {
                        Text("\(c.transfer.currentFileName) (\(c.transfer.currentIndex)/\(c.transfer.totalFiles))")
                            .font(.caption)
                    }.padding(.horizontal)
                }
                Toggle("Auto-send latest screenshot", isOn: $autoSend).padding(.horizontal, 24)
                Text("Sends a screenshot from the last 2 min when you reach the notch.")
                    .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 24)
                if let r = c.rssi { Text("RSSI \(r) dBm").font(.caption).foregroundStyle(.secondary) }
                if c.isNear {
                    HStack {
                        Button("Files") { c.showPicker = true }.buttonStyle(.borderedProminent)
                        Button("Photos") { c.showPhotos = true }.buttonStyle(.borderedProminent)
                    }.disabled(c.macName == nil)
                } else {
                    Text("Hold your iPhone near your Mac").foregroundStyle(.secondary)
                }
            }
            .padding()
            .onChange(of: scenePhase) { if $0 == .active { c.flushOutbox() } }
            .onLongPressGesture(minimumDuration: 1) { c.showCalibration = true }
            .sheet(isPresented: $c.showCalibration) { CalibrationView(ble: c.ble) }
            .sheet(isPresented: $c.showShare, onDismiss: { c.received = [] }) {
                ShareSheet(items: c.received)
            }
            .sheet(isPresented: $c.showPhotos) { PhotoPicker { c.send($0) } }
            .sheet(isPresented: $c.showPicker) {
                DocumentPicker { c.send($0) }
            }
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        vc.allowsMultipleSelection = true
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(_ f: @escaping ([URL]) -> Void) { onPick = f }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls) }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
