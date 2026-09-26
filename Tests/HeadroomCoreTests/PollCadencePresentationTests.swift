import Foundation
import Testing
@testable import HeadroomCore

/// U5 of the 2026-09-19 polling plan: the Settings cadence sentence is pure presentation over
/// `PollCadence` (AE2, AE3).
struct PollCadencePresentationTests {
    @Test func stretchedLaneNamesTheEffectiveIntervalAndTheAccountCount() {
        let cadence = PollCadence(chosenInterval: 2 * 60, effectiveInterval: 4 * 60, accountCount: 40)
        #expect(PollCadencePresentation.sentence(for: [("Claude", cadence)])
            == "Right now Claude refreshes about every 4\u{00A0}min across 40\u{00A0}accounts.")
    }

    @Test func slowestEffectiveMinutesBindsTheLatenessFigureToTheSlowestLane() {
        // R9 (notifications plan): the reminder help line's "up to N min late" reads the
        // same measured figure as the cadence sentence, rounded up the same way.
        let kept = PollCadence(chosenInterval: 5 * 60, effectiveInterval: 5 * 60, accountCount: 2)
        let claude = PollCadence(chosenInterval: 5 * 60, effectiveInterval: 8.3 * 60, accountCount: 6)
        #expect(PollCadencePresentation.slowestEffectiveMinutes(
            [kept, claude], chosenInterval: 5 * 60
        ) == 9)
        #expect(PollCadencePresentation.slowestEffectiveMinutes([kept], chosenInterval: 5 * 60) == 5)
        // Nothing measured yet: the chosen interval is the promise.
        #expect(PollCadencePresentation.slowestEffectiveMinutes([], chosenInterval: 10 * 60) == 10)
    }

    @Test func aKeptPromiseRendersNoSentence() {
        let cadence = PollCadence(chosenInterval: 5 * 60, effectiveInterval: 5 * 60, accountCount: 3)
        #expect(PollCadencePresentation.sentence(for: [("Claude", cadence)]) == nil)
        #expect(!cadence.isStretched)
    }

    @Test func httpLaneAtTheEnvelopeRendersNoSentence() {
        // The HTTP lane is never stretched, so 20 Codex accounts show nothing extra.
        let cadence = PollCadence(chosenInterval: 5 * 60, effectiveInterval: 5 * 60, accountCount: 20)
        #expect(PollCadencePresentation.sentence(for: [("Codex", cadence)]) == nil)
    }

    @Test func fractionalMinutesRoundUpAndOneAccountReadsSingular() {
        let cadence = PollCadence(chosenInterval: 5 * 60, effectiveInterval: 6.2 * 60, accountCount: 1)
        #expect(PollCadencePresentation.sentence(for: [("Grok", cadence)])
            == "Right now Grok refreshes about every 7\u{00A0}min across 1\u{00A0}account.")
    }

    @Test func onlyStretchedProvidersAreListedInOrder() {
        let kept = PollCadence(chosenInterval: 5 * 60, effectiveInterval: 5 * 60, accountCount: 2)
        let claude = PollCadence(chosenInterval: 5 * 60, effectiveInterval: 9 * 60, accountCount: 6)
        let cursor = PollCadence(chosenInterval: 5 * 60, effectiveInterval: 7 * 60, accountCount: 1)
        #expect(PollCadencePresentation.sentence(for: [("Claude", claude), ("Codex", kept), ("Cursor", cursor)])
            == "Right now Claude refreshes about every 9\u{00A0}min across 6\u{00A0}accounts, "
                + "and Cursor about every 7\u{00A0}min across 1\u{00A0}account.")
    }

    @Test func threeStretchedProvidersReadAsASeries() {
        let a = PollCadence(chosenInterval: 2 * 60, effectiveInterval: 4 * 60, accountCount: 20)
        let b = PollCadence(chosenInterval: 2 * 60, effectiveInterval: 3 * 60, accountCount: 5)
        let c = PollCadence(chosenInterval: 2 * 60, effectiveInterval: 3 * 60, accountCount: 1)
        #expect(PollCadencePresentation.sentence(for: [("Claude", a), ("Grok", b), ("Cursor", c)])
            == "Right now Claude refreshes about every 4\u{00A0}min across 20\u{00A0}accounts, "
                + "Grok about every 3\u{00A0}min across 5\u{00A0}accounts, "
                + "and Cursor about every 3\u{00A0}min across 1\u{00A0}account.")
    }
}
