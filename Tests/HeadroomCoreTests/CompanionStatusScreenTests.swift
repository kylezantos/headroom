import Foundation
import Testing
@testable import HeadroomCore

/// U10 (R4, R23, G5–G9): the phone's no-content screens. One row per state, every string
/// pinned here under the R2C6 copy rules.
struct CompanionStatusScreenTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: State mapping

    @Test func everyNonContentStateMapsToItsScreen() {
        #expect(CompanionStatusScreen(.accountScopeUnavailable) == .iCloudUnavailable)
        #expect(CompanionStatusScreen(.paused) == .paused)
        #expect(CompanionStatusScreen(.waiting(nil)) == .waiting)
        #expect(CompanionStatusScreen(.unreadable) == .unreadable)
        #expect(CompanionStatusScreen(.waiting(.updatePhone)) == .updatePhone)
        #expect(CompanionStatusScreen(.waiting(.updateMac)) == .updateMac)
    }

    @Test func contentHasNoStatusScreen() {
        let content = CompanionDemoData.snapshot(.multiAccount, now: now)
        #expect(content.content != nil)
        #expect(CompanionStatusScreen(content.state) == nil)
    }

    /// U7's demo variants are the UI tests' route to the waiting and paused screens.
    @Test func theWaitingAndPausedDemoVariantsReachTheirScreens() {
        #expect(CompanionStatusScreen(CompanionDemoData.snapshot(.waiting, now: now).state) == .waiting)
        #expect(CompanionStatusScreen(CompanionDemoData.snapshot(.paused, now: now).state) == .paused)
    }

    // MARK: The U10 table

    /// CA-I6 (COPY-10): the four screens a widget also shows use the widget's words, in Title
    /// Case.
    @Test func titlesMatchThePlanTable() {
        #expect(CompanionStatusScreen.waiting.title == "Waiting for Your Mac")
        #expect(CompanionStatusScreen.paused.title == "Sync Is Off")
        #expect(CompanionStatusScreen.iCloudUnavailable.title == "iCloud Not Available")
        #expect(CompanionStatusScreen.unreadable.title == "Couldn’t Read the Data")
        #expect(CompanionStatusScreen.updatePhone.title == "Update Headroom")
        #expect(CompanionStatusScreen.updateMac.title == "Update Headroom on your Mac")
    }

    @Test func theFourSharedTitlesAreTheWidgetCopyInTitleCase() {
        let pairs: [(CompanionStatusScreen, WidgetStatusState)] = [
            (.waiting, .iosWaitingForMac), (.paused, .iosDisabled),
            (.unreadable, .iosCorrupt), (.updatePhone, .iosIncompatibleSchema),
        ]
        for (screen, widget) in pairs {
            #expect(screen.title.lowercased() == widget.title.lowercased(), "\(screen)")
            #expect(screen.title == CompanionStatusCopy.titleCased(widget.title), "\(screen)")
        }
        #expect(CompanionStatusCopy.titleCased("iCloud is off") == "iCloud Is Off")
        #expect(CompanionStatusCopy.titleCased("a day in the life") == "A Day in the Life")
    }

    @Test func primaryActionsMatchThePlanTable() {
        #expect(CompanionStatusScreen.waiting.primaryAction == .refresh)
        #expect(CompanionStatusScreen.paused.primaryAction == .refresh)
        #expect(CompanionStatusScreen.unreadable.primaryAction == .refresh)
        #expect(CompanionStatusScreen.iCloudUnavailable.primaryAction == .openSettings)
        #expect(CompanionStatusScreen.updatePhone.primaryAction == .open(AboutLinks.iPhoneApp))
        #expect(CompanionStatusScreen.updateMac.primaryAction == .open(AboutLinks.getHeadroomForMac))
    }

    @Test func actionsLeadToTheRightPlaces() {
        #expect(CompanionStatusAction.refresh.title == "Refresh")
        #expect(CompanionStatusAction.openSettings.title == "Open iOS Settings")
        #expect(CompanionStatusAction.open(AboutLinks.iPhoneApp).title == "Open App Store")
        #expect(CompanionStatusAction.open(AboutLinks.iPhoneApp).url?.absoluteString
            == "https://apps.apple.com/app/id6787519784")
        #expect(CompanionStatusAction.open(AboutLinks.getHeadroomForMac).title == "Get Headroom for Mac")
        #expect(CompanionStatusAction.open(AboutLinks.getHeadroomForMac).url?.absoluteString
            == "https://headroom.zantos.co")
        #expect(CompanionStatusAction.refresh.url == nil)
        #expect(CompanionStatusAction.openSettings.url == nil)
    }

    /// G9: "Get Headroom for Mac" sits under the buttons on waiting and paused only; the
    /// Mac-update screen already leads with it.
    @Test func getHeadroomForMacLinkOnWaitingAndPaused() {
        let linked = CompanionStatusScreen.allCases.filter { $0.secondaryLink != nil }
        #expect(Set(linked) == [.waiting, .paused])
        #expect(CompanionStatusScreen.waiting.secondaryLink == AboutLinks.getHeadroomForMac)
        #expect(CompanionStatusScreen.paused.secondaryLink == AboutLinks.getHeadroomForMac)
    }

    /// Every screen leads somewhere, including into the demo.
    @Test func everyScreenOffersExploreDemo() {
        for screen in CompanionStatusScreen.allCases {
            #expect(screen.offersExploreDemo, "\(screen) must offer Explore Demo")
        }
        #expect(CompanionStatusCopy.exploreDemo == "Explore Demo")
    }

    /// The spinner rides the Refresh button only, so only a Refresh screen ever shows one.
    @Test func onlyRefreshScreensCanCheck() {
        for screen in CompanionStatusScreen.allCases {
            #expect(screen.canCheck == (screen.primaryAction == .refresh))
        }
        #expect(CompanionStatusCopy.checking == "Checking…")
    }

    // MARK: Copy (G8, R2C6)

    /// G8: the paused screen names the Mac switch exactly as the Mac prints it.
    @Test func pausedNamesTheMacSwitch() {
        #expect(CompanionStatusScreen.paused.message.contains("Sync usage to iPhone"))
        #expect(CompanionStatusScreen.paused.message.contains("Widgets & iPhone"))
    }

    /// The shipped build told users to "publish a fresh snapshot", which nothing on the Mac
    /// is called; the unreadable screen sends them to the Mac app instead.
    @Test func unreadableSendsUsersToTheMacApp() {
        let message = CompanionStatusScreen.unreadable.message
        #expect(message.contains("Open Headroom on your Mac"))
        #expect(!message.localizedCaseInsensitiveContains("publish"))
        #expect(!message.localizedCaseInsensitiveContains("snapshot"))
    }

    @Test func copyFollowsR2C6() {
        #expect(!CompanionStatusCopy.all.isEmpty)
        for line in CompanionStatusCopy.all {
            #expect(!line.contains("'"), "straight apostrophe in: \(line)")
            #expect(!line.localizedCaseInsensitiveContains("connect"), "retired verb in: \(line)")
            #expect(!line.contains(" —"), "em dash needs a non-breaking space before it: \(line)")
            #expect(!line.localizedCaseInsensitiveContains("renewal"), "renewal dates were cut: \(line)")
        }
    }

    @Test func copyListCoversEveryScreen() {
        for screen in CompanionStatusScreen.allCases {
            #expect(CompanionStatusCopy.all.contains(screen.title))
            #expect(CompanionStatusCopy.all.contains(screen.message))
            #expect(CompanionStatusCopy.all.contains(screen.primaryAction.title))
        }
    }
}
