import Foundation

/// Folder shared (via an App Group) between a share extension and its main app.
/// The extension drops files here; the app sends them when it is connected.
public enum Outbox {
    /// Set per platform through the `NotchShareAppGroup` Info.plist key.
    public static var groupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "NotchShareAppGroup") as? String
    }
    static let darwinName = "com.notchshare.outbox.changed" as CFString

    public static var directory: URL? {
        guard let id = groupID,
              let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        let dir = base.appendingPathComponent("Outbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Called by the share extension.
    @discardableResult
    public static func add(fileAt src: URL) -> Bool {
        guard let dir = directory else { return false }
        let fm = FileManager.default
        let staging = dir.appendingPathComponent(".tmp-" + UUID().uuidString, isDirectory: true)
        let final = dir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: staging.appendingPathComponent(src.lastPathComponent))
            try fm.moveItem(at: staging, to: final)   // atomic: never half-written
            return true
        } catch { try? fm.removeItem(at: staging); return false }
    }

    public static func notifyChanged() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(darwinName), nil, nil, true)
    }

    /// Called by the main app: moves pending files to a private temp folder and returns them.
    /// The caller deletes `folder` after handing the files to the transfer manager (which copies them).
    public static func claim() -> (files: [URL], folder: URL)? {
        guard let dir = directory else { return nil }
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                 options: [.skipsHiddenFiles])) ?? []
        guard !items.isEmpty else { return nil }
        let out = fm.temporaryDirectory.appendingPathComponent("outbox-" + UUID().uuidString, isDirectory: true)
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        var files: [URL] = []
        for sub in items {
            for f in (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil)) ?? [] {
                // keep the original file name inside a unique folder
                let folder = out.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = folder.appendingPathComponent(f.lastPathComponent)
                if (try? fm.moveItem(at: f, to: target)) != nil { files.append(target) }
            }
            try? fm.removeItem(at: sub)
        }
        return files.isEmpty ? nil : (files, out)
    }

    private final class Box { let f: () -> Void; init(_ f: @escaping () -> Void) { self.f = f } }

    /// Observe "outbox changed" from the extension. Keep the returned object alive.
    public static func observe(_ handler: @escaping () -> Void) -> AnyObject {
        let box = Box(handler)
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        Unmanaged.passUnretained(box).toOpaque(),
                                        { _, observer, _, _, _ in
            guard let observer else { return }
            let b = Unmanaged<Box>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { b.f() }
        }, darwinName, nil, .deliverImmediately)
        return box
    }
}
