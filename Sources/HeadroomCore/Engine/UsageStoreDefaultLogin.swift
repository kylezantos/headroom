import Foundation

/// Default-login plan U3 and U13: the store side of `DefaultLoginTransition`. One record
/// commit per change, then the mirrors (registry label, the slot's reminder entries, the
/// continuity record), then a second commit that marks the mirrors written.
@MainActor
extension UsageStore {
    /// Loads the records and runs the idempotent launch repair, before the first merge
    /// (KTD4, KTD6). `cached` is the raw continuity load, expired windows included.
    func prepareDefaultLogin(cached: [AccountKey: UsageSnapshot]) {
        guard let defaultLoginRecordStore else { return }
        guard let data = defaultLoginRecordStore.read() else {
            defaultLoginState = DefaultLoginRecordsState()
            launchContinuity = cached
            return
        }
        // An envelope this build cannot read is left alone, and the feature stays off for
        // the session rather than writing mirrors without their records.
        guard var state = DefaultLoginRecordsCodec.decode(data) else { return }
        let loaded = state

        for index in state.slots.indices {
            let key = state.slots[index].key
            guard providers.contains(where: { $0.accountKey == key }) else { continue }
            if let pending = state.slots[index].pendingMirror {
                // A crash between the commit and its mirrors: finish the change.
                writeMirror(pending, for: key)
                if pending.removesContinuity {
                    snapshots[key] = .pending(for: key.providerID)
                    state.slots[index].continuityRemoved = true
                }
                state.slots[index].pendingMirror = nil
            } else if state.slots[index].binding != nil,
                      !Self.continuityIsAttributed(cached[key], to: state.slots[index]) {
                // KTD6: another build rewrote this row's saved reading, so nothing kept
                // under the row is known to be the bound account's. Purged, never parked.
                purgeReminders(for: key)
                snapshots[key] = .pending(for: key.providerID)
                continuityCache?.remove(for: key)
                state.slots[index].continuityRemoved = true
            }
        }
        DefaultLoginTransition.retireDuplicates(in: &state)

        defaultLoginState = state
        // KTD7: only a slot nothing was ever bound to consults the saved reading's email.
        launchContinuity = cached.filter { key, _ in
            guard let slot = state.slot(for: key) else { return true }
            return slot.binding == nil && slot.phase != .cleared
        }
        if state != loaded { commitDefaultLogin(state) }
    }

    /// A saved reading is the bound account's when it carries that account's digest, or
    /// carries none and is the very reading this slot last accepted. A missing record is
    /// expected only when this build removed it (KTD6).
    private static func continuityIsAttributed(_ record: UsageSnapshot?, to slot: SlotRecord) -> Bool {
        guard let record else { return slot.continuityRemoved }
        if let digest = record.identity?.identity?.digest {
            return digest == slot.binding?.digest
        }
        return record.capturedAt != nil && record.capturedAt == slot.lastAcceptedCapturedAt
    }

    /// Classifies an accepted reading, applies any change of account as one committed
    /// step, and returns the reading to merge it against. Runs right after the
    /// `acceptsResult` guard, before the reliability note and the sign-out edge.
    func defaultLoginPrior(for key: AccountKey, fresh: UsageSnapshot) -> UsageSnapshot? {
        let current = snapshots[key]
        guard var state = defaultLoginState,
              let reading = DefaultLoginReading(fresh),
              let account = accounts(for: key.providerID).first(where: { $0.key == key })
        else { return current }

        let slot = state.slot(for: key)
        // The steady state, the same account again, parks nothing; skip the store reads.
        let isSteady = slot?.phase == .attached && slot?.binding != nil && reading.kind == slot?.binding.map { .known($0) }
        let context = DefaultLoginSlotContext(
            isBuiltIn: account.isBuiltIn,
            label: account.label,
            defaultLabel: ProviderAccount.builtInDefaultLabel,
            snapshot: current.flatMap { $0.windows.isEmpty || $0.freshness == .pending ? nil : $0 },
            reminders: isSteady ? .none : parkedReminders(for: key),
            launchSnapshot: launchContinuity[key],
            otherReaders: Set(state.slots.compactMap { other in
                other.key != key && other.key.providerID == key.providerID && other.phase == .attached
                    ? other.binding?.digest : nil
            })
        )
        let before = state
        let effects = DefaultLoginTransition.apply(reading, for: key, context: context, to: &state)
        if reading.kind != .lapsed { launchContinuity.removeValue(forKey: key) }

        if effects.accountChanged {
            // A post still in flight for the previous account must write nothing here.
            attachmentGenerations[key, default: 0] &+= 1
            sessionReliabilityRecord?.endObservation(for: key)
            signOutRecord?.clearLastKnownSignedIn(for: key)
        }
        if state != before { commitDefaultLogin(state) }
        if effects.needsMirror, let pending = state.slot(for: key)?.pendingMirror {
            writeMirror(pending, for: key)
            if var written = state.slot(for: key) {
                written.pendingMirror = nil
                state.upsert(written)
                commitDefaultLogin(state)
            }
        }

        switch effects.prior {
        case .current: return current
        case .none: return nil
        case .snapshot(let parked): return parked
        }
    }

    /// The reset boundary and stop-tracking (KTD7); removing an extra drops its record.
    func defaultLoginDidClear(_ key: AccountKey, removed: Bool = false) {
        guard var state = defaultLoginState else { return }
        launchContinuity.removeValue(forKey: key)
        let before = state
        if removed {
            state.removeSlot(for: key)
        } else {
            let label = accounts(for: key.providerID).first(where: { $0.key == key })?.label
                ?? ProviderAccount.builtInDefaultLabel
            DefaultLoginTransition.clear(key, label: label, in: &state)
        }
        if state != before { commitDefaultLogin(state) }
    }

    func defaultLoginDidRename(_ key: AccountKey, to label: String) {
        guard var state = defaultLoginState else { return }
        let before = state
        DefaultLoginTransition.rename(key, to: label, in: &state)
        if state != before { commitDefaultLogin(state) }
    }

    /// KTD6: notes whether this build left the slot without a continuity record.
    func defaultLoginDidUpdateContinuity(for key: AccountKey, removed: Bool) {
        guard var state = defaultLoginState, var slot = state.slot(for: key),
              slot.continuityRemoved != removed
        else { return }
        slot.continuityRemoved = removed
        state.upsert(slot)
        commitDefaultLogin(state)
    }

    private func commitDefaultLogin(_ state: DefaultLoginRecordsState) {
        defaultLoginState = state
        guard let data = DefaultLoginRecordsCodec.encode(state) else { return }
        defaultLoginRecordStore?.write(data)
    }

    private func writeMirror(_ mirror: PendingMirror, for key: AccountKey) {
        if let label = mirror.label { writeLabel(label, for: key) }
        if let reminders = mirror.reminders {
            notificationCoordinator?.restore(
                useItUp: reminders.useItUp,
                bankedBaseline: reminders.bankedBaseline,
                for: key,
                now: now()
            )
            bankedResetAcknowledgements?.restore(count: reminders.bankedAcknowledged, for: key)
        }
        if mirror.removesContinuity { continuityCache?.remove(for: key) }
    }

    /// Refreshes the account index too, so a reminder evaluated in the same merge names
    /// the row by its new label.
    private func writeLabel(_ label: String, for key: AccountKey) {
        if let accountRegistry {
            accountRegistry.renameAccount(key, to: label)
            accountsByProvider[key.providerID] = accountRegistry.accounts(
                for: key.providerID, capacity: accountCapacity(for: key.providerID)
            )
        } else if let index = accountsByProvider[key.providerID]?.firstIndex(where: { $0.key == key }) {
            accountsByProvider[key.providerID]?[index].label = label
        }
    }

    private func parkedReminders(for key: AccountKey) -> ParkedReminders {
        let parked = notificationCoordinator?.parkedState(for: key)
        return ParkedReminders(
            useItUp: parked?.useItUp ?? [],
            bankedBaseline: parked?.bankedBaseline,
            bankedAcknowledged: bankedResetAcknowledgements?.acknowledgedCount(for: key)
        )
    }

    private func purgeReminders(for key: AccountKey) {
        bankedResetAcknowledgements?.purge(for: key)
        notificationCoordinator?.purge(for: key)
    }
}
