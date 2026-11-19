import Foundation
import Testing
@testable import HeadroomCore

struct AboutLinksTests {
    @Test func tipJarGoesThroughHeadroomsOwnTipPath() {
        // The app never embeds the Stripe link itself; the website's redirect owns it.
        #expect(AboutLinks.tipJar.url.absoluteString == "https://headroom.zantos.co/tip")
        #expect(AboutLinks.tipJar.destination == "Tip jar")
    }

    @Test func makerRowsAreInOrderAndPointAtTheRightProfiles() {
        #expect(AboutLinks.maker.map(\.title) == ["Website", "LinkedIn", "X", "GitHub"])
        #expect(AboutLinks.maker.map(\.url.absoluteString) == [
            "https://zantos.co",
            "https://www.linkedin.com/in/kylezantos",
            "https://x.com/kylezantos",
            "https://github.com/kylezantos",
        ])
    }

    @Test func everyLinkIsHTTPSWithAHostAndAUniqueRowID() {
        let all = [AboutLinks.tipJar, AboutLinks.getHeadroomForMac] + AboutLinks.maker
        for link in all {
            #expect(link.url.scheme == "https")
            #expect(link.url.host() != nil)
        }
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test func tipJarNoteDoesNotClaimOpenSource() {
        // The repository is private.
        #expect(!AboutLinks.tipJarNote.localizedCaseInsensitiveContains("open source"))
    }
}

extension AboutLinksTests {
    /// CA-S8 (COPY-12): the sidebar Tip Jar's help tag. The About tagline was retired with
    /// the three-row About (CA-S6).
    @Test func tipJarCopyIsTheApprovedWording() {
        #expect(AboutLinks.tipJarNote == "Headroom is free. Tips go through Stripe.")
    }

    /// CA-S6: the three-row About and the sidebar's one Tip Jar keep every destination they
    /// had: the feedback address, the four maker profiles in order, and the tip path.
    @Test func theSlimAboutKeepsTodaysDestinations() {
        #expect(FeedbackEmail.address == "support@zantos.co")
        #expect(AboutLinks.makerName == "Kyle Zantos")
        #expect(AboutLinks.maker.map(\.title) == ["Website", "LinkedIn", "X", "GitHub"])
        #expect(AboutLinks.maker.map(\.url.absoluteString) == [
            "https://zantos.co",
            "https://www.linkedin.com/in/kylezantos",
            "https://x.com/kylezantos",
            "https://github.com/kylezantos",
        ])
        #expect(AboutLinks.tipJar.url.absoluteString == "https://headroom.zantos.co/tip")
    }
}

extension AboutLinksTests {
    /// G9: the Mac's Widgets & iPhone pane links to the live listing by its stable ID.
    @Test func iPhoneAppLinkOpensTheAppStoreListingByID() {
        #expect(AboutLinks.iPhoneApp.url.absoluteString == "https://apps.apple.com/app/id6787519784")
        #expect(AboutLinks.iPhoneApp.url.scheme == "https")
        #expect(AboutLinks.iPhoneApp.title == "Get Headroom for iPhone")
    }

    /// U12 / R23: the phone's Mac link goes to the website, not the tip jar.
    @Test func getHeadroomForMacOpensTheWebsite() {
        #expect(AboutLinks.getHeadroomForMac.url.absoluteString == "https://headroom.zantos.co")
        #expect(AboutLinks.getHeadroomForMac.title == "Get Headroom for Mac")
    }
}
