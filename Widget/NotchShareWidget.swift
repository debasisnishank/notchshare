import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents
import NotchShareKit

@main
struct NotchShareWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        NotchShareLiveActivity()
        NotchShareLockWidget()
        if #available(iOS 18.0, *) { NotchShareControl() }
    }
}

private typealias State = NotchShareActivityAttributes.ContentState

private func percent(_ s: State) -> String { "\(Int((s.progress ?? 0) * 100))%" }
private func title(_ s: State) -> String {
    switch s.mode {
    case .armed: return "Ready — \(s.macName)"
    case .transferring: return s.fileName ?? "Sending…"
    case .done: return "Sent to \(s.macName)"
    }
}

struct NotchShareLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NotchShareActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(title(context.state)).font(.headline)
                if context.state.mode == .transferring {
                    ProgressView(value: context.state.progress ?? 0)
                }
            }.padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: icon(context.state)) }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.mode == .transferring { Text(percent(context.state)) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading) {
                        Text(title(context.state)).lineLimit(1)
                        if context.state.mode == .transferring {
                            ProgressView(value: context.state.progress ?? 0)
                            Text("\(context.state.currentFileIndex ?? 1) of \(context.state.totalFiles ?? 1) · \(context.state.macName)")
                                .font(.caption2)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: icon(context.state))
            } compactTrailing: {
                if context.state.mode == .transferring { Text(percent(context.state)) }
            } minimal: {
                Image(systemName: icon(context.state))
            }
        }
    }
    private func icon(_ s: State) -> String {
        switch s.mode {
        case .armed: return "macbook.and.iphone"
        case .transferring: return "doc.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}

// MARK: Lock Screen widget (deep-links into the app)

struct LockEntry: TimelineEntry { let date = Date() }
struct LockProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockEntry { LockEntry() }
    func getSnapshot(in context: Context, completion: @escaping (LockEntry) -> Void) { completion(LockEntry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LockEntry>) -> Void) {
        completion(Timeline(entries: [LockEntry()], policy: .never))
    }
}

struct NotchShareLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NotchShareLock", provider: LockProvider()) { _ in
            LockIcon().widgetURL(URL(string: "notchshare://open"))
        }
        .configurationDisplayName("NotchShare")
        .description("Open NotchShare and arm it.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: Control Center tile (iOS 18+)

@available(iOS 18.0, *)
struct NotchShareControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "NotchShareControl") {
            ControlWidgetButton(action: OpenNotchShareIntent()) {
                Label("NotchShare", systemImage: "macbook.and.iphone")
            }
        }
        .displayName("NotchShare")
    }
}

struct LockIcon: View {
    var body: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: "macbook.and.iphone").containerBackground(.clear, for: .widget)
        } else {
            Image(systemName: "macbook.and.iphone")
        }
    }
}
