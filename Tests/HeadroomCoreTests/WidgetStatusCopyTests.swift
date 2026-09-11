import Foundation
import Testing
@testable import HeadroomCore

/// WCW4: the words, verbatim. Two hosts had written their own copy for the same nine
/// situations; these tests are what keeps them from drifting apart again.
struct WidgetStatusCopyTests {
    @Test func macStrings() {
        #expect(WidgetStatusState.macSetupNeeded.title == "No usage yet")
        #expect(WidgetStatusState.macSetupNeeded.message == "Open Headroom on this Mac to send usage to widgets.")

        #expect(WidgetStatusState.macIncompatibleSchema.title == "Update Headroom")
        #expect(WidgetStatusState.macIncompatibleSchema.message == "This widget needs a newer version of the app.")

        #expect(WidgetStatusState.macDisabled.title == "Widgets are off")
        #expect(WidgetStatusState.macDisabled.message == "Turn on Share data with widgets in Headroom Settings.")

        #expect(WidgetStatusState.macPending.title == "Not checked yet")
        #expect(WidgetStatusState.macPending.message == "Open Headroom to take the first reading.")
    }

    @Test func iPhoneStrings() {
        #expect(WidgetStatusState.iosDisabled.title == "Sync is off")
        #expect(WidgetStatusState.iosDisabled.message == "Turn on Sync usage to iPhone in Headroom on your Mac.")

        #expect(WidgetStatusState.iosSetupNeeded.title == "iCloud is off")
        #expect(WidgetStatusState.iosSetupNeeded.message == "Turn on iCloud for Headroom in iPhone Settings.")

        #expect(WidgetStatusState.iosWaitingForMac.title == "Waiting for your Mac")
        #expect(WidgetStatusState.iosWaitingForMac.message == "Open Headroom on your Mac to send a reading.")

        #expect(WidgetStatusState.iosCorrupt.title == "Couldn’t read the data")
        #expect(WidgetStatusState.iosCorrupt.message == "Open Headroom on your Mac and choose Check Now.")

        #expect(WidgetStatusState.iosIncompatibleSchema.title == "Update Headroom")
        #expect(WidgetStatusState.iosIncompatibleSchema.message == "Update the app on your Mac and iPhone.")
    }

    /// WCW4: the vessel must not imply a reading. The two "nothing has ever arrived" states
    /// draw an empty mark; every other state draws the same neutral half-full one.
    @Test func onlyTheNoReadingStatesDrawAnEmptyVessel() {
        for state in WidgetStatusState.allCases {
            let expected = (state == .macPending || state == .iosWaitingForMac) ? 0.0 : 0.46
            #expect(state.vesselFill == expected, "\(state)")
        }
    }

    @Test func everyVesselFillIsInRange() {
        for state in WidgetStatusState.allCases {
            #expect(state.vesselFill >= 0 && state.vesselFill <= 1, "\(state)")
        }
    }

    /// Sentence case, not title case: only the first word and proper nouns are capitalised.
    /// Settings toggle names ("Share data with widgets", "Sync usage to iPhone") and the
    /// "Check Now" command are quoted product strings, so they keep their own capitalisation.
    @Test func everyStringIsSentenceCase() {
        let allowedCapitals: Set<String> = [
            "Headroom", "Mac", "Share", "Sync", "Turn", "Open", "Update", "This", "Check", "Now",
            "iPhone", "iCloud", "Settings", "Not", "No", "Waiting", "Widgets", "Couldn’t",
        ]
        for state in WidgetStatusState.allCases {
            for text in [state.title, state.message] {
                let words = text
                    .split(whereSeparator: { $0 == " " || $0 == "." })
                    .map(String.init)
                for word in words.dropFirst() where word.first?.isUppercase == true {
                    #expect(allowedCapitals.contains(word), "\(state): unexpected capital in \"\(text)\" → \(word)")
                }
            }
        }
    }

    @Test func everyTitleIsShortEnoughForOneLineAndEveryMessageEndsInAPeriod() {
        for state in WidgetStatusState.allCases {
            #expect(!state.title.isEmpty, "\(state)")
            // Titles never take a period; they are labels, not sentences.
            #expect(!state.title.hasSuffix("."), "\(state)")
            #expect(state.title.count <= 22, "\(state) title is \(state.title.count) characters")
            #expect(state.message.hasSuffix("."), "\(state)")
        }
    }

    /// A status card exists to name one action. Every message has to contain a verb the user
    /// can act on (or, for the two "update" cases, say what is stale).
    @Test func everyMessageNamesAnAction() {
        for state in WidgetStatusState.allCases {
            let message = state.message
            let actionable = ["Open", "Turn on", "Update", "needs"].contains { message.contains($0) }
            #expect(actionable, "\(state): \"\(message)\"")
        }
    }

    @Test func noStringUsesTheDoubleHyphenDash() {
        for state in WidgetStatusState.allCases {
            #expect(!state.title.contains("--"), "\(state)")
            #expect(!state.message.contains("--"), "\(state)")
        }
    }
}
