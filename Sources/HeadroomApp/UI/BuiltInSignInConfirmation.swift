import AppKit
import Observation
import SwiftUI
import HeadroomCore

/// D7/AE7 (OpenCode plan): the warning before a built-in OpenCode sign-in. Every path that
/// starts one — Sign In, Sign In Again, Try Again and Sign Out & Set Up Again, from the
/// popover or Settings — goes through `SetupSessions.openSetup` or `resetSetup`, which park
/// the start here instead of opening Terminal. The dialog is shown every time and nothing is
/// remembered. Cancel opens nothing; extra accounts never come here.
///
/// The request is parked centrally because the start can come from many rows; the dialog is
/// drawn by whichever surface's window was key when it arrived, so the popover and Settings
/// never both present it.
@MainActor
@Observable
final class BuiltInSignInConfirmation {
    static let shared = BuiltInSignInConfirmation()

    struct Request: Identifiable, Equatable {
        let id: UUID
        let account: ProviderAccount
        let purpose: SetupHandoffPurpose
        /// The `BuiltInSignInConfirmationModifier` that draws this request, or nil when no
        /// surface is mounted (tests confirm or cancel directly).
        let presenter: UUID?
        let onRetry: () -> Void

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    /// One mounted surface able to draw the dialog.
    struct PresenterCandidate: Equatable {
        let id: UUID
        let isKey: Bool
        let isVisible: Bool
    }

    private(set) var pending: Request?
    @ObservationIgnored private var presenters: [(id: UUID, view: WeakView)] = []

    func request(account: ProviderAccount, purpose: SetupHandoffPurpose, onRetry: @escaping () -> Void) {
        let candidates = presenters.compactMap { entry -> PresenterCandidate? in
            guard let window = entry.view.value?.window else { return nil }
            return PresenterCandidate(id: entry.id, isKey: window.isKeyWindow, isVisible: window.isVisible)
        }
        pending = Request(
            id: UUID(),
            account: account,
            purpose: purpose,
            presenter: Self.choosePresenter(from: candidates),
            onRetry: onRetry
        )
    }

    /// The surface the user just clicked owns the key window. Failing that, a visible one,
    /// then the most recently mounted, so the request is never parked out of sight while a
    /// window is up.
    nonisolated static func choosePresenter(from candidates: [PresenterCandidate]) -> UUID? {
        candidates.last(where: \.isKey)?.id
            ?? candidates.last(where: \.isVisible)?.id
            ?? candidates.last?.id
    }

    /// Runs the parked start for real. Uses the request it is handed, not `pending`, so the
    /// dialog's own dismissal (which clears `pending`) can land first without losing it.
    func confirm(_ request: Request) {
        if pending?.id == request.id { pending = nil }
        switch request.purpose {
        case .reset:
            SetupSessions.resetSetup(for: request.account, confirmed: true)
        default:
            SetupSessions.openSetup(for: request.account, onRetry: request.onRetry, confirmed: true)
        }
    }

    func cancel(_ request: Request) {
        if pending?.id == request.id { pending = nil }
    }

    /// Test seam: drop any parked request.
    func reset() { pending = nil }

    fileprivate func register(_ id: UUID, view: NSView) {
        presenters.removeAll { $0.id == id || $0.view.value == nil }
        presenters.append((id, WeakView(value: view)))
    }

    fileprivate func unregister(_ id: UUID) {
        presenters.removeAll { $0.id == id || $0.view.value == nil }
    }

    struct WeakView { weak var value: NSView? }

    // MARK: Copy

    static func title(for purpose: SetupHandoffPurpose) -> String {
        purpose == .reset ? "Sign out and set up again?" : "Sign in to OpenCode Console?"
    }

    static func confirmLabel(for purpose: SetupHandoffPurpose) -> String {
        purpose == .reset ? "Sign Out & Set Up Again" : "Sign In"
    }

    static func message(for purpose: SetupHandoffPurpose) -> String {
        purpose == .reset ? SettingsCopy.opencodeBuiltInResetWarning : SettingsCopy.opencodeBuiltInSignInWarning
    }
}

/// Draws `BuiltInSignInConfirmation`'s dialog on one surface. Attached once to the popover
/// root and once to the Settings root.
struct BuiltInSignInConfirmationModifier: ViewModifier {
    @State private var id = UUID()
    private let center = BuiltInSignInConfirmation.shared

    func body(content: Content) -> some View {
        let request = center.pending.flatMap { $0.presenter == id ? $0 : nil }
        content
            .background(PresenterViewReader { center.register(id, view: $0) })
            .onDisappear { center.unregister(id) }
            .confirmationDialog(
                request.map { BuiltInSignInConfirmation.title(for: $0.purpose) } ?? "",
                isPresented: Binding(
                    get: { request != nil },
                    set: { if !$0, let request { center.cancel(request) } }
                ),
                titleVisibility: .visible,
                presenting: request
            ) { request in
                Button(BuiltInSignInConfirmation.confirmLabel(for: request.purpose)) {
                    center.confirm(request)
                }
                Button("Cancel", role: .cancel) { center.cancel(request) }
            } message: { request in
                Text(BuiltInSignInConfirmation.message(for: request.purpose))
            }
    }
}

extension View {
    func builtInSignInConfirmation() -> some View {
        modifier(BuiltInSignInConfirmationModifier())
    }
}

/// Hands the modifier its hosting view, so the center can ask which window is key.
private struct PresenterViewReader: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
