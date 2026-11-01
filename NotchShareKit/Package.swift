// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchShareKit",
    platforms: [.iOS("16.2"), .macOS(.v13)],
    products: [.library(name: "NotchShareKit", targets: ["NotchShareKit"])],
    targets: [.target(name: "NotchShareKit")]
)
