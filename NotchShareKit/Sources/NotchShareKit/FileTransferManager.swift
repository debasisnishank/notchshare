import Foundation
import MultipeerConnectivity

/// Sends files (iPhone) and receives them (Mac) over `PeerSession`.
public final class FileTransferManager: ObservableObject {
    @Published public private(set) var currentIndex = 0
    @Published public private(set) var totalFiles = 0
    @Published public private(set) var currentFileName = ""
    @Published public private(set) var fractionCompleted: Double = 0

    public var onQueueFinished: (() -> Void)?
    public var onFileReceived: ((URL) -> Void)?

    private let peerSession: PeerSession
    private var queue: [URL] = []
    private var observation: NSKeyValueObservation?

    public init(peerSession: PeerSession, receiveFolder: URL? = nil) {
        self.peerSession = peerSession
        #if os(macOS)
        let folder = receiveFolder ?? FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotchShare", isDirectory: true)
        #else
        let folder = receiveFolder ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchShareReceived", isDirectory: true)
        #endif
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        peerSession.onResourceReceived = { [weak self] name, _, localURL, error in
            guard let self, let src = localURL, error == nil else { return }
            let dest = Self.uniqueURL(in: folder, name: name)
            do {
                try FileManager.default.moveItem(at: src, to: dest)
                DispatchQueue.main.async { self.onFileReceived?(dest) }
                self.peerSession.send(NotchShareMessage(.ack))
            } catch { print("NotchShare: move failed: \(error)") }
        }
    }

    // MARK: Send (iPhone)

    /// Queue files (security-scoped URLs from the document picker are copied to temp first).
    public private(set) var isBusy = false

    public func send(files: [URL], to peer: MCPeerID) {
        let temps = files.compactMap(Self.copyToTemp)   // copies synchronously
        guard !temps.isEmpty else { return }
        DispatchQueue.main.async {
            if self.isBusy {                      // append to the running queue
                self.queue += temps
                self.totalFiles += temps.count
                return
            }
            self.isBusy = true
            self.queue = temps
            self.totalFiles = temps.count
            self.currentIndex = 0
            self.sendNext(to: peer)
        }
    }

    private func sendNext(to peer: MCPeerID) {
        guard !queue.isEmpty else {
            isBusy = false
            DispatchQueue.main.async { self.onQueueFinished?() }
            return
        }
        let url = queue.removeFirst()
        currentIndex += 1
        currentFileName = url.lastPathComponent
        fractionCompleted = 0
        let progress = peerSession.session.sendResource(
            at: url, withName: url.lastPathComponent, toPeer: peer
        ) { [weak self] error in
            try? FileManager.default.removeItem(at: url)
            if let error { print("NotchShare: send failed: \(error)") }
            DispatchQueue.main.async { self?.sendNext(to: peer) }
        }
        observation = progress?.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async { self?.fractionCompleted = p.fractionCompleted }
        }
    }

    private static func copyToTemp(_ url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let target = dest.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch { return nil }
    }

    private static func uniqueURL(in folder: URL, name: String) -> URL {
        var url = folder.appendingPathComponent(name)
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}
