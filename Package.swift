// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SIPPhone",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SIPPhoneCore",
            path: "Sources/SIPPhoneCore"
        ),
        .executableTarget(
            name: "CallerLite",
            dependencies: ["SIPPhoneCore"],
            path: "Sources/SIPPhone"
        ),
        .testTarget(
            name: "SIPPhoneTests",
            dependencies: ["SIPPhoneCore"],
            path: "Tests/SIPPhoneTests"
        )
    ]
)
