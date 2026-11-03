import SwiftUI

/// R20 / S1-A: one Settings sheet on a native list — About, Appearance, Widgets, iPhone
/// sync. Every section reads the one resolved snapshot the app shows
/// (KTD6); in Explore Demo that is the chosen demo variant, so every row reads the fixture
/// (R30).
struct SettingsSheetView: View {
    /// Build 33's inputs, kept so the Usage screen's existing call compiles. The sheet reads
    /// `snapshot` instead; U8 passes it once the app loads through the shared phone source.
    let envelope: WidgetSnapshotEnvelope?
    let syncInfo: IOSCompanionSyncInfo?
    var diagnostics: IOSSyncDiagnostics? = nil
    let isDemoMode: Bool
    @Binding var appearance: AppearanceSetting
    /// Capture harness only: pins the sheet to `.large` so a screenshot shows the settled,
    /// opaque sheet instead of the half-height detent over a dimmed Usage screen.
    var forcesLargeDetent: Bool = false
    /// The resolved snapshot the Usage screen shows. Nil until the host passes it; the sheet
    /// then loads its own through the shared phone source (KTD6).
    var snapshot: CompanionResolvedSnapshot? = nil
    /// U9: the last finished check-now round trip. Nil hides the row; it is never faked.
    var lastCheckNow: PhoneCheckNowRoundTrip? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var loadedSnapshot: CompanionResolvedSnapshot?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let shown = shownSnapshot(now: context.date)
                let manifestRows = PhoneSettingsManifestRows(snapshot: shown)
                List {
                    AboutSection(
                        syncStatus: isDemoMode
                            ? "Demo data"
                            : PhoneSyncStatus(snapshot: shown, now: context.date).state)
                    AppearanceSection(
                        appearance: $appearance, macDisplay: shown?.content?.display,
                        macNeedsUpdate: shown?.content?.notice == .updateMac)
                    WidgetsGallerySection(manifestRows: manifestRows)
                    SyncSection(
                        snapshot: shown, isDemoMode: isDemoMode, lastCheckNow: lastCheckNow,
                        now: context.date)

                    #if DEBUG
                    diagnosticsSection(now: context.date)
                    IdentityProbeDiagnosticsSection(isDemoMode: isDemoMode)
                    #endif
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        // U9-A: neutral like the popover; nothing in the sheet draws in system blue.
        .tint(.primary)
        .presentationDetents(forcesLargeDetent ? [.large] : [.medium, .large])
        .task(id: isDemoMode) {
            guard snapshot == nil, !isDemoMode else { return }
            loadedSnapshot = Self.loadSnapshot()
        }
    }

    private func shownSnapshot(now: Date) -> CompanionResolvedSnapshot? {
        if let snapshot { return snapshot }
        if isDemoMode {
            let variant = CompanionDemoModeStore.appGroup().variant(launch: .current)
            return CompanionDemoData.snapshot(variant, now: now)
        }
        return loadedSnapshot
    }

    private static func loadSnapshot() -> CompanionResolvedSnapshot {
        #if DEBUG
        if CompanionPreviewSeed.isEnabled { return CompanionPreviewSeed.snapshot() }
        switch CompanionPreviewSeed.uiTestState {
        case .waiting: return CompanionResolvedSnapshot(state: .waiting(nil))
        case .unreadable: return CompanionPreviewSeed.unreadableSnapshot()
        case .content, .stale: return CompanionPreviewSeed.snapshot()
        case nil: break
        }
        #endif
        return CompanionPhoneSnapshotSource.production().load()
    }

    #if DEBUG
    // Debug-only sync diagnostics (plan 2026-07-07-003): tells at a glance whether the phone
    // has no fresh iCloud payload or is choosing old cache over newer sync. DEBUG-gated so it
    // never ships in a Release build. Physical-device installs use the Debug config, so it's
    // visible where it's needed to diagnose stale sync.
    @ViewBuilder
    private func diagnosticsSection(now: Date) -> some View {
        Section("Sync Diagnostics") {
            row("Showing", value: diagnostics?.originText ?? "—")
            row("Cache updated", value: relative(diagnostics?.cacheGeneratedAt, now: now))
            row("iCloud state", value: diagnostics?.syncStateText ?? "—")
            row("iCloud published", value: relative(diagnostics?.syncPublishedAt, now: now))
            row("iCloud source", value: diagnostics?.syncSourceText ?? "—")
            // KTD22: deletion is verified from the phone by counting v4 key names present in
            // its KVS copy — names only, never payloads.
            row("v4 keys", value: "\(UbiquitousKeyValueSyncStore().keys(withPrefix: CompanionSyncKeys.namespace).count)")
        }
    }

    private func relative(_ date: Date?, now: Date) -> String {
        guard let date else { return "—" }
        return Countdown.updatedLabel(capturedAt: date, now: now) ?? "just now"
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
    #endif
}

struct IOSCompanionSyncInfo: Equatable {
    let publishedAt: Date?
    let sourceID: String?
    let sourcePlatform: SyncedWidgetSnapshotSourcePlatform?

    var sourceDescription: String {
        switch (sourceID, sourcePlatform) {
        case (let source?, .macOS):
            "\(source) on Mac"
        case (nil, .macOS):
            "Headroom on Mac"
        case (let source?, _):
            source
        case (nil, _):
            "Mac snapshot"
        }
    }
}

/// Raw sync state captured on each companion refresh, for the DEBUG diagnostics section.
/// Distinguishes "iCloud has no fresh payload" from "phone is choosing old cache over newer
/// sync" — the exact ambiguity the stale-sync investigation needs to resolve.
struct IOSSyncDiagnostics: Equatable {
    let cacheGeneratedAt: Date?
    let syncRead: iCloudSnapshotSyncRead
    let origin: IOSWidgetContentOrigin?

    var originText: String {
        switch origin {
        case .demo: "Demo data"
        case .cache: "Local cache"
        case .sync: "iCloud sync"
        case nil: "No content"
        }
    }

    var syncStateText: String {
        switch syncRead {
        case .unavailable: "Unavailable"
        case .missing: "No payload"
        case .corrupt: "Corrupt"
        case .incompatibleSchema: "Schema mismatch"
        case .snapshot: "Snapshot"
        }
    }

    var syncPublishedAt: Date? {
        syncRead.envelope?.publishedAt
    }

    var syncSourceText: String {
        guard let envelope = syncRead.envelope else { return "—" }
        return "\(envelope.sourceID) (\(envelope.sourcePlatform.rawValue))"
    }
}
