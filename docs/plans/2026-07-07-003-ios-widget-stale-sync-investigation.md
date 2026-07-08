# iOS Widget Stale Sync Investigation

## Context

The iOS large widget visually looked stale after the widget/card styling was unified with the macOS widgets and companion app. The first working theory was WidgetKit render caching. A later observation changed the diagnosis: the iPhone companion app itself showed `updated 20 hrs ago`, which means the iPhone is reading an old `WidgetSnapshotEnvelope`, not merely rendering a stale Home Screen snapshot.

Do not keep tuning design tokens until the data freshness problem is resolved. The current issue is most likely sync/cache state, not SwiftUI card styling.

## Current Confidence

- 80%: iPhone is displaying a stale snapshot from iCloud KVS or its local app-group cache.
- 15%: WidgetKit/SpringBoard is additionally caching the Home Screen snapshot after the stale data issue.
- 5%: Remaining source styling divergence between Claude and Codex cards.

## Evidence

1. Local render of the current widget code looked correct.

   A SwiftUI/ImageRenderer audit image of the large iOS widget showed Claude and Codex cards using the same material and ring-shadow treatment. Pixel sampling in matching blank card regions showed nearly identical RGB values.

2. Pixel sampling from the user's phone screenshot also did not show true card-fill divergence.

   Matching blank regions inside the Claude and Codex cards were effectively identical in the screenshot. That suggests perceived mismatch was not caused by provider-specific card fills in current source.

3. The iPhone companion app says the snapshot is old.

   The user observed `updated 20 hrs ago` inside the companion app. Since the companion app and widget both consume the same snapshot model, the phone has stale data before WidgetKit rendering even enters the picture.

4. Mac local widget export is fresh.

   Local Mac snapshot files checked on July 7 around 8:14pm:

   - `~/Library/Group Containers/group.com.kylezantos.headroom/widget-snapshot.json`
     - mtime: `2026-07-07 20:13:12 -0700`
     - `status`: `enabled`
     - providers: Claude + Codex, both live
   - `~/Library/Containers/com.kylezantos.headroom.widgets/Data/Library/Application Support/widget-snapshot.json`
     - mtime: `2026-07-07 20:13:12 -0700`
     - same generated snapshot

   That means the Mac widget cache/export path is alive.

5. Stale fallback snapshot files exist on the Mac.

   These older files were also found:

   - `~/Library/Group Containers/group.com.kylezantos.headroom/Library/Application Support/widget-snapshot.json`
     - mtime: `2026-07-03 08:30:36 -0700`
   - `~/Library/Application Support/widget-snapshot.json`
     - mtime: `2026-07-03 08:47:15 -0700`

   The current read order should prefer the fresh app-group root file, but these stale files are worth cleaning up or protecting against because older builds or fallback paths could read them.

6. Installed iPhone build number did not change during several visual iterations.

   The physical iPhone had `com.kylezantos.headroom.ios` installed with `CFBundleVersion = 6`. The built host app and widget extension also reported build `6`. This still supports a secondary WidgetKit cache theory, but the companion app's stale timestamp makes data freshness the primary problem.

## Relevant Code Paths

### Mac export

- `Sources/HeadroomApp/HeadroomApp.swift`
  - `AppComposition.phoneSyncExporter()` returns `iCloudSnapshotPublisher(sync: iCloudSnapshotSync(store: UbiquitousKeyValueSyncStore()))`.
- `Sources/HeadroomCore/Engine/UsageStore.swift`
  - `exportPhoneSyncSnapshot()` publishes `widgetSnapshot(widgetsEnabled: preferences.syncToIPhoneEnabled, generatedAt: generatedAt)`.
  - Called after `refreshAll()`, `refreshSubscriptions()`, `refreshAPISpend()`, surface changes, and widget preference changes.
- `Sources/HeadroomCore/Sync/iCloudSnapshotSync.swift`
  - `iCloudSnapshotPublisher.export(_:)` wraps the widget snapshot in a `SyncedWidgetSnapshotEnvelope` and calls `NSUbiquitousKeyValueStore.set`.

### iPhone read/cache

- `Sources/HeadroomIOS/Views/IOSCompanionView.swift`
  - `refresh()` reads iCloud KVS, reads the app-group cache, writes the remote snapshot into cache if iCloud returns one, then computes state.
- `Sources/HeadroomIOSWidgets/HeadroomIOSTimelineProvider.swift`
  - Widget timeline does the same: read iCloud, write remote snapshot to cache if available, then render from `IOSWidgetSnapshotState.from(...)`.
- `Sources/HeadroomCore/Sync/IOSWidgetTimelineMapping.swift`
  - `IOSWidgetSnapshotState.from(cacheRead:syncRead:)` currently prefers any local cache snapshot before sync state:

```swift
if let cached = state(from: cacheRead) {
    return cached
}
if let syncRead {
    return state(from: syncRead)
}
```

This means if the iPhone has a stale local cache and iCloud read is missing/unavailable/corrupt, the app can keep showing old content indefinitely rather than surfacing the sync failure. That behavior may be too forgiving for this debugging phase.

## Most Likely Root Cause

The Mac is writing a fresh local widget cache, but the iPhone is not receiving or not accepting a fresh iCloud KVS snapshot. Because the iPhone read path prefers local cached content, the companion app and widget can continue to display a 20-hour-old snapshot without making the sync failure obvious.

Potential reasons:

- `syncToIPhoneEnabled` may be off on the Mac, so the Mac publishes a disabled or old phone snapshot even while local Mac widgets stay fresh.
- `NSUbiquitousKeyValueStore.set(...).synchronize()` may be returning true locally but not propagating to the phone.
- The Mac and iPhone may be using different iCloud KVS identifiers because of team prefix or signing differences.
- The iPhone app-group cache may contain old data and the current state resolver treats that as valid content when iCloud cannot provide a newer snapshot.
- The widget extension build number staying at `6` may keep Home Screen snapshots stale after the data issue is fixed, but it does not explain the companion app's `updated 20 hrs ago` by itself.

## Proposed Debug Plan

1. Add explicit sync diagnostics, then remove or hide them before shipping.

   In `SettingsSheetView`, show:

   - installed app version/build
   - local cache `generatedAt`
   - iCloud `publishedAt`
   - iCloud read state: unavailable/missing/corrupt/incompatible/snapshot
   - source ID/platform
   - whether the selected displayed content came from cache or iCloud

   This will immediately tell whether the phone has no remote KVS data or is choosing old cache over newer sync.

2. Add a small Mac-side diagnostic command or debug log for the iCloud KVS payload.

   A good target is a temporary CLI flag on the Mac app, e.g. `swift run Headroom --dump-phone-sync`, that decodes `NSUbiquitousKeyValueStore.default.data(forKey: "headroom.syncedWidgetSnapshot")` and prints:

   - `publishedAt`
   - `snapshot.generatedAt`
   - source ID/platform
   - provider IDs
   - status

   Do this without printing secrets; the snapshot model is already redaction-safe.

3. Verify `syncToIPhoneEnabled` on the Mac.

   The companion app can only receive fresh data if the Mac setting "Sync snapshot to iPhone" is on. If it is off, the Mac local widget can be fresh while iPhone stays old or disabled.

4. Change iPhone state resolution to make stale cache visible.

   Consider resolving sync first when sync returns a valid snapshot, and when sync is unavailable/missing but cache is old, show a stale/sync warning instead of presenting old content as normal. At minimum, carry source metadata through `IOSWidgetSnapshotState` so the app can say "Showing cached snapshot from 20 hrs ago; iCloud has no newer snapshot."

5. Bump iOS host and widget extension build numbers.

   Change `CURRENT_PROJECT_VERSION` from `6` to `7` for `HeadroomIOS` and `HeadroomIOSWidgets` before reinstalling on the physical phone. This is a cache-busting step for WidgetKit after the data freshness issue is fixed.

6. Simulator control test.

   Simulator does not expose a simple `simctl add-widget` command. A useful control is still possible:

   - boot an iOS 26 simulator
   - install the iOS app
   - seed the simulator app-group cache with a fresh `WidgetSnapshotEnvelope`
   - launch the companion app and capture screenshots in light/dark mode
   - if possible, manually add the large Home Screen widget in Simulator and capture it

   This verifies the current SwiftUI/materials independently from the physical phone's iCloud state.

7. If WidgetKit still renders stale after fresh data is confirmed, force identity invalidation.

   Use only if needed:

   - uninstall/reinstall `com.kylezantos.headroom.ios` on the phone, or
   - temporarily change the widget kind from `HeadroomIOSUnifiedUsageWidget` to a new debug kind to prove WidgetKit snapshot identity caching.

   Changing widget kind requires re-adding the widget and should not be the default shipping fix.

## Proposed Product Fix

Make the iPhone companion app and widget honest about data freshness:

- Prefer newest valid snapshot by comparing dates when both cache and sync exist.
- Preserve sync metadata in the displayed state.
- Surface "cached" vs "synced" in Settings.
- If cache is older than a threshold and iCloud has no valid remote snapshot, show a sync warning instead of making the stale content look live.
- Keep `WidgetCenter.shared.reloadAllTimelines()` after cache writes.

This would prevent future "whack-a-mole" design debugging when the real problem is stale data.

## Validation Checklist For Opus

Run these after changes:

```bash
swift build
swift test
xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOS -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOSWidgets -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

Physical-device acceptance:

- Mac Settings has "Sync snapshot to iPhone" enabled.
- Mac diagnostic shows iCloud KVS `publishedAt` near now.
- iPhone Settings shows iCloud `publishedAt` near now.
- Companion app header says updated near now.
- Large iOS widget shows the same values as companion app.
- Claude and Codex large-widget cards use the same material/card style.
- macOS small/medium/large widgets still match the iOS widget material tokens.

