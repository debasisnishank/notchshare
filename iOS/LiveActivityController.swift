import ActivityKit
import NotchShareKit

/// Owns the single Live Activity: armed -> transferring -> done -> armed.
final class LiveActivityController {
    private var activity: Activity<NotchShareActivityAttributes>?
    private var macName = "Mac"

    func arm(macName: String) {
        self.macName = macName
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = NotchShareActivityAttributes.ContentState(mode: .armed, macName: macName)
        if let a = activity { Task { await a.update(.init(state: state, staleDate: nil)) }; return }
        activity = try? Activity.request(attributes: NotchShareActivityAttributes(),
                                         content: .init(state: state, staleDate: nil), pushType: nil)
    }

    func transferring(file: String, progress: Double, index: Int, total: Int) {
        let s = NotchShareActivityAttributes.ContentState(mode: .transferring, macName: macName, fileName: file,
                                                          progress: progress, totalFiles: total, currentFileIndex: index)
        guard let a = activity else { return }
        Task { await a.update(.init(state: s, staleDate: nil)) }
    }

    func done() {
        let s = NotchShareActivityAttributes.ContentState(mode: .done, macName: macName)
        guard let a = activity else { return }
        Task {
            await a.update(.init(state: s, staleDate: nil))
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            arm(macName: macName)
        }
    }

    func end() {
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
