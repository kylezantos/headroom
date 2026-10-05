import AppIntents
import Foundation
import UIKit

// KTD18 (R26): "How much <provider> is left?" answered from the last sync. Read-only: the
// intent never asks the Mac to check, never writes iCloud, and runs without opening the app.
// The words come from Core's `UsageAnswerComposer`, so every state is unit-tested there.

struct UsageLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Usage Left"
    static let description = IntentDescription(
        "Says how much of a provider’s usage is left, as of your Mac’s last sync.")
    /// iOS 26 replaces `openAppWhenRun = false` with this: answer in place, never foreground.
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Provider")
    var provider: UsageProviderOption

    static var parameterSummary: some ParameterSummary {
        Summary("How much \(\.$provider) is left")
    }

    init() {}

    init(provider: UsageProviderOption) {
        self.provider = provider
    }

    func perform() async throws -> some IntentResult & ReturnsValue<UsageLeftEntity> & ProvidesDialog {
        // KTD18: a locked phone's answer omits account titles.
        let isProtectedDataAvailable = await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
        let now = Date()
        let demo = UsageLeftDemo.snapshot(now: now)
        // KTD21: the demo snapshot is returned before iCloud or any cache is touched.
        let snapshot = CompanionPhoneSnapshotSource.production(demo: { demo }).load()
        let answer = UsageAnswerComposer.answer(
            for: provider.providerID, in: snapshot,
            context: UsageAnswerContext(
                now: now, isProtectedDataAvailable: isProtectedDataAvailable,
                isSampleData: demo != nil))
        return .result(value: UsageLeftEntity(answer), dialog: IntentDialog("\(answer.dialog)"))
    }
}

/// The structured half of the answer, for Shortcuts and for Siri surfaces that phrase
/// their own reply instead of reading the dialog (KTD18).
struct UsageLeftEntity: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Usage Left"

    @Property(title: "Provider")
    var provider: String

    @Property(title: "Percent Left")
    var percentLeft: Int?

    @Property(title: "Limit")
    var limit: String?

    @Property(title: "Updated")
    var updated: Date?

    @Property(title: "No Recent Update from Mac")
    var isDimmed: Bool

    @Property(title: "Sample Data")
    var isSampleData: Bool

    @Property(title: "Answer")
    var answer: String

    init() {
        provider = ""
        isDimmed = false
        isSampleData = false
        answer = ""
    }

    init(_ usage: UsageAnswer) {
        self.init()
        provider = usage.providerName
        percentLeft = usage.percentLeft
        limit = usage.windowLabel
        updated = usage.updatedAt
        isDimmed = usage.isDimmed
        isSampleData = usage.isSampleData
        answer = usage.dialog
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(answer)")
    }
}

/// Explore Demo (or a `--demo` launch) answers from U7's bundled v4 demo — the variant the
/// app shows, multi-account by default — resolved through the real codec and resolver in
/// memory at the answer's own clock. Nothing persists (KTD21, R30).
enum UsageLeftDemo {
    static func snapshot(now: Date) -> CompanionResolvedSnapshot? {
        let store = CompanionDemoModeStore(
            defaults: UserDefaults(suiteName: WidgetSnapshotCache.appGroupSuiteName), now: { now })
        return store.loaderSeam(launch: .current)()
    }
}
