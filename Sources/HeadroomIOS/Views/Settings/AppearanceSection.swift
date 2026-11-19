import SwiftUI

/// R21 / S2 (approved): the phone's Appearance — a live specimen, theme thumbnails, one
/// "Match my Mac" switch that reveals meter style, percentages, account-name ink and Spark
/// rows when off (CA-I7, was KTD11's dimmed sections), and the phone's own choices drawn by the real meter. Theme never syncs (S3).
struct AppearanceSection: View {
    @Binding var appearance: AppearanceSetting
    /// The shown data's display block: the Mac's, the demo fixture's in Explore Demo (R30), or
    /// nil for a v3-only Mac (V24).
    let macDisplay: CompanionDisplayBlock?
    /// True only when a lineage-less v3 won (an older Mac). A current Mac's v3 mirror also
    /// lacks a display block, but must not be told to update.
    var macNeedsUpdate = false
    var store: PhoneDisplayPreferencesStore = .app

    private var display: ResolvedPhoneDisplay { store.resolve(mac: macDisplay) }
    private var matchesMac: Bool { store.preferences.matchesMac }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section("Appearance") {
            PhoneAppearanceSpecimen(display: display)
                .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
            ThemeThumbnailRow(selection: $appearance)
                .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
        }

        Section {
            Toggle(isOn: Binding(
                get: { matchesMac },
                set: { matches in
                    // CA-I7: the governed sections leave and return on the crossfade resolver.
                    withAnimation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)) {
                        store.setMatchesMac(matches, mac: macDisplay)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(PhoneDisplayCopy.matchTitle)
                    Text(PhoneDisplayCopy.styleSummary(display.meterStyle))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(PhoneSettingsStyle.switchTint())
            .accessibilityIdentifier("headroom.settings.matchMac")
        } footer: {
            // V24: an old Mac sends no display choices, so Match resolves to the defaults and
            // says why rather than claiming to match.
            Text((macNeedsUpdate ? display.note : nil) ?? PhoneDisplayCopy.matchFooter)
        }

        // CA-I7 (option A; overturns the iOS parity plan's KTD11, which kept these visible at
        // 0.38 and disabled): a switch reveals what it governs, as iOS does. While Match my Mac
        // is on, the specimen above and the switch's summary are the readout.
        if !matchesMac {
            governedSections
        }
    }

    @ViewBuilder private var governedSections: some View {
        Section("Meter style") {
            MeterStyleTile(meterStyle: display.meterStyle, chrome: PhoneMeterStyleChrome()) { style in
                store.setMeterStyle(style, mac: macDisplay)
            }
            .listRowInsets(EdgeInsets(
                top: 14, leading: PhoneSettingsStyle.swatchRowInset,
                bottom: 14, trailing: PhoneSettingsStyle.swatchRowInset))
        }

        Section {
            PhoneSwatchPicker(
                options: UsagePercentageMode.allCases, selection: display.percentageMode,
                title: \.label, accessibilityName: "percentages",
                onSelect: { store.setPercentageMode($0, mac: macDisplay) }
            ) { mode in
                PercentageSample(mode: mode)
            }
            .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
        } header: {
            Text("Percentages")
        } footer: {
            // KTD11 / V25: "used" changes the app's rows only.
            Text(PhoneDisplayCopy.widgetsAlwaysLeft)
        }

        Section("Account names") {
            PhoneSwatchPicker(
                options: AccountTitleInk.allCases, selection: display.accountTitleInk,
                title: \.label, accessibilityName: "account names",
                onSelect: { store.setAccountTitleInk($0, mac: macDisplay) }
            ) { ink in
                AccountInkSample(ink: ink)
            }
            .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
        }

        Section {
            Toggle(PhoneDisplayCopy.sparkTitle, isOn: Binding(
                get: { display.showsSparkRows },
                set: { store.setShowsSparkRows($0, mac: macDisplay) }
            ))
            .tint(PhoneSettingsStyle.switchTint())
        } footer: {
            Text(PhoneDisplayCopy.sparkFooter)
        }
    }
}

// MARK: - Specimen

/// S8: the live specimen. Not a mock — the shared `IdentityRow` and `UsageBarView` (KTD2, the
/// popover's own rows) drawn from bundled demo data at the phone's scale (KTD3), so a choice
/// can never preview as something the cards don't draw. Claude and Codex are both shown so
/// account-name ink shows two brands and the Spark switch has a row to add.
///
/// Inert like the Mac's `AppearanceSpecimen`: no hit testing, one accessibility element.
struct PhoneAppearanceSpecimen: View {
    let display: ResolvedPhoneDisplay

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = PhoneScale.defaultFactor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Frozen once per launch: Settings is not a live-data surface, and a specimen whose
    /// countdowns ticked would invite the reader to trust it as real (L9P).
    private static let now = Date()
    private static let accounts: [(provider: String, account: CompanionResolvedAccount)] = {
        let content = CompanionDemoData.snapshot(.displayChoices, now: now).content
        return ["claude", "codex"].compactMap { id in
            content?.providers.first { $0.id == id }?.mainAccount.map { (id, $0) }
        }
    }()

    var body: some View {
        specimen
            .id(recipeKey)
            .transition(.opacity)
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                value: recipeKey
            )
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of provider cards in the selected style")
            .accessibilityIdentifier("headroom.settings.specimen")
    }

    /// M5A: the specimen dissolves old recipe → new instead of hard-cutting. Keyed on what is
    /// drawn (`resolvedShape`), so a stored Tube under Full never cross-fades into itself.
    private var recipeKey: String {
        let style = display.meterStyle
        return [
            style.format.rawValue, style.resolvedShape.rawValue, style.fill.rawValue,
            display.percentageMode.rawValue, display.accountTitleInk.rawValue, "\(display.showsSparkRows)",
        ].joined(separator: ".")
    }

    private var specimen: some View {
        // G3/T1A: the Mac card's 26pt between accounts, at phone scale.
        VStack(alignment: .leading, spacing: 26 * scale) {
            ForEach(Self.accounts, id: \.provider) { entry in
                accountSection(provider: entry.provider, account: entry.account)
            }
        }
        .environment(\.accountTitleInk, display.accountTitleInk)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountSection(provider: String, account: CompanionResolvedAccount) -> some View {
        let id = ProviderID(provider)
        let windows = display.appWindows(account.windows)
        return VStack(alignment: .leading, spacing: IdentityRowMetrics.identityToMetersGap * scale) {
            IdentityRow(
                providerID: id, title: account.title, planLabel: account.planName,
                isMenuBarAccount: false, isStale: false, email: nil,
                showsPersistentEmail: false, showsConnectedChip: false,
                bankedResets: account.bankedResets, scale: scale,
                mark: { slot in ProviderLogoView(providerID: provider, size: slot / 1.35) },
                accessory: { EmptyView() }
            )
            // T1A/FS1: Micro rows 10 apart, Full rows 12 (the Mac's `UsageBarsStack`).
            VStack(spacing: (display.meterStyle.format == .micro ? 10 : 12) * scale) {
                ForEach(windows) { window in
                    UsageBarView(
                        reading: UsageMeterReading(widgetSummary: window.summary),
                        percentageMode: display.percentageMode,
                        now: Self.now,
                        meterStyle: display.meterStyle,
                        scale: scale
                    )
                }
            }
            .padding(.leading, IdentityRowMetrics.meterContentInset * scale)
            .padding(.trailing, IdentityRowMetrics.contentTrailingInset * scale)
        }
    }
}

// MARK: - Theme thumbnails

/// S3: theme thumbnails like the Mac's (System / Light / Dark) instead of a segmented control.
private struct ThemeThumbnailRow: View {
    @Binding var selection: AppearanceSetting

    var body: some View {
        PhoneSwatchPicker(
            options: AppearanceSetting.allCases, selection: selection,
            // CA-I8: 92 × 48, the other pickers' height (was 92 × 60).
            title: \.title, accessibilityName: "theme", wellWidth: 92,
            onSelect: { selection = $0 }
        ) { setting in
            ThemeThumbnail(setting: setting)
        }
        .accessibilityIdentifier("headroom.settings.theme")
    }
}

/// A miniature screen in each theme: its background with three text lines. System is split
/// diagonally between the two.
private struct ThemeThumbnail: View {
    let setting: AppearanceSetting

    var body: some View {
        ZStack {
            switch setting {
            case .light: screen(dark: false)
            case .dark: screen(dark: true)
            case .system:
                screen(dark: false)
                screen(dark: true).mask(DiagonalHalf())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(8)
    }

    private func screen(dark: Bool) -> some View {
        let background = HeadroomWidgetColorValues.containerBackgroundTop(dark: dark)
        let line = dark ? Color.white.opacity(0.35) : Color.black.opacity(0.22)
        return ZStack(alignment: .topLeading) {
            Color(red: background.red, green: background.green, blue: background.blue)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(line).frame(width: 34, height: 4)
                Capsule().fill(line).frame(width: 24, height: 4)
                Capsule().fill(line).frame(width: 29, height: 4)
            }
            // CA-I8: 6pt top and bottom so the three lines fit the 48pt well's 32pt screen.
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
        }
    }
}

private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

// MARK: - Percentage and name samples

/// "38% left" / "62% used": the same weekly window both ways, on the real gauge.
private struct PercentageSample: View {
    let mode: UsagePercentageMode

    @Environment(\.colorScheme) private var scheme

    private static let remaining = 38.0

    var body: some View {
        let percent = mode == .remaining ? Self.remaining : 100 - Self.remaining
        HStack(spacing: 6) {
            MeterGauge(
                style: .default, fraction: percent / 100, severity: .low, freshness: .live
            )
            .frame(width: 32)
            Text("\(Int(percent))%")
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(ProviderStyle.accountTitleInk(scheme: scheme))
            MeterSuffixLabel(term: mode.term)
        }
    }
}

/// "Personal" and "Work" under each brand's mark, in the ink the choice gives them.
private struct AccountInkSample: View {
    let ink: AccountTitleInk

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            name("claude", "Personal")
            name("codex", "Work")
        }
    }

    private func name(_ provider: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            ProviderLogoView(providerID: provider, size: 10)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(ProviderStyle.accountTitleInk(for: ProviderID(provider), ink: ink, scheme: scheme))
                .lineLimit(1)
        }
    }
}
