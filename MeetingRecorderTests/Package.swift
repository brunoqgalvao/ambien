// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MeetingRecorderTests",
    platforms: [.macOS(.v13)],
    products: [],
    dependencies: [],
    targets: [
        .testTarget(
            name: "MeetingRecorderTests",
            dependencies: [],
            path: "."
        )
    ]
)
