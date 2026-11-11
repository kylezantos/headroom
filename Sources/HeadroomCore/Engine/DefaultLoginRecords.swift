import Foundation

// Default-login plan (2026-11-10), KTD3 and KTD4. An account row is a slot bound to one
// upstream identity at a time. The label, the retained reading and the reminder state
// belong to the identity and move in and out of the slot. This file holds the records and
// the pure transition; `UsageStoreDefaultLogin.swift` applies it to the store.

/// The reminder state that belongs to one account, lifted out of the `AccountKey`-keyed
/// stores while that account is not in a slot (KTD5). The stores keep their format.
struct ParkedReminders: Codable, Equatable, Sendable {
    var useItUp: [UseItUpLedgerEntry] = []
    var bankedBaseline: Int?
    var bankedAcknowledged: Int?

    static let none = ParkedReminders()
}

/// An account's state while it is out of its slot.
struct ParkedAccount: Codable, Equatable, Sendable {
    var identity: AccountIdentity?
    var label: String?
    var email: String?
    var snapshot: StoredSnapshot?
    var reminders: ParkedReminders = .none
}

/// Mirrors still to be written after a committed change. Present only between the commit
/// and the mirror writes, so a crash in between is finished at the next launch instead of
/// being read as another build's edit (KTD4).
struct PendingMirror: Codable, Equatable, Sendable {
    var label: String?
    var reminders: ParkedReminders?
    var removesContinuity = false
}

struct SlotRecord: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        /// Readings name the bound account, or no account has been bound yet.
        case attached
        /// Live readings with no readable identity while an account is bound (R4). The
        /// bound account's label, reading and reminders are parked.
        case detached
        /// The bound account's login lapsed. Its label stays; its last reading is parked
        /// so it survives the continuity record being cleared (AE8).
        case lapsed
        /// "Sign Out & Set Up Again" or stop-tracking. The previous digest and label are
        /// parked so the same account gets its label back and another gets none (KTD7).
        case cleared
    }

    let key: AccountKey
    var binding: AccountIdentity?
    var phase: Phase = .attached
    /// Capture time of the last reading this slot accepted. A continuity record with no
    /// digest is this build's own only when its capture time equals this (KTD6).
    var lastAcceptedCapturedAt: Date?
    /// The label this build last wrote to the registry for this slot. A registry label
    /// that differs was written by another build.
    var mirroredLabel: String?
    var parked: ParkedAccount?
    /// This build removed the slot's continuity record, so a missing record is expected.
    var continuityRemoved = false
    var pendingMirror: PendingMirror?

    init(key: AccountKey) { self.key = key }
}

/// An account that left the default login. With a snapshot it is a remembered account, a
/// last-known row (R6). Without one it only keeps the label and reminder state, so they
/// return if the account does. The local id is reused across retire and recreate.
struct RememberedAccount: Codable, Equatable, Sendable {
    let id: AccountID
    let providerID: ProviderID
    /// Nil while the entry is claimed by email only (the never-bound edge, KTD7).
    var identity: AccountIdentity?
    var provisionalEmail: String?
    var label: String
    var email: String?
    var snapshot: StoredSnapshot?
    var reminders: ParkedReminders = .none
    var isHidden = false
    var lastReadAt: Date?

    var key: AccountKey { AccountKey(providerID: providerID, accountID: id) }
    var hasRow: Bool { snapshot != nil }
}

struct DefaultLoginRecordsState: Equatable, Sendable {
    var slots: [SlotRecord] = []
    var remembered: [RememberedAccount] = []

    func slot(for key: AccountKey) -> SlotRecord? { slots.first { $0.key == key } }

    mutating func upsert(_ slot: SlotRecord) {
        if let index = slots.firstIndex(where: { $0.key == slot.key }) {
            slots[index] = slot
        } else {
            slots.append(slot)
        }
    }

    mutating func removeSlot(for key: AccountKey) { slots.removeAll { $0.key == key } }
}

/// Raw storage for the record envelope. `DefaultLoginRecordsCodec` decides whether what
/// was read is usable; an envelope it cannot read is never written over.
public protocol DefaultLoginRecordStoring: Sendable {
    func read() -> Data?
    func write(_ data: Data)
}

/// UserDefaults-backed, under its own versioned key so an older build ignores it and
/// `providerAccounts.v1` is untouched (KTD4). One `set` per change.
public struct DefaultLoginRecordStore: DefaultLoginRecordStoring, @unchecked Sendable { // UserDefaults is thread-safe
    static let storageKey = "defaultLoginRecords.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func read() -> Data? { defaults.data(forKey: Self.storageKey) }

    public func write(_ data: Data) { defaults.set(data, forKey: Self.storageKey) }
}

enum DefaultLoginRecordsCodec {
    static let currentSchemaVersion = 1
    /// KTD4: remembered accounts with a row, per provider. They do not count toward
    /// add-account capacity.
    static let rememberedCap = AccountRegistry.testedEnvelope
    /// Row-less entries (label and reminders only) kept per provider.
    static let rowlessCap = AccountRegistry.testedEnvelope

    private struct Header: Decodable { let schemaVersion: Int }

    /// Decodes entry by entry: one malformed record costs that record, not the store.
    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }

    private struct DecodedEnvelope: Decodable {
        let slots: [Lossy<SlotRecord>]?
        let remembered: [Lossy<RememberedAccount>]?
    }

    private struct EncodedEnvelope: Encodable {
        let schemaVersion: Int
        let slots: [SlotRecord]
        let remembered: [RememberedAccount]
    }

    /// Nil means blocked: undecodable, or a schema this build does not know.
    static func decode(_ data: Data) -> DefaultLoginRecordsState? {
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.schemaVersion == currentSchemaVersion,
              let envelope = try? JSONDecoder().decode(DecodedEnvelope.self, from: data)
        else { return nil }
        return DefaultLoginRecordsState(
            slots: (envelope.slots ?? []).compactMap(\.value),
            remembered: (envelope.remembered ?? []).compactMap(\.value)
        )
    }

    static func encode(_ state: DefaultLoginRecordsState) -> Data? {
        try? JSONEncoder().encode(EncodedEnvelope(
            schemaVersion: currentSchemaVersion,
            slots: state.slots,
            remembered: state.remembered
        ))
    }
}

/// What one accepted reading says about the account behind a slot.
struct DefaultLoginReading: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case known(AccountIdentity)
        /// A live reading with no readable identity.
        case absent
        /// A permanent failure: the login lapsed.
        case lapsed
    }

    let kind: Kind
    let email: String?
    let capturedAt: Date?

    /// Nil for a reading that says nothing about identity: a provider that reports none,
    /// or a transient failure.
    init?(_ snapshot: UsageSnapshot) {
        switch snapshot.freshness {
        case .live:
            switch snapshot.identity {
            case .known(let identity): kind = .known(identity)
            case .absent: kind = .absent
            case .unreadable, nil: return nil
            }
        case .stale(let reason):
            guard reason.isPermanent else { return nil }
            kind = .lapsed
        case .pending:
            return nil
        }
        email = snapshot.accountEmail
        capturedAt = snapshot.capturedAt
    }
}

/// What the store knows about a slot at the moment a reading arrives.
struct DefaultLoginSlotContext: Sendable {
    /// Only the built-in row follows the default login: it is relabelled and its outgoing
    /// account is remembered. An extra resets its history and keeps its label (KTD3).
    var isBuiltIn: Bool
    var label: String
    var defaultLabel: String
    /// The slot's current reading, when it has windows.
    var snapshot: UsageSnapshot?
    var reminders: ParkedReminders
    /// The raw continuity record found at launch, consulted once on the never-bound edge.
    var launchSnapshot: UsageSnapshot?
    /// Digests other rows of this provider are bound to.
    var otherReaders: Set<String>
}

struct DefaultLoginEffects: Equatable, Sendable {
    enum Prior: Equatable, Sendable {
        /// Merge against the row's current reading, as before.
        case current
        /// The reading is another account's, or no account's: no history.
        case none
        /// The arriving account's own parked reading.
        case snapshot(UsageSnapshot)
    }

    /// The label to write to the registry; nil leaves it.
    var label: String?
    /// The reminder state to put under the slot; nil leaves it.
    var reminders: ParkedReminders?
    var prior: Prior = .current
    /// The account behind the slot changed: reject in-flight posts for the old one, end
    /// its reliability observation and clear its sign-out flag.
    var accountChanged = false
    var removesContinuity = false

    var needsMirror: Bool { label != nil || reminders != nil || removesContinuity }
}

enum DefaultLoginTransition {
    /// Applies one accepted reading to `state` and returns what the store must do. Pure.
    static func apply(
        _ reading: DefaultLoginReading,
        for key: AccountKey,
        context: DefaultLoginSlotContext,
        to state: inout DefaultLoginRecordsState
    ) -> DefaultLoginEffects {
        var slot = state.slot(for: key) ?? SlotRecord(key: key)
        var effects = DefaultLoginEffects()

        switch reading.kind {
        case .known(let identity):
            known(identity, reading: reading, slot: &slot, context: context, state: &state, effects: &effects)
        case .absent:
            absent(slot: &slot, context: context, effects: &effects)
        case .lapsed:
            // Only an account this build has bound can lapse; a provider that never
            // reported an identity keeps no record.
            guard slot.binding != nil else { return effects }
            if slot.phase == .attached {
                slot.phase = .lapsed
                slot.parked = ParkedAccount(
                    identity: slot.binding,
                    email: context.snapshot?.accountEmail,
                    snapshot: stored(context.snapshot, for: key)
                )
            }
        }

        if reading.kind != .lapsed { slot.lastAcceptedCapturedAt = reading.capturedAt }
        if let label = effects.label {
            slot.mirroredLabel = label
        } else if slot.mirroredLabel == nil {
            slot.mirroredLabel = context.label
        }
        if effects.needsMirror {
            slot.pendingMirror = PendingMirror(
                label: effects.label,
                reminders: effects.reminders,
                removesContinuity: effects.removesContinuity
            )
        }
        state.upsert(slot)
        return effects
    }

    // MARK: Known

    private static func known(
        _ identity: AccountIdentity,
        reading: DefaultLoginReading,
        slot: inout SlotRecord,
        context: DefaultLoginSlotContext,
        state: inout DefaultLoginRecordsState,
        effects: inout DefaultLoginEffects
    ) {
        guard let bound = slot.binding else {
            if slot.phase == .cleared {
                afterReset(identity, slot: &slot, context: context, effects: &effects)
            } else {
                neverBound(identity, reading: reading, slot: &slot, context: context, state: &state, effects: &effects)
            }
            slot.binding = identity
            slot.phase = .attached
            slot.parked = nil
            return
        }

        // KTD1: another digest version means "adopt again", never "identity changed".
        guard bound.digestVersion == identity.digestVersion else {
            slot.binding = identity
            return
        }

        if bound == identity {
            switch slot.phase {
            case .attached, .cleared:
                break
            case .detached:
                // The known account is back: its label, reading and reminders return, and
                // whatever was written while its identity was unreadable goes (R4).
                let parked = slot.parked ?? ParkedAccount()
                if context.isBuiltIn { effects.label = parked.label }
                effects.reminders = parked.reminders
                effects.prior = parked.snapshot?.snapshot.map(DefaultLoginEffects.Prior.snapshot) ?? .none
                effects.accountChanged = true
            case .lapsed:
                // The same account signed in again (AE8). Across a relaunch the row has
                // no windows left, so its parked reading is the prior.
                if context.snapshot == nil, let parked = slot.parked?.snapshot?.snapshot {
                    effects.prior = .snapshot(parked)
                }
            }
            slot.phase = .attached
            slot.parked = nil
            return
        }

        // The default login is a different account.
        let leaving = outgoing(slot: slot, context: context)
        // An extra never takes a remembered account's entry: that row yields to the
        // extra while it reads the account and returns if the extra is removed (KTD12).
        let arriving = context.isBuiltIn
            ? takeArriving(identity, email: reading.email, providerID: slot.key.providerID, state: &state)
            : nil
        if context.isBuiltIn, bound.strength == .strong {
            remember(leaving, identity: bound, context: context, state: &state)
        }
        if context.isBuiltIn {
            effects.label = arriving?.label ?? context.defaultLabel
        }
        effects.reminders = arriving?.reminders ?? ParkedReminders.none
        effects.prior = arriving?.snapshot?.snapshot.map(DefaultLoginEffects.Prior.snapshot) ?? .none
        effects.accountChanged = true
        effects.removesContinuity = true
        slot.binding = identity
        slot.phase = .attached
        slot.parked = nil
    }

    /// KTD7, first run after upgrade: nothing has been bound, so the only evidence of
    /// whose label and reading these are is the email cached with the saved reading.
    private static func neverBound(
        _ identity: AccountIdentity,
        reading: DefaultLoginReading,
        slot: inout SlotRecord,
        context: DefaultLoginSlotContext,
        state: inout DefaultLoginRecordsState,
        effects: inout DefaultLoginEffects
    ) {
        guard let cachedEmail = AccountEmail.normalized(context.launchSnapshot?.accountEmail),
              let readingEmail = AccountEmail.normalized(reading.email),
              cachedEmail != readingEmail
        else { return } // Same account, or no evidence of another: adopt label and history.

        // The saved reading is a different account's. It is never shown under this one.
        effects.reminders = ParkedReminders.none
        effects.prior = .none
        effects.accountChanged = true
        effects.removesContinuity = true
        guard context.isBuiltIn else { return }
        effects.label = context.defaultLabel
        guard identity.strength == .strong, let saved = context.launchSnapshot, !saved.windows.isEmpty else { return }
        // Kept under its old label, keyed by email until a strong identity carrying that
        // email claims it (AE10). Its reminder state is unattributed, so it is not parked.
        var entry = RememberedAccount(
            id: AccountID(UUID().uuidString.lowercased()),
            providerID: slot.key.providerID,
            identity: nil,
            provisionalEmail: cachedEmail,
            label: context.label,
            email: cachedEmail,
            lastReadAt: saved.capturedAt
        )
        entry.snapshot = StoredSnapshot(key: entry.key, snapshot: saved)
        insert(entry, into: &state)
    }

    /// KTD7, after "Sign Out & Set Up Again" or stop-tracking: the user chose to leave the
    /// previous account, so it is not remembered. The same account gets its label back.
    private static func afterReset(
        _ identity: AccountIdentity,
        slot: inout SlotRecord,
        context: DefaultLoginSlotContext,
        effects: inout DefaultLoginEffects
    ) {
        guard context.isBuiltIn else { return }
        if let previous = slot.parked?.identity, previous == identity {
            if let label = slot.parked?.label, label != context.label { effects.label = label }
        } else if slot.parked?.identity != nil, context.label != context.defaultLabel {
            effects.label = context.defaultLabel
        }
    }

    // MARK: Absent

    private static func absent(
        slot: inout SlotRecord,
        context: DefaultLoginSlotContext,
        effects: inout DefaultLoginEffects
    ) {
        guard let bound = slot.binding, slot.phase == .attached || slot.phase == .lapsed else { return }
        // R4: a live reading nobody can name shows under the default name, with nothing
        // of the known account's. The binding stays, so the account returns whole.
        var parked = outgoing(slot: slot, context: context)
        parked.identity = bound
        slot.parked = parked
        slot.phase = .detached
        if context.isBuiltIn, context.label != context.defaultLabel { effects.label = context.defaultLabel }
        effects.reminders = ParkedReminders.none
        effects.prior = .none
        effects.accountChanged = true
        effects.removesContinuity = true
    }

    // MARK: Lifecycle

    /// The reset boundary and stop-tracking (KTD7).
    static func clear(_ key: AccountKey, label: String, in state: inout DefaultLoginRecordsState) {
        guard var slot = state.slot(for: key) else { return }
        let previous = slot.binding ?? slot.parked?.identity
        guard previous != nil else {
            state.removeSlot(for: key)
            return
        }
        let previousLabel = slot.phase == .detached ? slot.parked?.label : ownLabel(slot: slot, current: label)
        slot.parked = ParkedAccount(identity: previous, label: previousLabel)
        slot.binding = nil
        slot.phase = .cleared
        slot.lastAcceptedCapturedAt = nil
        slot.continuityRemoved = true
        slot.pendingMirror = nil
        state.upsert(slot)
    }

    /// A rename by this build goes to the slot record with the registry, so it never
    /// looks like another build's edit (KTD6).
    static func rename(_ key: AccountKey, to label: String, in state: inout DefaultLoginRecordsState) {
        guard var slot = state.slot(for: key) else { return }
        slot.mirroredLabel = label
        state.upsert(slot)
    }

    /// KTD4 launch repair, record side: a remembered row whose account a slot is bound to
    /// would show one account twice.
    static func retireDuplicates(in state: inout DefaultLoginRecordsState) {
        for slot in state.slots {
            guard let bound = slot.binding else { continue }
            for index in state.remembered.indices
            where state.remembered[index].providerID == slot.key.providerID
                && state.remembered[index].identity == bound
                && state.remembered[index].hasRow {
                state.remembered[index].snapshot = nil
            }
        }
    }

    // MARK: Helpers

    private struct Arriving {
        var label: String
        var reminders: ParkedReminders
        var snapshot: StoredSnapshot?
    }

    /// The account that is leaving, as it stands in the slot or parked beside it.
    private static func outgoing(slot: SlotRecord, context: DefaultLoginSlotContext) -> ParkedAccount {
        switch slot.phase {
        case .detached:
            return slot.parked ?? ParkedAccount()
        case .lapsed:
            return ParkedAccount(
                identity: slot.binding,
                label: ownLabel(slot: slot, current: context.label),
                email: slot.parked?.email ?? context.snapshot?.accountEmail,
                snapshot: slot.parked?.snapshot ?? stored(context.snapshot, for: slot.key),
                reminders: context.reminders
            )
        case .attached, .cleared:
            return ParkedAccount(
                identity: slot.binding,
                label: ownLabel(slot: slot, current: context.label),
                email: context.snapshot?.accountEmail,
                snapshot: stored(context.snapshot, for: slot.key),
                reminders: context.reminders
            )
        }
    }

    /// KTD6: a registry label this build did not write was another build's edit, made
    /// for an account this build cannot name. The slot's own mirrored label is the one
    /// that travels with the bound account.
    private static func ownLabel(slot: SlotRecord, current: String) -> String {
        slot.mirroredLabel ?? current
    }

    private static func stored(_ snapshot: UsageSnapshot?, for key: AccountKey) -> StoredSnapshot? {
        guard let snapshot, !snapshot.windows.isEmpty else { return nil }
        return StoredSnapshot(key: key, snapshot: snapshot)
    }

    /// Takes the arriving account's entry out of the remembered list, if it has one. The
    /// entry stays, row-less, so its local id and label are reused if the account leaves
    /// again. A provisional entry is claimed by a strong identity with the same email.
    private static func takeArriving(
        _ identity: AccountIdentity,
        email: String?,
        providerID: ProviderID,
        state: inout DefaultLoginRecordsState
    ) -> Arriving? {
        let normalized = AccountEmail.normalized(email)
        guard let index = state.remembered.firstIndex(where: { entry in
            guard entry.providerID == providerID else { return false }
            if entry.identity == identity { return true }
            return entry.identity == nil && identity.strength == .strong
                && normalized != nil && entry.provisionalEmail == normalized
        }) else { return nil }
        let entry = state.remembered[index]
        state.remembered[index].identity = identity
        state.remembered[index].provisionalEmail = nil
        state.remembered[index].snapshot = nil
        state.remembered[index].reminders = .none
        state.remembered[index].isHidden = false
        return Arriving(label: entry.label, reminders: entry.reminders, snapshot: entry.snapshot)
    }

    /// KTD9: keeps the leaving account. It gets a row only from a real last reading, and
    /// not while another row already reads that account.
    private static func remember(
        _ leaving: ParkedAccount,
        identity: AccountIdentity,
        context: DefaultLoginSlotContext,
        state: inout DefaultLoginRecordsState
    ) {
        let snapshot = context.otherReaders.contains(identity.digest) ? nil : leaving.snapshot
        let label = leaving.label ?? context.defaultLabel
        if let index = state.remembered.firstIndex(where: {
            $0.providerID == identity.providerID && $0.identity == identity
        }) {
            var entry = state.remembered.remove(at: index)
            entry.label = label
            entry.email = leaving.email ?? entry.email
            entry.snapshot = snapshot.flatMap { rekeyed($0, to: entry.key) }
            entry.reminders = leaving.reminders
            entry.lastReadAt = leaving.snapshot?.capturedAt ?? entry.lastReadAt
            insert(entry, into: &state)
        } else {
            var entry = RememberedAccount(
                id: AccountID(UUID().uuidString.lowercased()),
                providerID: identity.providerID,
                identity: identity,
                label: label,
                email: leaving.email,
                reminders: leaving.reminders,
                lastReadAt: leaving.snapshot?.capturedAt
            )
            entry.snapshot = snapshot.flatMap { rekeyed($0, to: entry.key) }
            insert(entry, into: &state)
        }
    }

    private static func rekeyed(_ snapshot: StoredSnapshot, to key: AccountKey) -> StoredSnapshot? {
        snapshot.snapshot.map { StoredSnapshot(key: key, snapshot: $0) }
    }

    /// Appends `entry` and enforces the per-provider caps (KTD4). The arriving account was
    /// taken out before this runs, so neither side of a change is evicted for the other.
    /// Hidden rows go first, then the least recently read.
    private static func insert(_ entry: RememberedAccount, into state: inout DefaultLoginRecordsState) {
        state.remembered.append(entry)
        evict(in: &state, providerID: entry.providerID, keeping: entry.id, rows: true,
              cap: DefaultLoginRecordsCodec.rememberedCap)
        evict(in: &state, providerID: entry.providerID, keeping: entry.id, rows: false,
              cap: DefaultLoginRecordsCodec.rowlessCap)
    }

    private static func evict(
        in state: inout DefaultLoginRecordsState,
        providerID: ProviderID,
        keeping kept: AccountID,
        rows: Bool,
        cap: Int
    ) {
        func candidates() -> [RememberedAccount] {
            state.remembered.filter { $0.providerID == providerID && $0.hasRow == rows }
        }
        while candidates().count > cap {
            let evictable = candidates().filter { $0.id != kept }
            guard let victim = evictable.min(by: { first, second in
                if first.isHidden != second.isHidden { return first.isHidden }
                return (first.lastReadAt ?? .distantPast) < (second.lastReadAt ?? .distantPast)
            }) else { return }
            state.remembered.removeAll { $0.id == victim.id && $0.providerID == providerID }
        }
    }
}
