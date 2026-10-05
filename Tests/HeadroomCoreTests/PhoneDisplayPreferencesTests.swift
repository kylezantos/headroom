import Foundation
import Testing
@testable import HeadroomCore

/// U12 / KTD11: one "Match my Mac" switch covers meter style, percentages, account-name ink and
/// the app's Codex Spark rows. Scenarios V23–V26 of the parity plan.
struct PhoneDisplayPreferencesTests {
    private let macChoices = CompanionDisplayBlock(
        meterStyle: MeterStyle(format: .full, shape: .segmented, fill: .ghost),
        percentageMode: .used, accountTitleInk: .brand, appSparkEnabled: true)

    private func freshDefaults() -> UserDefaults {
        let suite = "headroom.phone-display.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func values(_ display: ResolvedPhoneDisplay) -> CompanionDisplayBlock { display.block }

    // MARK: V23 — Match on follows the Mac; off holds; back on returns to the Mac

    @Test func matchIsOnByDefaultAndFollowsTheMacBlock() {
        let phone = PhoneDisplayPreferences.default
        #expect(phone.matchesMac)
        let display = PhoneDisplayPreferences.resolve(mac: macChoices, phone: phone)
        #expect(display.source == .mac)
        #expect(values(display) == macChoices)
        #expect(display.note == nil)
    }

    @Test func aMacStyleChangeReachesThePhoneOnlyWhileMatchIsOn() {
        var phone = PhoneDisplayPreferences.default
        let changed = CompanionDisplayBlock(
            meterStyle: MeterStyle(format: .micro, shape: .tube, fill: .hueRamp),
            percentageMode: .used, accountTitleInk: .brand, appSparkEnabled: true)
        #expect(PhoneDisplayPreferences.resolve(mac: changed, phone: phone).meterStyle == changed.meterStyle)

        phone.setMatchesMac(false, mac: macChoices)
        // Match off: the Mac moving on changes nothing on the phone.
        #expect(PhoneDisplayPreferences.resolve(mac: changed, phone: phone).meterStyle == macChoices.meterStyle)
        #expect(PhoneDisplayPreferences.resolve(mac: changed, phone: phone).source == .phone)
    }

    @Test func turningMatchOffSeedsTheOverrideFromTheMacSoNothingJumps() {
        var phone = PhoneDisplayPreferences.default
        let before = PhoneDisplayPreferences.resolve(mac: macChoices, phone: phone)
        phone.setMatchesMac(false, mac: macChoices)
        #expect(phone.override == macChoices)
        let after = PhoneDisplayPreferences.resolve(mac: macChoices, phone: phone)
        #expect(values(after) == values(before))
    }

    @Test func turningMatchBackOnRestoresTheMacAndRemembersTheOverride() {
        var phone = PhoneDisplayPreferences.default
        phone.setMatchesMac(false, mac: macChoices)
        phone.setMeterStyle(.default, mac: macChoices)
        phone.setPercentageMode(.remaining, mac: macChoices)

        phone.setMatchesMac(true, mac: macChoices)
        #expect(values(PhoneDisplayPreferences.resolve(mac: macChoices, phone: phone)) == macChoices)

        // The phone's own choice comes back as it was, not re-seeded from the Mac.
        phone.setMatchesMac(false, mac: macChoices)
        let display = PhoneDisplayPreferences.resolve(mac: macChoices, phone: phone)
        #expect(display.meterStyle == .default)
        #expect(display.percentageMode == .remaining)
        #expect(display.accountTitleInk == .brand)
    }

    @Test func choosingAPhoneValueTurnsMatchOffAfterSeeding() {
        var phone = PhoneDisplayPreferences.default
        phone.setAccountTitleInk(.neutral, mac: macChoices)
        #expect(!phone.matchesMac)
        let display = PhoneDisplayPreferences.resolve(mac: macChoices, phone: phone)
        #expect(display.accountTitleInk == .neutral)
        // Everything else was seeded from the Mac, so only the chosen value moved.
        #expect(display.meterStyle == macChoices.meterStyle)
        #expect(display.percentageMode == .used)
        #expect(display.showsSparkRows)
    }

    // MARK: V24 — an old Mac resolves to defaults and says so

    @Test func anOldMacWithMatchOnResolvesToDefaultsWithTheExplanatoryLine() {
        let display = PhoneDisplayPreferences.resolve(mac: nil, phone: .default)
        #expect(display.source == .macUnavailable)
        #expect(display.meterStyle == .default)
        #expect(display.percentageMode == .remaining)
        #expect(display.accountTitleInk == .neutral)
        // KTD11: with a v3-only Mac the Spark rows default off.
        #expect(!display.showsSparkRows)
        #expect(display.note == PhoneDisplayCopy.oldMacNote)
        #expect(PhoneDisplayCopy.oldMacNote.contains("Update Headroom on your Mac"))
    }

    @Test func anOldMacSeedsTheOverrideFromTheDefaults() {
        var phone = PhoneDisplayPreferences.default
        phone.setMatchesMac(false, mac: nil)
        #expect(phone.override == CompanionDisplayBlock())
        #expect(PhoneDisplayPreferences.resolve(mac: nil, phone: phone).note == nil)
    }

    @Test func theOldMacFixtureResolvesWithNoDisplayBlock() throws {
        let content = try #require(CompanionDemoData.snapshot(.oldMac, now: Date()).content)
        #expect(content.display == nil)
        #expect(PhoneDisplayPreferences.resolve(mac: content.display, phone: .default).source == .macUnavailable)
    }

    // MARK: V25 — "used" flips the app rows; widgets keep "left"

    @Test func usedModeFlipsTheAppRowsWhileWidgetsKeepLeft() throws {
        let content = try #require(CompanionDemoData.snapshot(.displayChoices, now: Date()).content)
        let display = PhoneDisplayPreferences.resolve(mac: content.display, phone: .default)
        #expect(display.percentageMode == .used)
        #expect(display.accountTitleInk == .brand)
        #expect(ResolvedPhoneDisplay.widgetPercentageMode == .remaining)
        #expect(PhoneDisplayCopy.widgetsAlwaysLeft == "Widgets always show what’s left.")
    }

    // MARK: V26 — the phone's Spark switch works while the Mac's widget Spark switch is off

    @Test func sparkRowsShowInTheAppOnlyWhileTheMacsWidgetSparkSwitchIsOff() throws {
        let snapshot = CompanionDemoData.snapshot(.multiAccount, now: Date())
        let content = try #require(snapshot.content)
        #expect(!content.widgetSparkEnabled)
        let codexMain = try #require(content.providers.first { $0.id == "codex" }?.mainAccount)

        var phone = PhoneDisplayPreferences.default
        phone.setShowsSparkRows(true, mac: content.display)
        let display = PhoneDisplayPreferences.resolve(mac: content.display, phone: phone)
        #expect(display.showsSparkRows)

        let sparkSnapshot = CompanionDemoData.snapshot(.displayChoices, now: Date())
        let sparkContent = try #require(sparkSnapshot.content)
        let sparkCodex = try #require(sparkContent.providers.first { $0.id == "codex" }?.mainAccount)
        #expect(sparkCodex.windows.contains { $0.isSpark })
        #expect(!sparkContent.widgetSparkEnabled)

        // The app keeps the flagged rows; the widget projection drops them (KTD13).
        #expect(display.appWindows(sparkCodex.windows).count == sparkCodex.windows.count)
        let widgetCodex = try #require(sparkSnapshot.primaryProjection()?.providers.first { $0.id == "codex" })
        #expect(widgetCodex.windows.count == sparkCodex.windows.filter { !$0.isSpark }.count)

        // And with the phone switch off, the app filters them too.
        phone.setShowsSparkRows(false, mac: content.display)
        let off = PhoneDisplayPreferences.resolve(mac: content.display, phone: phone)
        #expect(off.appWindows(sparkCodex.windows).allSatisfy { !$0.isSpark })
        #expect(codexMain.windows.allSatisfy { !$0.isSpark })
    }

    // MARK: Store persistence

    @MainActor @Test func theStorePersistsTheSwitchAndTheOverride() {
        let defaults = freshDefaults()
        let store = PhoneDisplayPreferencesStore(defaults: defaults)
        #expect(store.preferences == .default)
        store.setMatchesMac(false, mac: macChoices)
        store.setMeterStyle(MeterStyle(format: .micro, shape: .machined, fill: .glass), mac: macChoices)

        let reloaded = PhoneDisplayPreferencesStore(defaults: defaults)
        #expect(!reloaded.preferences.matchesMac)
        #expect(reloaded.resolve(mac: macChoices).meterStyle == MeterStyle(format: .micro, shape: .machined, fill: .glass))
        #expect(reloaded.resolve(mac: macChoices).percentageMode == .used)

        reloaded.setMatchesMac(true, mac: macChoices)
        let again = PhoneDisplayPreferencesStore(defaults: defaults)
        #expect(again.preferences.matchesMac)
        // Remembered across launches while Match is on.
        #expect(again.preferences.override?.meterStyle == MeterStyle(format: .micro, shape: .machined, fill: .glass))
    }

    @MainActor @Test func anUnreadableStoredOverrideFallsBackToMatchingTheMac() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: PhoneDisplayPreferencesStore.Key.matchesMac)
        defaults.set(Data("not json".utf8), forKey: PhoneDisplayPreferencesStore.Key.override)
        let store = PhoneDisplayPreferencesStore(defaults: defaults)
        // An override that can't be read is no override: Match off with nothing stored would
        // invent values, so the store reads it as Match on.
        #expect(store.preferences == .default)
    }

    // MARK: Copy (R2C6)

    @Test func styleSummaryNamesTheDrawnStyle() {
        #expect(PhoneDisplayCopy.styleSummary(.default) == "Micro · Chip · Only when low")
        // Tube is stored but drawn as Chip under Full, so the summary names what's drawn.
        #expect(PhoneDisplayCopy.styleSummary(MeterStyle(format: .full, shape: .tube, fill: .solid))
            == "Full · Chip · Always colored")
    }

    @Test func copyFollowsTheR2C6Rules() {
        for line in PhoneDisplayCopy.all {
            #expect(!line.contains("'"), "straight apostrophe in: \(line)")
            #expect(!line.localizedCaseInsensitiveContains("connect"), "retired verb in: \(line)")
        }
    }
}
