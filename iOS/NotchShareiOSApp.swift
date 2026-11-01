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
    @Published var rssi: Int?
    let ble = BLEProximityScanner()
    let live = LiveActivityController()
    private var bag = Set<AnyCancellable>()

    init() {
        transfer = FileTransferManager(peerSession: peers)
        peers.onPeerConnected = { [weak self] p in
            DispatchQueue.main.async { self?.macName = p.displayName; self?.status = "Connected to \(p.displayName)"; self?.live.arm(macName: p.displayName) }
        }
        peers.onPeerDisconnected = { [weak self] _ in
            DispatchQueue.main.async { self?.macName = nil; self?.status = "Searching for Mac…" }
        }
        peers.onMessage = { [weak self] msg, _ in
            DispatchQueue.main.async {
                switch msg.kind {
                case .ready: self?.showPicker = true
                case .ack: self?.status = "Delivered ✓"; self?.live.done()
                default: break
                }
            }
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
                self?.peers.send(NotchShareMessage(near ? .near : .far))
            }
        }
        let d = UserDefaults.standard
        if d.object(forKey: "nearThreshold") != nil { ble.nearThreshold = d.integer(forKey: "nearThreshold") }
        if d.object(forKey: "hysteresis") != nil { ble.hysteresis = d.integer(forKey: "hysteresis") }
        peers.start()
        ble.start()
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

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Image(systemName: "macbook.and.iphone").font(.system(size: 56))
                Text(c.status).font(.headline)
                if c.transfer.totalFiles > 0 {
                    ProgressView(value: c.transfer.fractionCompleted) {
                        Text("\(c.transfer.currentFileName) (\(c.transfer.currentIndex)/\(c.transfer.totalFiles))")
                            .font(.caption)
                    }.padding(.horizontal)
                }
                if let r = c.rssi { Text("RSSI \(r) dBm").font(.caption).foregroundStyle(.secondary) }
                if c.isNear {
                    Button("Send to Mac") { c.showPicker = true }
                        .buttonStyle(.borderedProminent).disabled(c.macName == nil)
                } else {
                    Text("Hold your iPhone near your Mac").foregroundStyle(.secondary)
                }
            }
            .padding()
            .onLongPressGesture(minimumDuration: 1) { c.showCalibration = true }
            .sheet(isPresented: $c.showCalibration) { CalibrationView(ble: c.ble) }
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
