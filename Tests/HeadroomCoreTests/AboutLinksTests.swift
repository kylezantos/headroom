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
    @Test func headerAndTipJarCopyAreTheApprovedWording() {
        #expect(AboutLinks.tagline == "AI usage limits + API spend right from your menu bar")
        #expect(AboutLinks.tipJarNote == "Headroom is free. If you find it useful, tips are always appreciated. Processed through Stripe.")
    }
}

extension AboutLinksTests {
    /// U12 / R23: the phone's Mac link goes to the website, not the tip jar.
    @Test func getHeadroomForMacOpensTheWebsite() {
        #expect(AboutLinks.getHeadroomForMac.url.absoluteString == "https://headroom.zantos.co")
        #expect(AboutLinks.getHeadroomForMac.title == "Get Headroom for Mac")
    }
}
