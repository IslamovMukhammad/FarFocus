// swift-tools-version: 6.2
import PackageDescription

// Everything runs on the main actor unless it says otherwise: the app is AppKit UI plus one timer.
let settings: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "FarFocus",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "FarFocus",
            path: "Sources/FarFocus",
            swiftSettings: settings
        ),
        .testTarget(
            name: "FarFocusTests",
            dependencies: ["FarFocus"],
            path: "Tests/FarFocusTests",
            swiftSettings: settings
        ),
    ]
)
