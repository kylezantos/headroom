import Foundation

/// One outbound link in the Settings About pane: a row title on the leading edge and the
/// destination, spelled the way people recognise it, on the trailing edge.
public struct AboutLink: Identifiable, Equatable, Sendable {
    public let title: String
    /// The trailing text. A handle or domain rather than the full URL, so the row says
    /// where it goes without printing a scheme.
    public let destination: String
    public let url: URL

    public var id: String { title }

    init(title: String, destination: String, url: String) {
        self.title = title
        self.destination = destination
        // Literals only, each pinned by `AboutLinksTests`, so a typo fails a test rather
        // than shipping a row that opens nothing.
        self.url = URL(string: url)!
    }
}

/// Every destination the About pane links out to, kept in Core so the URLs are tested
/// without a SwiftUI host.
public enum AboutLinks {
    /// The tip jar. It points at Headroom's own `/tip` path, which the website redirects
    /// to the Stripe Payment Link, so the payment provider can change without an app update.
    public static let tipJar = AboutLink(
        title: "Enjoying Headroom?",
        destination: "Tip jar",
        url: "https://headroom.zantos.co/tip"
    )

    /// Headroom is free but not open source, so this is deliberately not "free and open source".
    public static let tipJarNote =
        "Headroom is free. If you find it useful, tips are always appreciated. Processed through Stripe."

    /// The one-line description under the name in the About header.
    public static let tagline = "AI usage limits + API spend right from your menu bar"

    public static let makerName = "Kyle Zantos"

    /// U12 / R23: the phone's one-line row to the Mac app. Kyle (S4-C): short enough that the
    /// row never wraps, so the trailing edge carries only the outbound arrow, not the domain.
    public static let getHeadroomForMac = AboutLink(
        title: "Get Headroom for Mac",
        destination: "headroom.zantos.co",
        url: "https://headroom.zantos.co"
    )

    /// The phone's About header line. The phone has no tip jar this round (S4-C).
    public static let companionTagline = "iPhone & iPad companion"

    /// The "Made by" rows, in display order. GitHub is the profile, not the repo: the
    /// repository is private, so a repo link would 404 for everyone but its owner.
    public static let maker: [AboutLink] = [
        AboutLink(title: "Website", destination: "zantos.co", url: "https://zantos.co"),
        AboutLink(title: "LinkedIn", destination: "in/kylezantos", url: "https://www.linkedin.com/in/kylezantos"),
        AboutLink(title: "X", destination: "@kylezantos", url: "https://x.com/kylezantos"),
        AboutLink(title: "GitHub", destination: "kylezantos", url: "https://github.com/kylezantos"),
    ]
}
