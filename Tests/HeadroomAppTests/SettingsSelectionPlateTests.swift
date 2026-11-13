import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Headroom

/// SP1: on macOS 15 the Settings window terminated whenever a swatch row's selection plate
/// slid between swatches with `matchedGeometryEffect` (AppKit's "more Update Constraints in
/// Window passes than there are views in the window"). The fix frames one plate per row from
/// the selected swatch's layout anchor. macOS 26 never showed the crash, so a hosted window
/// test on the build machine can't catch it coming back. These tests pin the two facts the fix
/// stands on instead: the plate is drawn where the selected swatch's anchor says, and no
/// Settings view slides anything with `matchedGeometryEffect`.
/// See `docs/solutions/ui/settings-matched-geometry-crash-macos15.md`.
@MainActor
@Suite(.sharedAppState)
struct SettingsSelectionPlateTests {
    nonisolated private static let swatchCount = 3
    nonisolated private static let swatchWidth: CGFloat = 60
    nonisolated private static let swatchSpacing: CGFloat = 8
    nonisolated private static let inset: CGFloat = 10

    /// A three-swatch row built from the same pieces the Settings pickers use.
    private struct PlateRow: View {
        let selection: Int

        var body: some View {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(SettingsSelectionPlateTests.swatchWidth),
                                        spacing: SettingsSelectionPlateTests.swatchSpacing),
                    count: SettingsSelectionPlateTests.swatchCount
                ),
                alignment: .leading,
                spacing: SettingsSelectionPlateTests.swatchSpacing
            ) {
                ForEach(0..<SettingsSelectionPlateTests.swatchCount, id: \.self) { index in
                    Color.clear
                        .frame(height: 40)
                        .padding(5)
                        .selectionChrome(isSelected: index == selection)
                }
            }
            .settingsSelectionGroup(value: selection)
            .padding(SettingsSelectionPlateTests.inset)
            .frame(width: 2 * SettingsSelectionPlateTests.inset
                + CGFloat(SettingsSelectionPlateTests.swatchCount) * SettingsSelectionPlateTests.swatchWidth
                + CGFloat(SettingsSelectionPlateTests.swatchCount - 1) * SettingsSelectionPlateTests.swatchSpacing,
                   alignment: .leading)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        }
    }

    /// Horizontal centre, in points, of the strongly coloured pixels: the accent ring. Every
    /// other mark in the row is a neutral hairline.
    private static func accentCentreX(selection: Int) throws -> CGFloat {
        let scale: CGFloat = 2
        let renderer = ImageRenderer(content: PlateRow(selection: selection))
        renderer.scale = scale
        let image = try #require(renderer.cgImage, "the row did not render")
        let rep = NSBitmapImageRep(cgImage: image)
        var sum: CGFloat = 0
        var count: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let channels = [colour.redComponent, colour.greenComponent, colour.blueComponent]
                let chroma = (channels.max() ?? 0) - (channels.min() ?? 0)
                if colour.alphaComponent > 0.5, chroma > 0.3 {
                    sum += CGFloat(x)
                    count += 1
                }
            }
        }
        try #require(count > 0, "no accent ring was drawn for selection \(selection)")
        return sum / count / scale
    }

    private static func swatchCentreX(_ index: Int) -> CGFloat {
        inset + CGFloat(index) * (swatchWidth + swatchSpacing) + swatchWidth / 2
    }

    @Test(arguments: 0..<swatchCount)
    func thePlateIsDrawnOnTheSelectedSwatch(_ selection: Int) throws {
        let centre = try Self.accentCentreX(selection: selection)
        // Within a quarter swatch of the selected column, and nearer it than any neighbour.
        #expect(abs(centre - Self.swatchCentreX(selection)) < Self.swatchWidth / 4,
                "plate centred at \(centre), swatch \(selection) at \(Self.swatchCentreX(selection))")
    }

    /// Settings sources: every file under `HeadroomApp/UI` that builds Settings chrome, plus
    /// the shared Settings tile. Found by content so a new pane is covered without editing this.
    private static func settingsSourceFiles() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HeadroomAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let markers = ["SettingsTile", "selectionChrome", "settingsSelectionGroup", "SettingsPaneScaffold", "SettingsView"]
        let fileManager = FileManager.default
        var files: [URL] = []
        for directory in ["Sources/HeadroomApp/UI", "Sources/HeadroomSharedUI/Settings"] {
            let url = root.appendingPathComponent(directory)
            for name in try fileManager.contentsOfDirectory(atPath: url.path) where name.hasSuffix(".swift") {
                let file = url.appendingPathComponent(name)
                let text = try String(contentsOf: file, encoding: .utf8)
                if directory.hasSuffix("Settings") || name.contains("Settings") || markers.contains(where: text.contains) {
                    files.append(file)
                }
            }
        }
        return files
    }

    @Test func noSettingsViewSlidesWithMatchedGeometryEffect() throws {
        let files = try Self.settingsSourceFiles()
        #expect(files.contains { $0.lastPathComponent == "SettingsRows.swift" }, "the Settings sources were not found")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let offending = text.split(separator: "\n").filter { line in
                let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                return code.contains(".matchedGeometryEffect(")
            }
            #expect(offending.isEmpty, """
                \(file.lastPathComponent) uses matchedGeometryEffect. In the Settings window that \
                terminated the app on macOS 15 (SP1); frame the moving view from a layout anchor \
                instead, or re-run the macOS 15 VM matrix in \
                docs/solutions/ui/settings-matched-geometry-crash-macos15.md first.
                """)
        }
    }
}
