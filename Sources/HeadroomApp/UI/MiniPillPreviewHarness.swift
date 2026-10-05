import AppKit
import SwiftUI
import HeadroomCore
#if canImport(HeadroomWidgetSharedUI)
import HeadroomWidgetSharedUI
#endif

/// KTD10: one complete pinned-date native cycle, rendered without opening a window.
@MainActor
enum MiniPillPreviewHarness {
    static func run(outputDirectory: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let frames = Int((LoadingMotionConstants.dripCycle * 30).rounded())
            for dark in [false, true] {
                for frame in 0..<frames {
                    let view = preview(dark: dark, date: Date(timeIntervalSince1970: Double(frame) / 30))
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 1
                    guard let image = renderer.cgImage,
                          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                        throw PreviewFailure.image
                    }
                    let name = String(format: "%@-%03d.png", dark ? "dark" : "light", frame)
                    try data.write(to: directory.appendingPathComponent(name))
                }
            }
            print("Rendered \(frames * 2) pinned native Mini Pill frames at 1× (\(frames) per appearance).")
        } catch {
            print("Loading preview failed to render or write its output.")
            exit(1)
        }
    }

    private static func preview(dark: Bool, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Waiting for sign-in")
                .font(.system(size: 12, weight: .medium))
            HStack(spacing: 6) {
                MiniPill(mode: .drip)
                Text("Continue in Terminal…")
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(Color(nsColor: dark ? NSColor(white: 0.75, alpha: 1) : NSColor(white: 0.30, alpha: 1)))
        .frame(width: 230, height: 90, alignment: .leading)
        .padding(.leading, 18)
        .background(Color(nsColor: dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.96, alpha: 1)))
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.loadingDate, date)
    }

    private enum PreviewFailure: Error { case image }
}
