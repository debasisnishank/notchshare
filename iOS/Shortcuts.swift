import AppIntents

struct NotchShareShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenNotchShareIntent(),
                    phrases: ["Open \(.applicationName)", "Share with \(.applicationName)"],
                    shortTitle: "Open NotchShare", systemImageName: "macbook.and.iphone")
    }
}
