# Repo patterns research — iPhone/iPad parity round (2026-10-04)

Scope: **patterns**, limited to the seven gaps INVENTORY.md does not cover. Read-only audit of
`rome-v1` (`06d082af` + uncommitted BUGS.md / project.yml version bump). Paths are repo-relative.
"Unverified" marks anything not proven from source.

## Repository Research Summary

### Findings that change the plan (read first)

1. **Evidence against the U4-C dual-publish premise: App Store iPhone 1.0 (24) cannot read v3 today.**
   BRIEF.md:22 and APPSTORE.md:602 say the public build is 1.0 (24). Its source (`1f4acb53`, the
   commit that set build 24, 2026-07-20) decodes the full envelope, then requires
   `envelope.snapshot.schemaVersion == WidgetSnapshotEnvelope.schemaVersion` with
   `schemaVersion = 1` exactly (`git show 1f4acb53:Sources/HeadroomCore/Sync/SyncedWidgetSnapshotModels.swift:52-62`).
   Its `WidgetSnapshotEnvelope.schemaVersion` is 1, and its `WidgetWindowSummary` requires a
   non-optional `resetsAt: Date` (`…/WidgetSnapshotModels.swift:182-189` at that commit).
   Mac 1.1.2 (26, `ea7b2e38`, 2026-07-28) already published schema 2. The current Mac publishes
   schema 3, which uses `resetKind`/`resetDeadline` and has no `resetsAt`.
   So every 1.0 (24) phone paired with an updated Mac already shows "Snapshot Unreadable" (corrupt)
   or "Update Needed" (incompatible). Which one depends on whether the payload has windows; that
   split is inferred from source, not tested on a device. Kyle's own phone runs 1.0 (24).
   The only clients that read v3 are dev or TestFlight builds made after the 2026-08-07 schema-3
   commit (`e640fa74`); build 33 is archived but not uploaded. **Implication:** keeping the v3 key
   protects no public phone. It's still cheap and harmless, and it can stay as the new phone's own
   widget-extension input, but Kyle should re-decide it knowing this. The misleading 1.0 copy
   ("Open Headroom on your Mac to publish a fresh snapshot") is a `BUGS.md` candidate: the shipped
   binary can't be fixed, and 1.5 fixes it by update.
2. **No export coalescing exists, and the two exports are coupled.** Every export writes the App
   Group file plus calls `WidgetCenter.shared.reloadAllTimelines()`. A reload fires even when
   nothing changed, and a test pins that: `WidgetSnapshotCacheTests.swift:242`
   `exporterReloadsUnchangedSnapshot`; the exporter is at `WidgetSnapshotExporter.swift:18-26` and
   `HeadroomApp.swift:1200-1209`. Each export also does a KVS `set` (`iCloudSnapshotSync.swift:86-94`).
   Nothing debounces either path (grep for debounce/throttle/coalesce finds only scheduler request
   coalescing). The only throttle is KTD9: a full refresh exports once, at its end. New exports on
   extra-account merges must go to the phone path only. Routing them through
   `exportWidgetSnapshot()` would spend the macOS widget reload budget for data the Mac widgets
   never show.
3. **A phone "check now" mapped to `refreshAll()` publishes no new snapshot until every lane drains.**
   `fullRefreshDepth` suppresses per-merge exports during a full refresh (`UsageStore.swift:152-155`,
   `772-794`, gate at `1290`). Claude lanes are serial: the PTY fallback takes about 20–30 s per
   account. Per-account receipts therefore have to come from the scheduler's user-progress callback
   (`UsageStore.swift:1317-1323` → `refreshProgress`), not from snapshot exports.
   `refreshNow()` (`394-396`) has no concurrency guard; the Mac popover disables its button instead
   (`PopoverView.swift:624-629`). The phone-request handler has to check `isRefreshing` itself and
   rate-limit.
4. **Bare `--demo` publishes demo data to the real iCloud KVS.** `demoStore()` deliberately keeps
   the real widget and iCloud exporters (`HeadroomApp.swift:861-890`; comment at 861-864). Running
   the Mac screenshot path on an entitled build overwrites the user's real phone snapshot with
   fixture numbers. A phone-request observer must also stay off under `--demo`. Separately,
   `phoneSyncExporter()` is not gated for the XCTest host, unlike `widgetExporter()`
   (`HeadroomApp.swift:1200-1213`).
5. **CloudKit on the Developer ID Mac needs script changes beyond entitlements:**
   - `build-app.sh` strips only the two KVS-era keys in its unentitled path
     (`Scripts/build-app.sh:129-138`). Any new restricted key must join that strip list, or ad-hoc
     builds get SIGKILLed at spawn, the same exit 137 already documented (`BUGS.md:420-428`). That
     includes `com.apple.developer.icloud-services` and a non-empty container list.
   - `release-app.sh` verifies only application-id, team, KVS, and app group
     (`Scripts/release-app.sh:302-329`).
   - The Developer ID export plist has no `iCloudContainerEnvironment` (`release-app.sh:395-413`);
     the TestFlight plist sets it to `Production` (`Scripts/ExportOptions-TestFlight.plist`).
     Exporting with a CloudKit container probably requires that key; this is unverified, so check
     it in the spike. If the Mac writes to the Development environment while the App Store phone
     subscribes to Production, nothing is delivered and nothing reports an error.
6. **Core's `WidgetFamily` must not grow accessory cases.** `WidgetFamily` (small/medium/large,
   `CaseIterable`) is at `WidgetTypeScale.swift:9-16`. The render harness sweeps `allCases`
   (`WidgetRenderHarness.swift:135,146,155`), every style recipe switches on it, and the iOS host
   maps anything unknown to `.large` (`HeadroomIOSWidgetView.swift:56-62`). Lock Screen families
   need their own `Widget`, view, and family type.
7. **The v3 decoder is strict on closed enums.** It throws (then `.corrupt` for the whole payload)
   on any unknown value of these:
   - `ResetUnresolvedReason` (`WidgetSnapshotModels.swift:374-384`)
   - `WidgetUsageSeverity`, `APISpendAttention`, `APISpendKind`
   - the synthesized `WidgetProviderFreshness`, `WidgetWindowFreshness`, `WidgetWindowKind`
     (`WidgetSnapshotModels.swift:240-250,534-579`)

   Once v3 is frozen for dual publishing, the new version needs its own types, or a v3 projection
   that maps new cases down. No test pins "the v3 payload only emits values v3 knows"; add a golden
   fixture test.

### Implementation Patterns

#### 1. Mac snapshot publishing

**Export call sites** (both exporters are `WidgetSnapshotExporting`, `WidgetSnapshotExporter.swift:3-5`):

| Site | Function | Widget | Phone |
|---|---|---|---|
| `UsageStore.swift:489` | `setWidgetPrioritySource` | ✓ | ✗ (D6 bug, `BUGS.md:411-414`) |
| `UsageStore.swift:618-619` | `setShowCodexSparkCountersInWidgets` | ✓ | ✓ |
| `UsageStore.swift:731` | `setWidgetsEnabled` | ✓ | — |
| `UsageStore.swift:736` | `setSyncToIPhoneEnabled` | — | ✓ |
| `UsageStore.swift:757-758` | `setSurfaceEnabled` | ✓ | ✓ |
| `UsageStore.swift:789-790` | `refreshAll` (once at end) | ✓ | ✓ |
| `UsageStore.swift:869-870` | `refreshAPISpend(exportAfter:)` | ✓ | ✓ |
| `UsageStore.swift:1290-1293` | `schedulerMerge`, **primary only, not during a full refresh** | ✓ | ✓ |
| `UsageStoreAccountLifecycle.swift:36-37` | `invalidateUsageForAccountReset` | ✓ | ✓ |
| `UsageStoreAccountLifecycle.swift:111-112` | `promoteAccount` (Make Main) | ✓ | ✓ |
| `UsageStoreAccountLifecycle.swift:179-180` | `resumeTrackingBuiltInAccount` | ✓ | ✓ |
| `UsageStoreAccountLifecycle.swift:209-210` | `detachAccount` | ✓ | ✓ |

These don't export but would need to for multi-account or mirrored display:
- `addAccount` (`Lifecycle:60`) and `renameAccount` (`:82`): a rename changes a synced title.
- `setShowCodexSparkCountersInApp` (`UsageStore.swift:610`).
- `setUsagePercentageMode`, `setAccountTitleInk`, `setMeterStyle` (`457-472`); a test pins that
  meter style never exports (`UsageStoreTests.swift:1062`).
- The reminder setters (`636-680`).

**Projection.** `widgetSnapshot(widgetsEnabled:generatedAt:)` (`UsageStore.swift:1087-1103`) builds
one primary-only envelope for both exporters. The only difference between them is the `enabled`
flag: `widgetsEnabled` vs `syncToIPhoneEnabled` (`1077-1085`). Phone sync **defaults off**, and the
Mac publishes a `.disabled` envelope with no providers even when sync is off; this is pinned by
`UsageStoreTests.swift:2023` `phoneSyncDefaultsOffAndExportsOnlyWhenEnabled`.
`WidgetSnapshotProjector` (`Widgets/WidgetSnapshotProjector.swift:5-48`) is excluded from both iOS
targets by path (`project.yml:110-112,150-152`). A new Mac-only multi-account projector needs the
same exclusion in both iOS targets.

**KVS write path.** There is one key, `headroom.syncedWidgetSnapshot` (`iCloudSnapshotSync.swift:27`).
`iCloudSnapshotPublisher.export` wraps the envelope with `publishedAt`, `sourceID: "Mac"` and
`.macOS`, then calls `try? sync.publish` (`71-95`). `UbiquitousKeyValueSyncStore.set` always returns
`true` (`109-112`), so failures and quota problems are invisible. The `iCloudKeyValueSyncing` seam
offers only `data(forKey:)`, `set` and `synchronize` (`20-24`): there is no remove (which split
per-provider keys need when a provider goes away), no change observation, and no reason or quota
signal. `iCloudSnapshotSync` takes a `key:` parameter (`33-41`) but its codec is
snapshot-specific, so request and receipt channels need a small generic codable-per-key channel
next to it. The test fake `MemoryiCloudKeyValueStore` (`iCloudSnapshotSyncTests.swift:120-150`)
is reusable. `publishWritesSingleKeyAndReadReturnsSnapshot` (`:9-19`) asserts that exactly one key
is written; dual publishing intentionally breaks it.

**Composition.** `AppComposition.store` passes `widgetExporter()` and `phoneSyncExporter()` into
`UsageStore.init` (`HeadroomApp.swift:829-858`). The store holds them as optional `let`s
(`UsageStore.swift:180-181,211-226`).

**Mac observation of KVS: none.** No `didChangeExternally` observer, no `synchronize()` call
outside the `--dump-phone-sync` diagnostic (`HeadroomApp.swift:394-430`), and no observer of
any kind in Core. Observer precedents in the app:
- `DistributedNotificationCenter` theme flips on the always-present menu-bar label `.task`/`.onReceive` (`HeadroomApp.swift:505-540`)
- `NSApplication.didBecomeActive` in `SettingsView.swift:159`
- `willTerminate` in `AccountsSettingsTile.swift:181`

Where a request observer would attach:
- `HeadroomApp.init`, beside `SetupSessions.configure(store:)`, gated by `!DemoFixture.isEnabled` (`HeadroomApp.swift:449-470`)
- or `AppDelegate.startUsageStore` / `applicationDidFinishLaunching` (`736-755`)

Mirror KTD9-style guards: no `--demo`, no `--render-*`, no XCTest host (`usesInertNotificationClient`, `HeadroomApp.swift:1177-1188`).

**Phone-request hooks in Core:**
- `refreshAll()` (`UsageStore.swift:772-794`): `markAllDue` + `dispatchDue`, waits for user work, then exports once.
- `refreshAccountNow(_:)` → `scheduler.requestPriority` (`796-798`; scheduler `AccountProbeScheduler.swift:136-151`), front of the lane, bypasses the duty-cycle gate.
- `markAllDue` re-inserts keys that already finished, so a second `refreshAll` during a running one is a real second pass (`AccountProbeScheduler.swift:121-133,501-508`).
- `isRefreshing` / `refreshProgress` (`UsageStore.swift:136-143`), with `RefreshProgress {total, completed, lastLanded}` (`49-60`).
- The receipt copy `RefreshReceipt.line` is pure, but it lives in the **Mac app module** (`HeadroomApp/UI/PopoverView.swift:723-747`, tested in `Tests/HeadroomAppTests/RefreshReceiptTests.swift`). Sharing it with the phone means lifting it into Core.
- Titles come from `refreshReceiptTitle(for:)`: "Claude" alone, or "Claude Work" when there are several accounts (`UsageStore.swift:719-725`). It contains no email.

Request handling must:
- dedupe by request ID
- ignore stale requests (KVS can replay the last value at launch; unverified)
- skip when sync is off or a refresh is already running
- rate-limit, because every Claude probe is a full CLI process (AGENTS.md cost warning)

**Phone read path.**
- `IOSCompanionView` listens for `didChangeExternallyNotification` but ignores its `userInfo`, and calls `refresh()` on appear, on scene active, on open-URL, and on KVS change (`IOSCompanionView.swift:47-63`). `refresh()` has a 550 ms floor (`162-240`).
- Pull-to-refresh is `MirrorView`'s `.refreshable { await onRefresh() }` (`MirrorView.swift:58`), which lands in that same `refresh()`. A "check now" write must come from the pull gesture only, not from `refresh()` in general.
- **The iOS widget extension reads KVS directly** and copies newer remote envelopes into the App Group cache (`HeadroomIOSTimelineProvider.swift:46-67`). The app does the same with a slightly different `adoptable` rule (`IOSCompanionView.swift:262-268`).
- To keep the widget path simple, leave `widget-snapshot.json` and the v3 key as the widget input, and put multi-account data under new keys in a separate cache file. Both sides write the cache today, and they'd race if it changed shape.

#### 2. Versioning gates

- **Inner snapshot:** `WidgetSnapshotEnvelope.schemaVersion = 3`, `oldestSupportedSchemaVersion = 1`, `supports(...)` is the range (`WidgetSnapshotModels.swift:5-7,77-79`).
  - `init(from:)` throws on an unsupported version (`41-61`).
  - Schemas below 3 go through `LegacyWidgetProviderSummary` migration (`54-58`).
  - Additive fields use `decodeIfPresent`, and unknown keys are ignored.
- **Outer wrapper:** `SyncedWidgetSnapshotEnvelope.schemaVersion = 1`, matched exactly (`SyncedWidgetSnapshotModels.swift:3-4,56`).
  - A header-first decode (`SyncedWidgetSnapshotHeader`, `67-75`) returns `.incompatibleSchema` before a full decode, so a future shape is never reported as corrupt.
  - `newestValid` returns incompatible even when a valid local copy exists (`82`).
- **App Group cache:** `WidgetSnapshotCache.decode` uses the same header-then-range check (`WidgetSnapshotCache.swift:157-174`).
  - `write` refuses to overwrite a file whose version is outside the range (`110-113,146-155`), so a downgrade locks the cache.
- **On an unknown version:**
  - **iOS app:** `IOSWidgetSnapshotState.resolve` puts incompatible ahead of content on either side (`Sync/IOSWidgetTimelineMapping.swift:56-58`). The screen is "Update Needed" (`IOSCompanionView.swift:126-133`), and Settings diagnostics show "Schema mismatch" (`SettingsSheetView.swift:206`).
  - **iOS widget:** `.iosIncompatibleSchema` status card (`HeadroomIOSWidgetView.swift:121-122`).
  - **macOS widget:** reads only the App Group file and shows the `.incompatibleSchema` view (`HeadroomTimelineProvider.swift:50-71`; `HeadroomWidgetEntry.swift:15-25`; `HeadroomWidgetView.swift:63`).
  - **Mac diagnostic:** `--dump-phone-sync` prints the result (`HeadroomApp.swift:410-416`).
- **Tests that pin this** (all in `Tests/HeadroomCoreTests/`):
  - `SyncedWidgetSnapshotModelsTests.swift`:
    - `:18` pins schema 3 and wrapper 1
    - `:29`, `:156`, `:218`, `:253` cover legacy migration
    - `:43` `futureSnapshotSchemaIsIncompatible`
    - `:127` `unsupportedInnerSchemaWinsOverMalformedPayload`
    - `:274` `unsupportedSchemaReturnsIncompatible`
    - `:304` `newestValidSurfacesIncompatibleRemoteWithoutFallingBack`
  - `iCloudSnapshotSyncTests.swift:9` single key, `:58` missing/corrupt/incompatible.
  - `WidgetSnapshotCacheTests.swift:121` `futurePrimaryFileDoesNotFallBackOrGetOverwritten`.
  - `IOSWidgetTimelineMappingTests.swift:51`, `:57`.
  - `DemoScreenshotDataVariantsTests.swift:65`.
- **Second versioning precedent:** `UsageContinuityCache` (`Engine/UsageContinuityCache.swift:77,104-114`), tested by `UsageContinuityCacheTests.swift:273` (future payload not overwritten) and `:374` (v2 ignores unknown keys).
- **Unknown-value fallback pattern for new enums:** `WidgetLayoutStyle(storedValue:)` (`WidgetLayoutStyleTests.swift:10,16`).

#### 3. Shared cross-platform SwiftUI folder (precedent: `HeadroomWidgetSharedUI`)

- **XcodeGen:**
  - The folder is compiled *into* each consuming target by path: macOS app (`project.yml:36-38`), macOS widget (`71`), iOS widget (`131`).
  - `HeadroomCore` is a **macOS-only** static lib (`20-28`), so the iOS targets compile Core files by path:
    - a hand-picked list of 9 `Models/` files (`99-109`, `139-149`)
    - `Widgets/` minus the projector, and all of `Sync/` (`110-113`, `150-153`)
  - So any new Core file a shared view touches must be reachable from that list. A `Models/` file outside it breaks the iOS build (the `BUGS.md:366-372` precedent).
  - A file can be compiled into several targets by path. Precedent: `HeadroomWidgetConfigurationIntent.swift` is in both extensions (`project.yml:136-137`). Use the same approach for App Intents shared by the app and the widget extension.
- **SPM** (`Package.swift:16-31`):
  - It's a `.target(name: "HeadroomWidgetSharedUI", dependencies: ["HeadroomCore"])` plus a library product.
  - `HeadroomApp` and `HeadroomWidgets` depend on it.
  - No iOS target is in the package. `swift build` only proves macOS, so the iOS compile has to go through xcodebuild.
- **Import guards:**
  - Shared files open with `#if canImport(HeadroomCore) import HeadroomCore #endif` (every file in `Sources/HeadroomWidgetSharedUI/*.swift:1-3`).
  - Mac consumers use `#if SWIFT_PACKAGE import HeadroomWidgetSharedUI #endif` (`WidgetRenderHarness.swift:2-5`, `WidgetStyleGalleryPicker.swift:1-5`, `WidgetPreviewStrip.swift:1-5`, `HeadroomWidgets/Views/HeadroomWidgetView.swift:1-4`).
  - API must be `public` for the SPM module.
- **Redeclaration trap** (`HeadroomWidgetTypography.swift:24-28`):
  - Xcode compiles the shared folder into the Mac app module, so move views rather than copy them.
  - **Name overlaps to resolve before moving:** the iOS app module already declares `UsageBarView` and `ProviderLogoView`, the same names as the Mac's.
  - Shared UI vs the iOS app has **no** top-level type collisions today, and its `Color` init uses a distinct label: shared `Color(styleTint:)`, iOS `Color(_ tint:)` (`HeadroomWidgetStylePrimitives.swift:119-123`; `HeadroomTheme.swift:90-98`). Mac `ProviderStyle`'s `Color` extension is `private` (`ProviderStyle.swift:285`).
- **Resource lookups** break if moved into an SPM module:
  - The Mac brand SVGs load from `Bundle.main` or `Headroom_HeadroomApp.bundle` (`ProviderLogoView.swift:101-108`). Keep `ProviderLogoView` platform-specific (INVENTORY P31).
  - Shared views use `Image(assetName)` from the host's asset catalog (`HeadroomWidgetSharedUI.swift:98-125`). BrandIcons.xcassets is already in the iOS app (`project.yml:98`).
- **Adding `HeadroomWidgetSharedUI` to the iOS app** (S3 gallery):
  - Add `- path: Sources/HeadroomWidgetSharedUI` to `HeadroomIOS` sources.
  - It already compiles against the identical Core file list in the iOS widget extension.
  - Grep confirms it references no extension-only type (no intent or entry types).
  - It imports WidgetKit, which is fine in an app.
  - It reads `widgetRenderingMode` / `showsWidgetContainerBackground` only through `@HeadroomWidgetRendering` (`HeadroomWidgetStylePrimitives.swift:48-61`). Outside a widget these take default values, and `HeadroomWidgetRenderingOverrideKey` exists for posing states.
  - Mac precedent: `WidgetStyleGalleryPicker.swift` and `WidgetPreviewStrip.swift`.
- **Testability:**
  - `HeadroomAppTests` uses `@testable import Headroom` (e.g. `DotMatrixSpinnerTests.swift:1-2`), so shared views compiled into the Mac app module stay testable there.
  - There is **no iOS unit-test target**. Phone-only logic must live in Core to be unit-tested.

#### 4. App Intents, CloudKit, push, background tasks, entitlements

- **App Intents:** only `HeadroomWidgetConfigurationIntent` plus its two `AppEnum`s (`HeadroomWidgets/HeadroomWidgetConfigurationIntent.swift`). That file compiles into the extensions only, never Core or either app. There is no `AppShortcutsProvider` and no `AppIntent` in either app.
- **None of these exist anywhere** in `Sources/`, `project.yml` or `Scripts/`:
  - CloudKit, `registerForRemoteNotifications`, `aps-environment`, `BGTaskScheduler`
  - `UIApplicationDelegateAdaptor` (the iOS app is a bare `App`, `HeadroomIOSApp.swift:4-13`)
  - `ControlWidget`, accessory families
- **`UNUserNotificationCenter`:** Mac app only (`HeadroomApp/UserNotificationClient.swift`). The iOS `Info.plist` has a `headroom` URL scheme and no `UIBackgroundModes`.
- **Entitlements:**
  - Mac app `HeadroomApp.entitlements`: empty `icloud-container-identifiers` array, KVS `$(TeamIdentifierPrefix)$(CFBundleIdentifier)`, app group, **not sandboxed**.
  - Mac widget: sandbox, app group, KVS `…com.kylezantos.headroom`.
  - iOS app and iOS widget: app group and KVS `…com.kylezantos.headroom`.
  - All four share one KVS store.
- **`Scripts/build-app.sh`:**
  - Default builds **strip** the KVS key and the container array (`129-138`).
  - With `HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1` it:
    - sets the team-prefixed KVS ID and adds application-id and team-id (`115-128`)
    - requires **separate** host and widget profiles (`39-45`), validated as "Mac Team Provisioning Profile" (Apple Development) or "Mac Team Direct Provisioning Profile" (Developer ID) (`173-237`)
    - embeds both (`239-250`) and verifies the signed ID (`252-266`)
- **`Scripts/release-app.sh`:**
  - Archives with `CODE_SIGN_STYLE=Automatic` and `-allowProvisioningUpdates`, then exports `developer-id` with automatic signing (`395-450`). Xcode fetches the Direct profiles itself.
  - Verifies the KVS, app group, and profile kind (`302-329`).
  - CloudKit means adding `icloud-services` plus container IDs to `HeadroomApp.entitlements`, and extending the strip list, the verify list, and possibly the export options (finding 5).
- **iOS release checks:** `Scripts/verify-ios-release.sh:155-165` checks only the app group and KVS. A CloudKit or push iOS app needs `aps-environment` plus container checks added there.
- **W9 parity note:**
  - The Mac app could expose the same read-only App Intents; macOS supports App Shortcuts.
  - App Intents metadata is generated only in Xcode builds, not `swift build`.
  - Intents on the phone can read `WidgetSnapshotCache.appGroup()`, which is already compiled into the iOS app.

#### 5. NotificationCoordinator: the "send to phone" hook

- **Decision point:** `UsageStore.merge` runs `evaluateNotifications` only on a fresh `.live` merge (`UsageStore.swift:899-924`, gate at `915-917`; context built at `930-948`).
  - The context includes `accountLabel`, which is nil unless the provider shows more than one account.
  - The coordinator (`Notifications/NotificationCoordinator.swift:50-141`) runs `UseItUpEvaluator` and the banked-reset baseline, then calls `post(content)` (`133-141`).
  - **Ledgers are written only when the poster returns `true`** and the account is still attached (`100-104`, `125-129`).
- **Seam:** Core's `NotificationPosting` (`NotificationPosting.swift:5-9`) takes `NotificationContent {identifier, threadIdentifier, title, body}` (`NotificationContent.swift:5-19`).
  - The identifier is deterministic (`use-it-up.<provider>.<account>.<window>.<deadlineMinutes>`, `:47-52`), which makes a natural CloudKit `recordName` for idempotency.
  - It's composed once: `AppComposition.notificationClient` → `NotificationCoordinator(poster:)` (`HeadroomApp.swift:849-854,1171-1197`).
  - The inert guard covers `--demo`, `--render-*`, the XCTest host, and unbundled runs.
- **Cleanest attachment, with no Core change:**
  - Wrap the client in a composite `NotificationPosting` that posts locally and writes the CloudKit record.
  - **Decide the accepted semantics explicitly.**
    - **Local `||` phone:** the ledger is recorded when either one lands. If Mac banners are denied but the phone write succeeds, a later permission grant won't re-fire that limit.
    - **Local only (current):** a Mac with notifications denied would re-propose, and re-write, on every fresh poll.
  - The CloudKit writer must be composed behind the same inert guard. A `CKContainer` in an unentitled process is assumed to throw like `UNUserNotificationCenter.current()` (unverified; note KTD9 at `UserNotificationClient.swift:54-60`).
- **Purge hooks:** `NotificationCoordinator.purge(for:)` (`62-65`) is the place to delete an account's pending records on removal.

#### 6. iOS widget extension: accessory families and ControlWidget

- **Structure today:**
  - One `WidgetBundle` with `HeadroomIOSUsageWidget` (`HeadroomIOSWidgets.swift:4-30`): `AppIntentConfiguration`, kind `HeadroomIOSUnifiedUsageWidget` (`Widgets/HeadroomIOSWidgetConfiguration.swift:1-3`), system small/medium/large.
  - `contentMarginsDisabled`, and `.disfavoredLocations([.iPhoneWidgetsOnMac])`.
  - Entry: `HeadroomIOSWidgetEntry {date, state, style, colorMode}` (`HeadroomIOSWidgetEntry.swift:4-10`).
  - The provider's `resolvedState()` is **private**: it combines demo, cache and KVS and copies newer data into the cache (`HeadroomIOSTimelineProvider.swift:46-67`). The app duplicates the same logic (`IOSCompanionView.swift:209-238`).
- **Reuse:**
  - Extract that read into one shared helper used by the app, the system widget, the accessory widget, the control value provider, and App Intents.
  - The pure parts already live in Core: `IOSWidgetSnapshotState.from/resolve` and `WidgetTimelineSchedule.entryDates/refreshDate` (`WidgetSnapshotModels.swift:600+`).
  - Accessory views should read rendering through `@HeadroomWidgetRendering` (vibrant → `.monochrome`), per the AGENTS.md gotcha.
- **Add accessory as a new `Widget` struct in the same bundle,** with its own kind, view, and family enum (finding 6). `HeadroomWidgetConfigurationIntent`'s Style/Color don't apply to accessories, so they need a `StaticConfiguration` or their own intent.
- **ControlWidget:**
  - Its intent must compile into both the app and the extension; use the by-path pattern at `project.yml:137`.
  - The iOS target is 26.0, so no availability gate is needed there.
  - For macOS parity, the Mac widget extension targets 15.0 (`project.yml:5`), so a Mac control would need `@available(macOS 26, *)`. Whether `WidgetBundleBuilder` accepts an `if #available` branch is unverified.
- **Rendering evidence:** `--render-widgets` already has `ios61` and `ios67` geometries (`WidgetRenderHarness.swift:29-38`), but they're keyed by Core `WidgetFamily`. Accessory renders need a parallel geometry table, not new `WidgetFamily` cases.

#### 7. Tests and harness entry points

| Area | Extend | Run with |
|---|---|---|
| Wire models, versioning, dual publish, request/receipt codecs, coalescer, projector | `Tests/HeadroomCoreTests/` `SyncedWidgetSnapshotModelsTests`, `iCloudSnapshotSyncTests` (+ `MemoryiCloudKeyValueStore`), `WidgetSnapshotProjectorTests`, `WidgetSnapshotCacheTests`, `IOSWidgetTimelineMappingTests` | `swift test` |
| Store export triggers, phone request → refresh, receipts | `UsageStoreTests` (`SpyWidgetExporter` / `FailingWidgetExporter` in `Mocks.swift:279-298`; phone tests `:2023`, `:2049`, `:2179`), `MultiAccountTests` (`:650` Make Main exports, `:1698` primary-only export), `AccountProbeSchedulerTests` | `swift test` |
| Notifications fan-out | `NotificationCoordinatorTests`, `BankedResetNotificationTests`, `UseItUpEvaluatorTests`; app side `Tests/HeadroomAppTests/NotificationClientTests.swift` | swift test / HeadroomAppTests |
| Receipt and stamp copy (if lifted to Core) | Move `Tests/HeadroomAppTests/RefreshReceiptTests.swift` and `PopoverHeaderStatusTests.swift` into Core tests | swift test |
| Shared UI moved out of `HeadroomApp/UI` | Existing `HeadroomAppTests` (`MeterRecipeKeyTests`, `DotMatrixSpinnerTests`, `HeadroomMotionTests`, `OpticalLeadingTests`, `ProviderCardIdentityRowTests`) keep working via `@testable import Headroom` | `./Scripts/build-app.sh --deps-only && xcodebuild -project Headroom.xcodeproj -scheme HeadroomAppTests -destination 'platform=macOS' -derivedDataPath ./.xcode-derived test` |
| Phone UI | `Tests/HeadroomIOSUITests/DemoModeUITests.swift`, `ResponsiveLayoutUITests.swift` (launch args `--demo`, `--demo-stale-api-spend`; env `HEADROOM_UI_TEST_STATE`, `HEADROOM_UI_TEST_RESET_DEMO`) | `xcodegen generate` then `xcodebuild test -project Headroom.xcodeproj -scheme HeadroomIOS -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath ./.xcode-derived-ios CODE_SIGNING_ALLOWED=NO` (from `.context/ios-parity/uitests-r1.log:2`) |
| iOS compile gate | — | `xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOS -destination 'generic/platform=iOS Simulator' build` (and `HeadroomIOSWidgets`) (`docs/plans/2026-10-02-1247-feat-widget-styles-plan.md:574`) |

**Harnesses:**
- `--render-popover <dir>` and `--render-widgets <dir>` are dispatched in `HeadroomApp.swift:38-50`. Both are **macOS-only** (NSWindow capture and `ImageRenderer`), so neither can produce phone screenshots.
- Phone screenshots go through the Simulator:
  - `Scripts/capture-demo-screenshots.sh`: simctl, a 9:41 status bar, launch arg `--demo` → `DemoScreenshotData.isEnabled` (`35-101`). Its macOS half runs `killall Headroom` (`:113`).
  - `Scripts/capture-case-study-shots.sh`: `HEADROOM_PREVIEW=1` / `HEADROOM_PREVIEW_SCREEN=settings` → DEBUG `CompanionPreviewSeed`. Both are headless.
- New phone states (multi-account, receipt, iPad masonry, Settings rows) need `DemoScreenshotData` / `CompanionPreviewSeed` variants plus `simctl` shots.

### Recommendations (sequencing clues)

1. **Foundation first:**
   - Add a KVS seam: remove, change observation with reason and changed keys, quota signal.
   - Add a generic codable-per-key channel and a phone-only publish coalescer with an injectable clock (the `PollingEngine` pattern).
   - Split phone export triggers from widget export triggers.
   - Fix D6.
2. **New-version wire types:**
   - Put them in `Widgets/` or `Sync/` (auto-included in iOS) with their own enums.
   - Keep the v3 projector frozen and add a v3 golden test.
   - Add the multi-account projector to the Mac only, excluded by path in both iOS targets.
3. **Phone reader:** read the new keys and fall back to v3; keep the widget cache on v3.
4. **Request and receipt:**
   - Mac observer composed in `HeadroomApp.init` with demo, harness and test guards.
   - It reads progress from `schedulerUserProgressDidChange`.
   - Lift `RefreshReceipt` to Core.
5. **CloudKit spike** covering build and release script changes (finding 5), then the composite poster.
6. **Widgets, accessories, control, intents** on top of the shared read helper.
