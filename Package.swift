// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notchless",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Notchless", path: "Sources/Notchless")
    ]
)
