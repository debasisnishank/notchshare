import UIKit
import UniformTypeIdentifiers
import NotchShareKit

/// iOS share extension: copies the shared files into the App Group Outbox for the main app to send.
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        label.text = "Preparing for your Mac…"
        label.font = .preferredFont(forTextStyle: .headline)
        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical; stack.spacing = 12; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                                     stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        collect()
    }

    private func collect() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let group = DispatchGroup()
        var saved = 0
        let lock = NSLock()
        for p in providers {
            guard let type = p.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .data) == true || UTType($0)?.conforms(to: .item) == true
            }) ?? p.registeredTypeIdentifiers.first else { continue }
            group.enter()
            p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                defer { group.leave() }
                guard let url, Outbox.add(fileAt: url) else { return }
                lock.lock(); saved += 1; lock.unlock()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if saved > 0 { Outbox.notifyChanged() }
            self.label.text = saved > 0 ? "Sending to your Mac ✓" : "Couldn't share this item"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}
