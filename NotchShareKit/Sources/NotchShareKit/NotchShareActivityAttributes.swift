#if os(iOS)
import ActivityKit

public struct NotchShareActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public enum Mode: String, Codable { case armed, transferring, done }
        public var mode: Mode
        public var macName: String
        public var fileName: String?
        public var progress: Double?
        public var totalFiles: Int?
        public var currentFileIndex: Int?

        public init(mode: Mode, macName: String, fileName: String? = nil, progress: Double? = nil,
                    totalFiles: Int? = nil, currentFileIndex: Int? = nil) {
            self.mode = mode; self.macName = macName; self.fileName = fileName
            self.progress = progress; self.totalFiles = totalFiles; self.currentFileIndex = currentFileIndex
        }
    }
    public init() {}
}
#endif
