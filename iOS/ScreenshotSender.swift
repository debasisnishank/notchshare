import Photos
import PhotosUI
import SwiftUI

/// Finds the most recent screenshot and exports it to a temp file.
enum ScreenshotFinder {
    static let maxAge: TimeInterval = 120          // only screenshots from the last 2 minutes
    private static let lastSentKey = "lastSentScreenshotID"

    static func latestUnsentScreenshot(completion: @escaping (URL?, String?) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized || status == .limited else { completion(nil, "Photos access denied"); return }
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            opts.fetchLimit = 1
            guard let asset = PHAsset.fetchAssets(with: .image, options: opts).firstObject,
                  let date = asset.creationDate, Date().timeIntervalSince(date) < maxAge else {
                completion(nil, "No recent screenshot"); return
            }
            if UserDefaults.standard.string(forKey: lastSentKey) == asset.localIdentifier {
                completion(nil, "Screenshot already sent"); return
            }
            guard let res = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo }) else {
                completion(nil, "Can't read screenshot"); return
            }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(res.originalFilename)
            PHAssetResourceManager.default().writeData(for: res, toFile: url, options: nil) { error in
                if error == nil {
                    UserDefaults.standard.set(asset.localIdentifier, forKey: lastSentKey)
                    completion(url, nil)
                } else { completion(nil, "Export failed") }
            }
        }
    }
}

/// Photos picker (multi-select, photos and videos) that hands back temp file URLs.
struct PhotoPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration(photoLibrary: .shared())
        cfg.selectionLimit = 0
        cfg.filter = .any(of: [.images, .videos])
        let vc = PHPickerViewController(configuration: cfg)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([URL]) -> Void
        init(_ f: @escaping ([URL]) -> Void) { onPick = f }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let group = DispatchGroup()
            var urls: [URL] = []
            let lock = NSLock()
            for r in results {
                guard let type = r.itemProvider.registeredTypeIdentifiers.first else { continue }
                group.enter()
                r.itemProvider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                    defer { group.leave() }
                    guard let url else { return }
                    // The provided file is deleted when this closure returns, so copy it.
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let dest = dir.appendingPathComponent(url.lastPathComponent)
                    if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                        lock.lock(); urls.append(dest); lock.unlock()
                    }
                }
            }
            group.notify(queue: .main) { [onPick] in if !urls.isEmpty { onPick(urls) } }
        }
    }
}
