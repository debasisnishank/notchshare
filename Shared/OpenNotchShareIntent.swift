import AppIntents

/// Opens NotchShare so the armed Live Activity starts. Used by the Action Button
/// (via Shortcuts), Control Center tile and Spotlight.
struct OpenNotchShareIntent: AppIntent {
    static var title: LocalizedStringResource = "Open NotchShare"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}
