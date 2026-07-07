import SwiftUI

struct SettingsSheetView: View {
    let envelope: WidgetSnapshotEnvelope?
    let syncInfo: IOSCompanionSyncInfo?
    @Binding var appearance: AppearanceSetting

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                List {
                    Section {
                        appHeader
                            .listRowInsets(EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
                    }

                    Section("Appearance") {
                        Picker("Appearance", selection: $appearance) {
                            ForEach(AppearanceSetting.allCases) { setting in
                                Text(setting.title).tag(setting)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }

                    Section("Sync") {
                        row("Status", value: syncStatus(now: context.date))
                        row("Source", value: syncInfo?.sourceDescription ?? "Mac snapshot")
                        row("Widgets", value: envelope?.status == .enabled ? "Enabled" : "Paused")
                    }

                    Section("Managed on Mac") {
                        Label("Refresh interval, API keys, provider selection, and renewal dates stay in Headroom on your Mac.", systemImage: "macbook")
                            .font(.footnote)
                            .foregroundStyle(HeadroomTheme.secondaryText(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Section("App") {
                        row("Version", value: versionText)
                    }
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
        .presentationDetents([.medium, .large])
    }

    private var appHeader: some View {
        HStack(spacing: 14) {
            HeadroomAppIconView(size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Headroom")
                    .font(.title3.weight(.semibold))
                Text("iPhone companion")
                    .font(.subheadline)
                    .foregroundStyle(HeadroomTheme.secondaryText(scheme))
            }
        }
        .accessibilityElement(children: .combine)
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

    private func syncStatus(now: Date) -> String {
        if let publishedAt = syncInfo?.publishedAt {
            return "Synced \(Countdown.updatedLabel(capturedAt: publishedAt, now: now) ?? "just now")"
        }
        if let generatedAt = envelope?.generatedAt {
            return "Updated \(Countdown.updatedLabel(capturedAt: generatedAt, now: now) ?? "just now")"
        }
        return "Waiting for Mac"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
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
