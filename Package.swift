// swift-tools-version: 6.0
import PackageDescription

// Headroom — a menu bar app that shows remaining usage for AI subscriptions.
//
// Structured as a Swift package so the testable core (`HeadroomCore`) builds and
// verifies via `swift build` / `swift test` in CI and headless environments. The
// package opens directly in Xcode 27 and `xcodebuild -scheme Headroom` builds it.
// Finalizing the distributable menu bar app (LSUIElement Info.plist, launch-at-login
// bundle, and the stable Apple Development signing identity in KTD8) is done in Xcode
// on the user's machine — see docs/plans and README.
let package = Package(
    name: "Headroom",
    platforms: [.macOS("15.0"), .iOS("26.0")],
    products: [
        .library(name: "HeadroomCore", targets: ["HeadroomCore"]),
        .library(name: "HeadroomWidgetSharedUI", targets: ["HeadroomWidgetSharedUI"]),
        .library(name: "HeadroomSharedUI", targets: ["HeadroomSharedUI"]),
        .executable(name: "Headroom", targets: ["HeadroomApp"]),
        .executable(name: "HeadroomWidgets", targets: ["HeadroomWidgets"]),
    ],
    targets: [
        .target(name: "HeadroomCore"),
        .target(
            name: "HeadroomWidgetSharedUI",
            dependencies: ["HeadroomCore"]
        ),
        .target(
            name: "HeadroomSharedUI",
            dependencies: ["HeadroomCore", "HeadroomWidgetSharedUI"]
        ),
        .executableTarget(
            name: "HeadroomApp",
            // L9P: Settings › Widgets & iPhone renders the real small/medium widget
            // bodies from HeadroomWidgetSharedUI rather than a hand-kept mock.
            dependencies: ["HeadroomCore", "HeadroomWidgetSharedUI", "HeadroomSharedUI"],
            // The app icon catalog is compiled by actool in the xcodegen/xcodebuild app
            // build only; excluding it keeps `swift build`/`swift test` (a plain CLI
            // executable, no app bundle) fast and free of asset-catalog processing.
            exclude: ["HeadroomApp.entitlements", "Resources/Assets.xcassets"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "HeadroomWidgets",
            dependencies: ["HeadroomCore", "HeadroomWidgetSharedUI", "HeadroomSharedUI"],
            exclude: ["HeadroomWidgets.entitlements", "Info.plist"]
        ),
        .testTarget(
            name: "HeadroomCoreTests",
            dependencies: ["HeadroomCore"],
            resources: [.process("Fixtures")]
        ),
    ]
)
