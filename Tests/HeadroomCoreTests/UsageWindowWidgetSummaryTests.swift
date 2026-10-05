import Foundation
import Testing
@testable import HeadroomCore

/// U3/KTD2: the phone renders synced rows through the popover's own meter row, so the
/// adapter from the wire summary back to `UsageWindow` must be lossless where the wire is,
/// and the row's numbers must come from one canonical normalized value on both platforms.
@Suite
struct UsageWindowWidgetSummaryTests {
    private let reset = Date(timeIntervalSince1970: 1_800_003_600)
    private let observed = Date(timeIntervalSince1970: 1_799_990_000)

    private func summary(
        kind: WidgetWindowKind = .fiveHour,
        label: String = "5h",
        remaining: Double,
        utilization: Double? = nil,
        resetSchedule: ResetSchedule? = nil,
        freshness: WidgetWindowFreshness = .live,
        observedAt: Date? = nil,
        billingPeriodDuration: TimeInterval? = nil
    ) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: kind,
            label: label,
            percentRemaining: remaining,
            utilization: utilization,
            resetSchedule: resetSchedule ?? .scheduled(reset),
            resetLabel: "Resets 4pm",
            resetTimeZoneIdentifier: "Europe/London",
            observedAt: observedAt,
            severity: WidgetUsageSeverity(UsageSeverity(percentRemaining: remaining)),
            freshness: freshness,
            billingPeriodDuration: billingPeriodDuration
        )
    }

    // MARK: - Kind

    @Test func aSchemaThreeBillingPeriodBecomesABillingPeriodAgain() throws {
        let source = UsageWindow(
            kind: .billingPeriod(label: "Included", duration: 2_592_000),
            utilization: 40,
            resetsAt: reset
        )
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [.cursor: UsageSnapshot(providerID: .cursor, windows: [source], planLabel: nil, capturedAt: observed, freshness: .live)],
            providerOrder: [.cursor],
            displayNames: [.cursor: "Cursor"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: observed
        )
        let wire = try #require(envelope.providers.first?.windows.first)
        #expect(wire.kind == .other("Included"))
        #expect(UsageWindow(widgetSummary: wire).kind == .billingPeriod(label: "Included", duration: 2_592_000))
    }

    @Test(arguments: [nil, 0, -60, Double.infinity, Double.nan] as [TimeInterval?])
    func anyOtherDurationLeavesAnHonestOther(duration: TimeInterval?) {
        let window = UsageWindow(widgetSummary: summary(
            kind: .other("Weekly (Fable)"), label: "Weekly (Fable)", remaining: 60,
            billingPeriodDuration: duration
        ))
        #expect(window.kind == .other("Weekly (Fable)"))
    }

    /// The associated label is the kind's identity; the summary's display `label` is not.
    @Test func theKindsOwnLabelSurvivesIncludingAnEmptyOne() {
        #expect(UsageWindow(widgetSummary: summary(kind: .other(""), label: "x", remaining: 60)).kind == .other(""))
        #expect(UsageWindow(widgetSummary: summary(kind: .weekly, label: "anything", remaining: 60)).kind == .weekly)
        #expect(UsageWindow(widgetSummary: summary(kind: .other("Spark weekly"), label: "Spark", remaining: 60)).kind == .other("Spark weekly"))
    }

    // MARK: - Utilization, reset and provenance

    @Test func aMigratedRowWithoutUtilizationMaterializesTheComplement() throws {
        let row = summary(remaining: 37.5)
        #expect(UsageWindow(widgetSummary: row).utilization == 62.5)
        let reading = UsageMeterReading(widgetSummary: row)
        // Not exact evidence: the reading keeps the absence.
        #expect(reading.exactUtilization == nil)
        #expect(try #require(reading.display).sourceUtilization == nil)
    }

    @Test func anExactUtilizationIsKeptVerbatim() {
        let row = summary(remaining: 15.1, utilization: 84.95)
        #expect(UsageWindow(widgetSummary: row).utilization == 84.95)
        #expect(UsageMeterReading(widgetSummary: row).exactUtilization == 84.95)
    }

    @Test func theResetScheduleLabelAndZoneRoundTrip() {
        let scheduled = UsageWindow(widgetSummary: summary(remaining: 50))
        #expect(scheduled.resetSchedule == .scheduled(reset))
        #expect(scheduled.resetLabel == "Resets 4pm")
        #expect(scheduled.resetTimeZoneIdentifier == "Europe/London")
        let unresolved = UsageWindow(widgetSummary: summary(remaining: 50, resetSchedule: .unresolved(.legacyUnknown)))
        #expect(unresolved.resetSchedule == .unresolved(.legacyUnknown))
        #expect(unresolved.resetSchedule.deadline == nil)
    }

    @Test func freshnessAndItsDatesMapOneToOne() {
        let since = observed.addingTimeInterval(-600)
        #expect(UsageWindow(widgetSummary: summary(remaining: 50)).freshness == .live)
        let stale = UsageWindow(widgetSummary: summary(remaining: 50, freshness: .stale(observedAt: observed)))
        #expect(stale.freshness == .stale(observedAt: observed))
        #expect(stale.observedAt == observed)
        let unavailable = UsageWindow(widgetSummary: summary(
            remaining: 50, freshness: .unavailable(since: since), observedAt: observed
        ))
        #expect(unavailable.freshness == .unavailable(since: since))
        // The original observation anchor survives, never a later publication time.
        #expect(unavailable.observedAt == observed)
    }

    @Test func aLiveRowKeepsItsSourceObservationAnchor() {
        let live = UsageWindow(widgetSummary: summary(remaining: 50, observedAt: observed))
        #expect(live.freshness == .live)
        #expect(live.observedAt == observed)
        #expect(UsageWindow(widgetSummary: summary(remaining: 50)).observedAt == nil)
    }

    // MARK: - Severity parity with the projector

    /// Plan U3: severity from the adapted row equals the projector's at the band edges.
    @Test(arguments: [0.0, 15, 16, 50, 100])
    func adaptedSeverityMatchesTheProjector(remaining: Double) throws {
        let source = UsageWindow(kind: .weekly, utilization: 100 - remaining, resetsAt: reset)
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [.claude: UsageSnapshot(providerID: .claude, windows: [source], planLabel: nil, capturedAt: observed, freshness: .live)],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: observed
        )
        let wire = try #require(envelope.providers.first?.windows.first)
        let reading = UsageMeterReading(widgetSummary: wire)
        #expect(reading.severity.map(WidgetUsageSeverity.init) == wire.severity)
        #expect(UsageWindow(widgetSummary: wire).severity == source.severity)
        #expect(UsageMeterReading(window: source).severity == reading.severity)
    }

    // MARK: - Canonical display

    /// Source path: decimal subtraction before rounding (UsageDisplayValue owns the rule).
    @Test(arguments: [(84.96, 15.0, UsageSeverity.critical), (84.95, 15.1, .low), (49.96, 50.0, .low)])
    func theMacReadingNormalizesTheActualSourceWindow(utilization: Double, remaining: Double, severity: UsageSeverity) throws {
        let reading = UsageMeterReading(window: UsageWindow(kind: .fiveHour, utilization: utilization, resetsAt: reset))
        #expect(try #require(reading.display).percentRemaining == remaining)
        #expect(reading.severity == severity)
        #expect(reading.exactUtilization == utilization)
    }

    /// Remaining-only rows normalize the stored remaining, never a fabricated utilization.
    @Test(arguments: [
        (15.049999999999997, 15.0, UsageSeverity.critical),
        (15.05, 15.1, .low),
        (50.05, 50.1, .healthy),
    ])
    func aRemainingOnlyRowNormalizesWhatWasStored(remaining: Double, expected: Double, severity: UsageSeverity) throws {
        let reading = UsageMeterReading(widgetSummary: summary(remaining: remaining))
        #expect(try #require(reading.display).percentRemaining == expected)
        #expect(reading.severity == severity)
    }

    /// The adversarial case the preflight recorded: the fabricated complement rounds the
    /// other way, which is exactly why the reading does not take that path.
    @Test func theFabricatedComplementWouldHaveRoundedTheOtherWay() throws {
        let row = summary(remaining: 15.049999999999997)
        let fabricated = try #require(UsageDisplayValue(window: UsageWindow(widgetSummary: row)))
        #expect(fabricated.percentRemaining == 15.1)
        #expect(UsageMeterReading(widgetSummary: row).display?.percentRemaining == 15.0)
    }

    @Test(arguments: [
        (0.0, 0, 100),
        (15, 15, 85),
        (16, 16, 84),
        (50, 50, 50),
        (100, 100, 0),
        (15.05, 15, 85),
        (49.96, 50, 50),
    ])
    func bothModesPrintFromTheSameCanonicalRemaining(remaining: Double, left: Int, used: Int) {
        for reading in [
            UsageMeterReading(widgetSummary: summary(remaining: remaining)),
            UsageMeterReading(window: UsageWindow(kind: .weekly, utilization: 100 - remaining, resetsAt: reset)),
        ] {
            #expect(reading.roundedPercentage(for: .remaining) == left)
            #expect(reading.roundedPercentage(for: .used) == used)
            let display = reading.display!.percentRemaining
            #expect(reading.fraction(for: .remaining) == display / 100)
            #expect(reading.fraction(for: .used) == (100 - display) / 100)
        }
    }

    /// KTD6.2 consequence, pinned on purpose: the printed integer rounds the normalized
    /// tenth, because that tenth is all the phone receives. 84.54% used is 15.46% left, which
    /// normalizes to 15.5 and prints 16% left on both platforms (the raw value printed 15%).
    @Test func theIntegerRoundsTheNormalizedTenthOnBothPlatforms() {
        let source = UsageWindow(kind: .weekly, utilization: 84.54, resetsAt: reset)
        #expect(UsagePercentageMode.remaining.roundedPercentage(for: source) == 15)
        let mac = UsageMeterReading(window: source)
        let phone = UsageMeterReading(widgetSummary: resolvedPhoneSummary(for: source, freshness: .live))
        #expect(mac.display?.percentRemaining == 15.5)
        for reading in [mac, phone] {
            #expect(reading.roundedPercentage(for: .remaining) == 16)
            #expect(reading.roundedPercentage(for: .used) == 85)
        }
    }

    @Test func anUnavailableRowHidesItsValueButKeepsItsSeverityMetadata() throws {
        let reading = UsageMeterReading(widgetSummary: summary(
            remaining: 12, utilization: 88, freshness: .unavailable(since: observed)
        ))
        #expect(reading.hidesValue)
        #expect(reading.roundedPercentage(for: .remaining) == nil)
        #expect(reading.roundedPercentage(for: .used) == nil)
        #expect(reading.fraction(for: .remaining) == 0)
        #expect(reading.severity == .critical)
        #expect(try #require(reading.display).percentRemaining == 12)
        #expect(!reading.usesCriticalInk(dimmed: false))
    }

    @Test func aStaleRowKeepsItsFigureButNeverPaintsCritical() {
        let reading = UsageMeterReading(widgetSummary: summary(remaining: 12, freshness: .stale(observedAt: observed)))
        #expect(!reading.hidesValue)
        #expect(reading.roundedPercentage(for: .remaining) == 12)
        #expect(reading.severity == .critical)
        #expect(!reading.usesCriticalInk(dimmed: false))
    }

    @Test func aDimmedLiveRowNeverPaintsCritical() {
        let reading = UsageMeterReading(widgetSummary: summary(remaining: 12))
        #expect(reading.usesCriticalInk(dimmed: false))
        #expect(!reading.usesCriticalInk(dimmed: true))
    }

    /// A non-finite source never becomes an apparently live 0% or 100%.
    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func aNonFiniteSourceShowsNoFigure(value: Double) {
        let mac = UsageMeterReading(window: UsageWindow(kind: .fiveHour, utilization: value, resetsAt: reset))
        let phone = UsageMeterReading(widgetSummary: summary(remaining: value))
        for reading in [mac, phone] {
            #expect(reading.display == nil)
            #expect(reading.hidesValue)
            #expect(reading.severity == nil)
            #expect(reading.roundedPercentage(for: .remaining) == nil)
            #expect(reading.fraction(for: .used) == 0)
            #expect(!reading.usesCriticalInk(dimmed: false))
        }
        #expect(mac.exactUtilization == nil)
    }

    // MARK: - Mac ↔ phone parity (plan U3 parity scenario)

    /// The resolved phone row: the normalized remaining the Mac projects (KTD6.2) plus the
    /// source's exact utilization.
    private func resolvedPhoneSummary(for source: UsageWindow, freshness: WidgetWindowFreshness) -> WidgetWindowSummary {
        summary(
            kind: .fiveHour,
            remaining: UsageDisplayValue(window: source)!.percentRemaining,
            utilization: source.utilization,
            freshness: freshness
        )
    }

    @Test(arguments: [15.04, 15.05, 50.04])
    func theMacRowAndCapsuleAgreeWithTheResolvedPhone(remaining: Double) {
        let since = observed.addingTimeInterval(-60)
        let cases: [(UsageWindowFreshness, WidgetWindowFreshness)] = [
            (.live, .live),
            (.stale(observedAt: observed), .stale(observedAt: observed)),
            (.unavailable(since: since), .unavailable(since: since)),
        ]
        for (macFreshness, phoneFreshness) in cases {
            let source = UsageWindow(kind: .fiveHour, utilization: 100 - remaining, resetsAt: reset, freshness: macFreshness)
            let mac = UsageMeterReading(window: source)
            let phone = UsageMeterReading(widgetSummary: resolvedPhoneSummary(for: source, freshness: phoneFreshness))
            for mode in UsagePercentageMode.allCases {
                #expect(mac.roundedPercentage(for: mode) == phone.roundedPercentage(for: mode))
                #expect(mac.fraction(for: mode) == phone.fraction(for: mode))
            }
            #expect(mac.severity == phone.severity)
            for dimmed in [false, true] {
                #expect(mac.usesCriticalInk(dimmed: dimmed) == phone.usesCriticalInk(dimmed: dimmed))
            }
            let macSnapshot = UsageSnapshot(providerID: .codex, windows: [source], planLabel: "plus", capturedAt: observed, freshness: .live)
            #expect(macSnapshot.hasLiveCriticalResettableWindow
                == PlanCapsulePresentation.hasLiveCriticalResettableWindow(snapshotIsLive: true, readings: [phone]))
        }
    }

    /// 15.04% remaining is the boundary the raw value got wrong: the binary `100 − 84.96`
    /// (15.040000000000006) sat above 15 and read Low on the Mac while the normalized phone
    /// value (15.0) read Critical. Both now read the normalized value, so both open.
    @Test func theRoundingBoundaryIsCriticalOnBothPlatforms() {
        let source = UsageWindow(kind: .fiveHour, utilization: 84.96, resetsAt: reset)
        #expect(source.severity == .low) // the raw value the capsule used to read
        let phone = UsageMeterReading(widgetSummary: resolvedPhoneSummary(for: source, freshness: .live))
        #expect(UsageMeterReading(window: source).severity == .critical)
        #expect(phone.severity == .critical)
        let snapshot = UsageSnapshot(providerID: .codex, windows: [source], planLabel: "plus", capturedAt: observed, freshness: .live)
        #expect(snapshot.hasLiveCriticalResettableWindow)
        #expect(PlanCapsulePresentation.hasLiveCriticalResettableWindow(snapshotIsLive: true, readings: [phone]))
    }

    /// And the decimal tie one hundredth above it stays Low on both.
    @Test func theDecimalTieStaysLowOnBothPlatforms() {
        let source = UsageWindow(kind: .fiveHour, utilization: 84.95, resetsAt: reset)
        let phone = UsageMeterReading(widgetSummary: resolvedPhoneSummary(for: source, freshness: .live))
        #expect(UsageMeterReading(window: source).severity == .low)
        #expect(phone.severity == .low)
        let snapshot = UsageSnapshot(providerID: .codex, windows: [source], planLabel: "plus", capturedAt: observed, freshness: .live)
        #expect(!snapshot.hasLiveCriticalResettableWindow)
    }
}
