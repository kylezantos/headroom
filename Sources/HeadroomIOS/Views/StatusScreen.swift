import SwiftUI
import UIKit

/// U10 (R4, R23; G5–G9): the screen for every state with nothing to show. Its copy and
/// actions are one row of Core's `CompanionStatusScreen`; this view only lays it out, in the
/// approved status mock's order: mark, title, message, primary action, Explore Demo, then the
/// Mac app link on waiting and paused (G9). Everything is neutral ink (G6).
struct StatusScreen: View {
    let screen: CompanionStatusScreen
    var onExploreDemo: (() -> Void)?
    var onRefresh: () async -> Void

    @Environment(\.colorScheme) private var scheme

    /// P59: the status mock's vessel height; the waiting ghost row shares the slot so the
    /// text block sits at the same height on every screen.
    private static let markHeight: CGFloat = 84
    private static let markWallWidth = 2.6
    /// The halftone pill's 5 × 10 grid (`HalftoneVesselView`'s default), kept at hero size
    /// so the ghost reads as the same dot field the menu bar and widgets wait with.
    private static let ghostColumns = 5
    private static let ghostRows = 10

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(HeadroomTheme.backgroundView(scheme).ignoresSafeArea())
    }

    private var content: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 18)
            mark
                .frame(height: Self.markHeight)
            VStack(spacing: 9) {
                Text(screen.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(screen.message)
                    .font(.subheadline)
                    .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                primaryButton
                if let onExploreDemo, screen.offersExploreDemo {
                    Button(CompanionStatusCopy.exploreDemo) {
                        onExploreDemo()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityHint(CompanionStatusCopy.exploreDemoHint)
                    .accessibilityIdentifier("headroom.demo.enter")
                }
            }
            if let link = screen.secondaryLink {
                Link(destination: link.url) {
                    Label(link.title, systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
                }
                .accessibilityIdentifier("headroom.status.getMac")
            }
            Spacer(minLength: 36)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 520)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("headroom.status.\(screen.rawValue)")
    }

    /// Waiting shows the vessel as a static halftone ghost: the loading language's waiting
    /// placeholder (loading R14, KTD15's one-ghost-vessel form, as the widget's waiting card
    /// draws it) at the status vessel's 11:18 geometry, so it can't read as a value. Every
    /// other state shows the solid neutral vessel.
    @ViewBuilder private var mark: some View {
        if screen == .waiting, let ghost = LoadingPillState.ghostRow(count: 1).first {
            let geometry = WidgetVesselGeometry(height: Double(Self.markHeight))
            HalftoneVesselView(state: ghost, width: CGFloat(geometry.width), height: Self.markHeight,
                               columns: Self.ghostColumns, rows: Self.ghostRows)
                .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
        } else {
            VesselMark(stroke: Self.markWallWidth)
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch screen.primaryAction {
        case .refresh:
            StatusRefreshButton(onRefresh: onRefresh)
        case .openSettings:
            StatusOpenButton(action: screen.primaryAction,
                             url: URL(string: UIApplication.openSettingsURLString))
        case .open(let link):
            StatusOpenButton(action: screen.primaryAction, url: link.url)
        }
    }
}

/// A primary action that leaves the app (iOS Settings, the App Store, the Mac app's site).
private struct StatusOpenButton: View {
    let action: CompanionStatusAction
    let url: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action.title) {
            if let url { openURL(url) }
        }
        // U8 (G6): the neutral filled button, never system blue.
        .headroomProminentButton()
        .controlSize(.large)
        .accessibilityIdentifier("headroom.status.primary")
    }
}

/// KTD17 (loading plan): the button owns the check and its bounded tail; the status screen
/// stays static. The sloshing ghost row is built only while `frame.isWorking`, so nothing on
/// the screen moves unless a refresh is actually running (U10).
private struct StatusRefreshButton: View {
    let onRefresh: () async -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.loadingDate) private var pinnedDate
    @State private var isChecking = false
    @State private var endedAt: Date?

    var body: some View {
        let current = recipe(at: pinnedDate ?? Date())
        LoadingTimeline(active: isChecking && !reduceMotion, until: current.waveEnd) { date in
            let frame = recipe(at: date)
            Button {
                Task { await refresh() }
            } label: {
                if frame.isWorking {
                    HStack(spacing: 8) {
                        HalftonePillRow(pills: frame.pills, sloshEndedAt: endedAt)
                        Text(CompanionStatusCopy.checking)
                    }
                } else {
                    Text(CompanionStatusCopy.refresh)
                }
            }
            // U8 (G6): the neutral filled button, never system blue.
            .headroomProminentButton()
            .controlSize(.large)
            .disabled(frame.isWorking)
            .accessibilityIdentifier("headroom.status.primary")
        }
    }

    private func recipe(at date: Date) -> LoadingCheckRecipe {
        LoadingCheckRecipe(isChecking: isChecking, endedAt: endedAt, now: date, reduceMotion: reduceMotion)
    }

    private func refresh() async {
        guard !recipe(at: pinnedDate ?? Date()).isWorking else { return }
        endedAt = nil
        isChecking = true
        await onRefresh()
        endedAt = Date()
        isChecking = false
    }
}

/// "Get Headroom for Mac ↗": the outbound arrow trails the words, as in the status mock.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}
