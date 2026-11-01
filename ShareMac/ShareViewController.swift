import AppKit
import UniformTypeIdentifiers
import NotchShareKit

/// macOS share extension: copies shared files into the App Group Outbox for the main app to send.
final class ShareViewController: NSViewController {
    private let label = NSTextField(labelWithString: "Preparing for your iPhone…")

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 90))
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 35, width: 280, height: 22)
        v.addSubview(label)
        view = v
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        collect()
    }

    private func collect() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let group = DispatchGroup()
        var saved = 0
        let lock = NSLock()
        for p in providers {
            group.enter()
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    var url: URL?
                    if let u = item as? URL { url = u }
                    else if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                    guard let url, Outbox.add(fileAt: url) else { return }
                    lock.lock(); saved += 1; lock.unlock()
                }
            } else if let type = p.registeredTypeIdentifiers.first {
                p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                    defer { group.leave() }
                    guard let url, Outbox.add(fileAt: url) else { return }
                    lock.lock(); saved += 1; lock.unlock()
                }
            } else { group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if saved > 0 { Outbox.notifyChanged() }
            self.label.stringValue = saved > 0 ? "Sending to your iPhone ✓" : "Couldn't share this item"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}
