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
        var scheme: ColorScheme = .light

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
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)
        }
    }

    private struct PixelCensus {
        /// Mean x, in points, of the ring's pixels: strong ink against the background.
        var ringCentreX: CGFloat?
        var ringPixelCount = 0
        /// Pixels with real colour in them. A neutral ink plate draws none.
        var chromaticCount = 0
    }

    /// CA-S2: the ring is primary ink at 0.85, so it is the only near-black (light) or
    /// near-white (dark) mark in the row; the unselected hairlines are 0.08 ink.
    private static func census(selection: Int, scheme: ColorScheme = .light) throws -> PixelCensus {
        let scale: CGFloat = 2
        let renderer = ImageRenderer(content: PlateRow(selection: selection, scheme: scheme))
        renderer.scale = scale
        let image = try #require(renderer.cgImage, "the row did not render")
        let rep = NSBitmapImageRep(cgImage: image)
        var sum: CGFloat = 0
        var census = PixelCensus()
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      colour.alphaComponent > 0.5 else { continue }
                let channels = [colour.redComponent, colour.greenComponent, colour.blueComponent]
                let chroma = (channels.max() ?? 0) - (channels.min() ?? 0)
                if chroma > 0.15 { census.chromaticCount += 1 }
                let luminance = channels.reduce(0, +) / 3
                if scheme == .dark ? luminance > 0.6 : luminance < 0.4 {
                    sum += CGFloat(x)
                    census.ringPixelCount += 1
                }
            }
        }
        if census.ringPixelCount > 0 {
            census.ringCentreX = sum / CGFloat(census.ringPixelCount) / scale
        }
        return census
    }

    private static func swatchCentreX(_ index: Int) -> CGFloat {
        inset + CGFloat(index) * (swatchWidth + swatchSpacing) + swatchWidth / 2
    }

    @Test(arguments: 0..<swatchCount)
    func thePlateIsDrawnOnTheSelectedSwatch(_ selection: Int) throws {
        let centre = try #require(try Self.census(selection: selection).ringCentreX,
                                  "no ring was drawn for selection \(selection)")
        // Within a quarter swatch of the selected column, and nearer it than any neighbour.
        #expect(abs(centre - Self.swatchCentreX(selection)) < Self.swatchWidth / 4,
                "plate centred at \(centre), swatch \(selection) at \(Self.swatchCentreX(selection))")
    }

    /// CA-S2: the plate colour is not the system accent, in either appearance. With no
    /// AccentColor asset the accent is system blue, so a blue ring shows up as chromatic
    /// pixels; the ink ring draws none and still draws a ring.
    @Test(arguments: [ColorScheme.light, .dark])
    func thePlateIsInkNotTheSystemAccent(_ scheme: ColorScheme) throws {
        let census = try Self.census(selection: 1, scheme: scheme)
        #expect(census.chromaticCount == 0, "\(census.chromaticCount) coloured pixels in the \(scheme) plate")
        #expect(census.ringPixelCount > 0, "no ink ring in the \(scheme) plate")
        #expect(SettingsSelectionInk.ringOpacity == 0.85)
        #expect(SettingsSelectionInk.ringWidth == 1.5)
    }

    private static func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/HeadroomApp/UI/\(name)"), encoding: .utf8)
    }

    private static func codeLines(_ text: String) -> [Substring] {
        text.split(separator: "\n").map { $0.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? "" }
    }

    /// CA-S2: Settings text links are neutral (`SettingsInlineLink`); system-blue `.link`
    /// buttons, `Link`s and accent fills are gone from the files that draw Settings chrome.
    @Test func settingsChromeDrawsNoSystemBlue() throws {
        let files = ["SettingsRows.swift", "SettingsPanes.swift", "SettingsSidebar.swift", "InAppDisplayTile.swift",
                     "ThemeThumbnailPicker.swift", "WidgetSettingsSection.swift", "WidgetStyleGalleryPicker.swift",
                     "NotificationsSettingsPane.swift", "ReminderRuleRow.swift", "MeterStyleTile+Settings.swift"]
        for file in files {
            let offending = Self.codeLines(try Self.source(file)).filter {
                // A titled `Link("…", destination:)` draws system blue; the sidebar's Tip Jar
                // is a `Link(destination:)` with its own plain label and stays allowed.
                $0.contains("Color.accentColor") || $0.contains(".buttonStyle(.link)")
                    || ($0.contains(" Link(") && !$0.contains("Link(destination:"))
            }
            #expect(offending.isEmpty, "\(file): \(offending)")
        }
    }

    /// CA-S7: the widget style control is a labelled preview. It wears no selection ring
    /// (nothing persists) and holds only a binding to view state, never the store or
    /// `Preferences`.
    @Test func theWidgetStylePreviewWearsNoRingAndReachesNoPreference() throws {
        let code = Self.codeLines(try Self.source("WidgetStyleGalleryPicker.swift")).joined(separator: "\n")
        #expect(!code.contains("selectionChrome"))
        #expect(!code.contains("settingsSelectionGroup"))
        #expect(!code.contains("UsageStore"))
        #expect(!code.contains("Preferences"))
        #expect(WidgetStylePreviewPicker.label == "Preview")
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
