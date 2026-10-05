# Apple platform research: iPhone/iPad parity round (2026-10-04)

Researcher: framework-docs pass (read-only). Sources are Apple documentation (fetched through the
developer.apple.com JSON doc endpoints, so the quotes are current as of today), WWDC sessions, Apple
DTS forum answers, and Kyle's local provisioning profiles and keychain (read-only). Each answer has a
confidence level. **UNVERIFIED** marks anything a spike has to prove.

## 0. Environment facts that differ from the brief (read first)

- **The toolchain is Xcode 27.0 (27A266a), Swift 6.4, with iOS 27.0 and macOS 27.0 SDKs**, not the
  Xcode 26.6 / Swift 6.3.3 that AGENTS.md states. Build 33 was archived against
  `iPhoneOS27.0.sdk` (`testflight-33.log`). iOS 27 and macOS 27 have shipped: Apple opened App Store
  submissions for the 27 releases on Sep 9, 2026. The deployment targets are still iOS 26 and
  macOS 15, so any iOS 27 API (for example App Intents `ExecutionTargets`) needs an availability
  check. The iOS 27 SDK becomes mandatory for uploads in April 2027. Source:
  [Apple Developer News](https://developer.apple.com/news/).
- **Kyle's Developer ID Application certificate expires Feb 1, 2027, and it was issued by the
  retiring Sub-CA.** Its issuer is `CN=Developer ID Certification Authority, OU=Apple Certification
  Authority`, issued Jul 3, 2026, `notAfter=Feb 1 22:12:15 2027 GMT`. Apple announced on Oct 1, 2026
  that this Sub-CA expires Feb 1, 2027. Apps that are already notarized keep working, but future
  updates must be signed with a new certificate from the **G2** Sub-CA. Both
  "Mac Team Direct Provisioning Profile" files (host and widgets) embed only this certificate, so
  they also need regenerating. **Do the G2 certificate and the CloudKit profile regeneration
  together** (see §1). Source: [Apple Developer News, Oct 1 2026](https://developer.apple.com/news/).
- **Current profiles** (decoded locally, entitlements only):
  - Mac Direct (Developer ID) profile for `com.kylezantos.headroom`: `com.apple.developer.icloud-services = *`,
    `icloud-container-identifiers = []` (empty), `ubiquity-kvstore-identifier = 8D42S4MS38.*`.
    It has no `aps-environment`, no `icloud-container-environment`, and no
    `icloud-container-development-container-identifiers`. (The Mac *development* profile does carry
    the last key.)
  - The iOS dev and App Store profiles for `com.kylezantos.headroom.ios` and `.ios.widgets` have
    empty container arrays and **no `aps-environment`**.
  - Result: CloudKit is permitted at the service level (`*`), but **no container is assigned to any
    App ID yet, and push is not enabled on the iOS App ID**. Every profile that needs CloudKit or
    push has to be regenerated after the portal changes.

---

## 1. CloudKit in a Developer ID-signed, unsandboxed macOS app

**Answer: supported. Confidence: high that it's supported, medium on the exact manual-codesign
recipe (spike it).**

Evidence:
- Apple's capability matrix for macOS lists **iCloud: CloudKit**, **iCloud key-value storage**,
  **Push notifications**, and **App groups** as supported for **Developer ID**.
  [Supported capabilities (macOS)](https://developer.apple.com/help/account/reference/supported-capabilities-macos)
- "Software signed with a Developer ID certificate can also take advantage of advanced capabilities
  such as CloudKit and Apple Push Notifications." [Developer ID](https://developer.apple.com/developer-id/)
- Developer ID CloudKit has worked since Xcode 8 / the macOS 10.12 SDK: "You can export a Developer
  ID signed app and it will work … in the production environment." (Apple staff, 2016.)
  [forum 54125](https://developer.apple.com/forums/thread/54125)
- CloudKit does not need App Sandbox. Every macOS-specific CloudKit failure report found was about
  *sandboxed* apps; see the failure modes below.

How CloudKit picks its environment (the main trap for a hand-signed build):
- "At runtime, CloudKit uses your app's `com.apple.developer.icloud-container-environment`
  entitlement to discover whether you're using a `Development` or `Production` version of your
  provisioning profile." [CKContainer](https://developer.apple.com/documentation/cloudkit/ckcontainer)
  DTS (Ziqiao Chen, Aug 2025) gave the same explanation for an app that was writing to the
  Development container. [forum 795826](https://developer.apple.com/forums/thread/795826)
- TestFlight and App Store builds always use Production whatever the entitlement says
  ([forum 707098](https://developer.apple.com/forums/thread/707098)). **That override does not
  apply to Developer ID.** For Developer ID, Xcode's export writes the entitlement.
  `xcodebuild -help` on Xcode 27: *"iCloudContainerEnvironment … If the app is using CloudKit, this
  configures the com.apple.developer.icloud-container-environment entitlement … defaults to
  Development when development signing or Production when distribution signing."*
  **`Scripts/build-app.sh` signs with `codesign` itself and never goes through Xcode's export, so
  it must add `com.apple.developer.icloud-container-environment = Production` by hand.** Without
  that key, the Mac writes to an environment the App Store iPhone never reads.
- The value is case-sensitive: `Production`, not `production`. A lowercase value got the app
  "Terminated due to code signing error". [forum 17499](https://developer.apple.com/forums/thread/17499)

Steps:
1. **Portal (Certificates, Identifiers & Profiles):** create the container `iCloud.com.kylezantos.headroom`.
   It is permanent: "Once you've created a container, you can't delete or rename it."
   ([Enabling CloudKit](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app))
   Assign it to the App IDs `com.kylezantos.headroom` (Mac) and `com.kylezantos.headroom.ios`
   (iPhone). Enable **Push Notifications** on the iOS App ID. The widget App IDs need no changes.
2. **Certificates:** create the G2 Developer ID Application certificate (see §0).
3. **Regenerate profiles:** Mac Developer ID (Direct) for the host. Regenerate the widget's too,
   only to pick up the new certificate. Regenerate the Mac development profile for local testing,
   and the iOS dev and App Store profiles for `.ios`. The new iOS profiles will carry
   `aps-environment`.
4. **Mac host entitlements, Developer ID path in `build-app.sh`:**
   - `com.apple.developer.icloud-services = [CloudKit]`
   - `com.apple.developer.icloud-container-identifiers = [iCloud.com.kylezantos.headroom]`
   - `com.apple.developer.icloud-container-environment = Production`
   - keep `ubiquity-kvstore-identifier`, `application-identifier`, `team-identifier`
   - Keep the ad-hoc path that deletes all iCloud keys. Restricted iCloud keys in an unprovisioned
     signature get the process SIGKILLed, which the script already guards against. So CloudKit,
     like KVS today, works only in provisioned builds.
5. **`aps-environment` on the Mac: not needed** if the Mac only *writes* records, which is the
   design in §2. The Mac needs `com.apple.developer.aps-environment`, Push enabled on the Mac App
   ID, and `NSApplication.registerForRemoteNotifications()` only if it must *receive* CloudKit
   pushes (for example, phone-to-Mac requests over CloudKit instead of KVS).
   [com.apple.developer.aps-environment](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.aps-environment)
6. **Schema:** create the record type and indexes in Development (CloudKit Console), then
   **deploy to Production before release.** "The production server generates errors when your app
   tries to add record types or add new fields." ([CKContainer](https://developer.apple.com/documentation/cloudkit/ckcontainer))
   "Attempting to create a subscription directly in the production environment results in an
   error." ([CKSubscription](https://developer.apple.com/documentation/cloudkit/cksubscription))
7. **Verify:** `codesign -d --entitlements :- Headroom.app` shows the keys. Then the notarized
   build launches, `CKContainer.accountStatus` returns `.available`, a test save succeeds, and the
   record appears under **Production** in CloudKit Console.

Known failure modes:
- A profile that lacks the container, or an entitlement value the profile doesn't allow → AMFI
  kills the app at launch, or CloudKit returns bad-container / not-entitled errors.
  Gatekeeper "will evaluate the validity of your Developer ID provisioning profile at every app
  launch." ([Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/))
- **UNVERIFIED:** the current Direct profile has no `icloud-container-environment` key at all.
  Xcode-exported Developer ID apps carry `…environment = Production` and launch, which suggests AMFI
  doesn't check this key against the profile. Proving that for a hand-signed bundle is the first
  thing the spike must do.
- Empty `icloud-container-identifiers` / `icloud-services` arrays break Xcode signing with
  "Provisioning profile missing entitlement" (Mar 2026, macOS 26.2 / Xcode 26.3).
  `HeadroomApp.entitlements` ships an empty container array today; the script deletes it on the
  ad-hoc path. [forum 818501](https://origin-devforums.apple.com/forums/thread/818501)
- Environment mismatch while testing: an Xcode-run iPhone build uses **Development**, while a
  Developer ID Mac build set to Production uses **Production**. The two never see each other's
  records or pushes. Test as pairs: (Apple Development Mac + Xcode iPhone, both Development) or
  (Developer ID Mac + TestFlight iPhone, both Production).
- No iCloud account, or iCloud turned off for the app → `CKAccountStatus.noAccount`, `.restricted`,
  or `.temporarilyUnavailable`. Show a typed state for this, not a silent failure.
- Private-database data "counts toward the user's iCloud storage quota" ([CKContainer](https://developer.apple.com/documentation/cloudkit/ckcontainer)).
  If the user's iCloud is full, saves fail with `quotaExceeded`.
- Sandboxed Mac processes on macOS 26 have hit `deny mach-lookup com.apple.cloudd` with Mac App
  Store and TestFlight profiles. This is not relevant to the unsandboxed host, but **don't call
  CloudKit from the sandboxed Mac widget extension.** (Search-result summary of a 2026 forum
  thread; the thread itself wasn't opened. Low confidence.)
- Editing an App ID's capabilities marks its existing profiles "Invalid" in the portal. Copies of
  the Mac app already installed embed the old Direct profile. **UNVERIFIED** that the portal status
  has no effect on them; installed copies are expected to keep launching because the profile's
  signature and 18-year expiry are unchanged. Check this by relaunching an installed 1.4 build
  after the portal change.

---

## 2. Visible iPhone alerts from CloudKit subscriptions (no server)

**Answer: works. Confidence: high on the mechanism, medium on dynamic text through record fields
(spike it).** The iPhone shows a high-priority alert pushed by CloudKit even when the app isn't
running, as long as the user has allowed notifications and the app has registered for remote
notifications.

What the docs say:
- Subscriptions are per user, and changes from *any* device trigger them: "A subscription applies
  only to the user that creates it. When a subscription registers a change … it sends push
  notifications to the user's devices … When appropriate, the server excludes the device where the
  change originates." ([CKQuerySubscription](https://developer.apple.com/documentation/cloudkit/ckquerysubscription))
  "…sends push notifications to all devices with that subscription except for the one that makes
  the original changes." ([CKSubscription](https://developer.apple.com/documentation/cloudkit/cksubscription))
  → **A record the Mac saves does trigger the subscription on the iPhone signed in to the same
  Apple Account.** It also triggers on that user's iPad. Testing on a single device shows nothing
  (DTS QA1917; [forum 801498](https://developer.apple.com/forums/thread/801498): "you cannot send
  push notifications to the same device that is modifying a record").
- Visible versus silent: "If you don't set any of the alertBody, soundName, or shouldBadge
  properties, CloudKit sends the push notification using a lower priority and doesn't display any
  content." ([NotificationInfo](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class))
  "High-priority notifications are visual and the system displays them to the user. Visual
  notifications need the user's permission." ([CKQueryNotification](https://developer.apple.com/documentation/cloudkit/ckquerynotification))
- iPhone requirements:
  - the `aps-environment` entitlement. Xcode adds it with CloudKit; the profile must contain it,
    which today's don't.
  - `UNUserNotificationCenter.requestAuthorization` for alerts and sound.
  - `UIApplication.shared.registerForRemoteNotifications()` on every launch. QA1917: "it's not
    automatic even with CloudKit enabled." ([QA1917](https://developer.apple.com/library/archive/qa/qa1917/_index.html))
  - Background Modes are *not* needed for visible alerts; they're only for silent pushes.
  - Each device must open the app once so it registers.
  - Force-quitting the app does not block visible alerts. It does drop silent pushes.
- Save the subscription **from the iPhone**, the device that holds `aps-environment`. A project
  outside Apple reports that an app without `aps-environment` can't hold a push subscription (low
  confidence). Saving from the iPhone sidesteps the question.

Recommended zone and record design ("one record per reminder event"):
- Custom zone `Reminders` in the **private** database. The default zone also works for query
  subscriptions, but a custom zone allows atomic batches, change tokens, and later zone or database
  subscriptions.
- Record type `ReminderEvent`: `title` and `body` (strings, **≤100 characters each**, because
  CloudKit "may truncate strings with a length greater than 100 characters"), plus `provider`,
  `kind` (use-it-up / banked-reset), and `firedAt` (date). Use a deterministic record name, for
  example `provider.account.window.resetEpoch`. A retried save then can't create a duplicate alert:
  saving an existing record is a modification, and the subscription fires only on creation.
- Subscription: `CKQuerySubscription(recordType: "ReminderEvent", predicate: NSPredicate(value: true),
  subscriptionID: "reminder-events", options: [.firesOnRecordCreation])` with `zoneID = Reminders`.
  - `NotificationInfo.titleLocalizationKey` / `alertLocalizationKey` hold format keys that exist in
    the **iOS app's** string catalog (for example `"%1$@"`).
  - `titleLocalizationArgs = ["title"]` and `alertLocalizationArgs = ["body"]`. These are field
    names CloudKit reads from the triggering record; values must be strings, numbers, or dates.
    ([alertLocalizationArgs](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class/alertlocalizationargs))
  - `soundName = "default"`, plus `collapseIDKey` if repeats should replace each other.
  - A fixed `alertBody` can't vary per event, so per-event text has to come through localization
    args or a Notification Service Extension (`shouldSendMutableContent`).
  - **Use a query subscription, not a zone or database subscription.** Only query notifications
    carry the triggering record's fields. (Inference from the notification types; **UNVERIFIED**
    that zone and database subscriptions can't fill localization args. The spike settles it.)
  - Don't put alert fields in `encryptedValues`. **UNVERIFIED**, but encrypted fields are almost
    certainly unavailable to push payloads.
- Housekeeping: the Mac deletes `ReminderEvent` records after a few days. Deletes don't fire a
  creation-only subscription. Records are tiny, but they still count against the user's iCloud
  storage.

Latency and delivery honesty:
- **No SLA.** APNs is "a best-effort service" that "may reorder notifications." It "stores only one
  notification per bundle ID": if the iPhone is offline and two reminders fire, the user usually
  gets only the latest. ([Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns))
  "Because the system coalesces notifications, don't rely on them for specific changes." (CloudKit
  subscription docs.)
- In practice, high-priority CloudKit pushes usually arrive within seconds. **UNVERIFIED**: no
  Apple number exists, so measure it in the spike.
- NotificationInfo has no interruption-level field. Focus and Scheduled Summary can hold a
  reminder. A Notification Service Extension could raise it to `.timeSensitive`, but that needs the
  Time Sensitive capability (**UNVERIFIED**; probably out of scope).
- Inherent to having no server: if the Mac is asleep or off, nothing fires. Product copy should
  say reminders come from the Mac.
- Subscriptions belong to the user, not the device, so deleting the subscription on one device
  turns alerts off on all of them. Per-device opt-out is the iOS notification permission.

Quotas: Apple publishes no rate limits for the private database. Handle `requestRateLimited`,
`zoneBusy`, and `serviceUnavailable` by honoring `CKErrorRetryAfterKey`
([WWDC16 CloudKit Best Practices](https://wwdcnotes.com/documentation/wwdc16-231-cloudkit-best-practices/)).
A record holds at most 1 MB, not counting assets ([CKRecord](https://developer.apple.com/documentation/cloudkit/ckrecord)).
Storage counts against the user's iCloud quota.

**Could CloudKit carry the multi-account snapshot instead of KVS?** Possible, but the trade is
worse. **Recommendation: keep KVS for the snapshot and use CloudKit only for alerts. Confidence:
medium-high.**

| | NSUbiquitousKeyValueStore | CloudKit private DB |
|---|---|---|
| Size | 1 MB total, 1024 keys, 1 MB per value | 1 MB per record (more with CKAsset) |
| User iCloud quota | values don't count (only key strings do, per the archived iCloud Design Guide) | counts |
| Getting updates to the phone | system syncs on its own; `didChangeExternally` while running | needs silent pushes plus a fetch. Silent pushes are throttled: "don't try to send more than two or three per hour" ([Pushing background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)), dropped when force-quit, and widgets can't receive them |
| Widget push | n/a | `WidgetPushHandler` needs a server to send to the widget's push token; CloudKit can't target it |
| Complexity | already shipped | schema, zones, change tokens, conflict handling, environment parity |
| Latency | several times per minute at best | similar for foreground fetches; no better for background or widgets |

---

## 3. NSUbiquitousKeyValueStore limits, throttling, latency

**Confidence: high on the documented limits, medium on latency (no SLA).**

Documented limits ([NSUbiquitousKeyValueStore](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore)):
- No more than **1024 keys**.
- **1 MB total** across all values.
- **1 MB maximum per value**.
- Keys up to **128 UTF-16 characters**, and keys don't count toward the 1 MB. The archived iCloud
  Design Guide says **64 bytes UTF-8**, so keep keys ≤64 ASCII characters to satisfy both.
- A key that is too long **raises an exception**. A write that exceeds the quota "fails and the
  system doesn't add the keys or values to the store," and the system posts
  `didChangeExternallyNotification` with `NSUbiquitousKeyValueStoreQuotaViolationChange`.
  ([QuotaViolationChange](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestorequotaviolationchange))
  → The quota observation in U4-C is the right safeguard. The v3 and v4 payloads share the same
  1 MB.

Throttling and latency:
- "Don't rely on keys and values being available on the person's other devices immediately …
  iCloud determines the best time … **Typically, iCloud limits updates to several times per
  minute.**" `synchronize()` "doesn't force the system to write new keys and values to iCloud …
  it notifies iCloud that new keys and values are available." ([synchronize()](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore/synchronize()))
- DTS (Ziqiao Chen, Aug 2025): sync "happens shortly after a CloudKit app is launched (KVS is
  based on CloudKit)." [forum 796134](https://developer.apple.com/forums/thread/796134)
- Community measurement (not Apple): "about 10–20 seconds" when conditions are good. Frequent
  changes make iCloud reduce sync frequency, "potentially extending synchronization times to
  several minutes." ([fatbobman](https://fatbobman.com/en/posts/nsubiquitouskeyvaluestore/))
- The doc also says "Don't store personal or sensitive information … stores the information on
  disk in an unencrypted format." The redaction-safe snapshot rule matters here: no emails or
  account IDs in KVS.
- Doc inconsistency: the class page says you "must distribute your app through the App Store or
  Mac App Store." The capability matrix says Developer ID supports KVS, and Headroom's shipped
  Mac-to-iPhone sync is the practical evidence that it works.

What this means for U5-B (pull-to-refresh asks the Mac to check now):
- The phone-to-Mac direction works: the Mac app is always running and observes
  `didChangeExternally`.
- Expect **about 10–30 s typical, minutes under throttling, and a wait until wake if the Mac is
  asleep**. The phone UI needs an honest pending state and a timeout ("Your Mac hasn't answered
  yet"). The small spike stays warranted.
- Use a monotonically increasing request token (UUID plus timestamp), never a boolean. Have the
  Mac echo `lastHandledRequestID` in its next publish. Coalesce: one request in flight, and
  rate-limit to about one per 30–60 s.
- `didChangeExternally` never fires for a device's own writes. Call `synchronize()` right after
  writing the request key; the archived guide says it is meant for "fast-as-possible upload."
- Split per-provider keys: fine at 1024 keys. Writes to separate keys sync independently, but the
  "several times per minute" throttle applies to the store as a whole, so coalesced publishes
  still matter.

---

## 4. App Intents: Siri and Shortcuts read-only answers (iOS 26, with iOS 27 notes)

**Confidence: high on placement and phrase rules, medium on iOS 27 Siri behavior.**

- **Placement:** "Include this type [AppShortcutsProvider] in your app, app extension, Swift
  package, or library … Define your shortcuts in the same place you define the app intents."
  ([App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts))
  iOS 26 added App Intents in **Swift packages and static libraries** through `AppIntentsPackage`.
  ([WWDC25 275](https://developer.apple.com/videos/play/wwdc2025/275/),
  [AppIntentsPackage](https://developer.apple.com/documentation/appintents/appintentspackage))
  → **Recommendation:** put the read-only intents, the `ProviderOption: AppEnum`, and the single
  `AppShortcutsProvider` in the **iOS app target**, or in a shared package registered from the app
  through `AppIntentsPackage` if a control also needs them. Keep them out of the widget extension.
- **Phrases:** every phrase must contain `\(.applicationName)`. Parameters in phrases must be
  `AppEnum` or `AppEntity`. The limit is **10 App Shortcuts per app**.
  ([WWDC22 10170](https://developer.apple.com/videos/play/wwdc2022/10170/),
  [forum 710816](https://developer.apple.com/forums/thread/710816))
  Example: `"How much \(\.$provider) is left in \(.applicationName)"`. The spoken name comes from
  the bundle display name ("Headroom"), not the App Store name "Headroom by Kyle Zantos".
- **Read-only result:** `perform() async throws -> some IntentResult & ReturnsValue<…> &
  ProvidesDialog` (optionally `& ShowsSnippetView`). Use `IntentDialog(full:supporting:)`. Siri
  reads the full string on voice-only devices.
  ([Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent);
  [WWDC26 343](https://developer.apple.com/videos/play/wwdc2026/343/))
  The current `IntentDialog` doc: "When someone performs an action with Siri AI that invokes your
  app intent, the system might not display the IntentDialog you return." → **Also return a
  structured value**, so Siri on iOS 27 can phrase its own answer. Every answer should state that
  the data is as of the last sync from the Mac (honesty principle).
- **`supportedModes`** (new in iOS 26) replaces `openAppWhenRun`. Use `.background` for read-only
  intents. ([supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes))
- **Coexistence with `HeadroomWidgetConfigurationIntent`:** each bundle carries its own App Intents
  metadata. The widget extensions keep their `WidgetConfigurationIntent` and AppEnums, and the app
  adds its own types. Name types distinctly (for example `UsageProviderOption`) to avoid confusion
  across targets.
  - `isDiscoverable` defaults to `true`, and discoverable intents appear in Siri, Spotlight, and
    Shortcuts. ([isDiscoverable](https://developer.apple.com/documentation/appintents/appintent/isdiscoverable))
    The existing configuration intent doesn't set it.
  - **UNVERIFIED** whether a `WidgetConfigurationIntent` shows up as a Shortcuts action; check after
    adding the app's intents.
  - **Any control "Check now" intent must set `isDiscoverable = false`**, or it becomes a Siri and
    Shortcuts *action*, contradicting W9's "no actions."
- **iOS 27 Siri:** SiriKit is deprecated, and App Intents plus **App Schemas** drive the new Siri.
  No schema domain fits usage meters: the domains are audio, calendar, camera, clock, mail, maps,
  messages, notes, phone, photos, reminders, search, and the Shortcuts-specific ones
  ([App schema domains](https://developer.apple.com/documentation/appintents/app-schema-domains)).
  So App Shortcuts with phrases remain the path. `AppShortcutsProvider` is not deprecated in the
  current docs.
  - iOS 27-only additions to gate behind availability checks: `ExecutionTargets` (choose
    app, App Intents extension, or widget extension), `LongRunningIntent`, `SyncableEntity`.
    ([WWDC26 345](https://developer.apple.com/videos/play/wwdc2026/345/))
  - Without Apple Intelligence, Siri matches the defined phrases. **UNVERIFIED** how loosely
    iOS 27's new Siri matches a phrase-only App Shortcut; test on device.

---

## 5. Control Center controls (ControlWidget)

**Confidence: high.**

- Structure: a `ControlWidget` with `StaticControlConfiguration` (or `AppIntentControlConfiguration`
  for configurable controls) wrapping a `ControlWidgetButton` (an `AppIntent` or `OpenIntent`
  action) or a `ControlWidgetToggle` (`SetValueIntent`). Declare it in the widget extension's
  `WidgetBundle`, which can mix widgets and controls; bundle order is gallery order. The value
  comes from `ControlValueProvider.currentValue()` (async; can read the App Group). Refresh with
  `ControlCenter.shared.reloadControls(ofKind:)` or push. **`ControlPushHandler` needs a server,
  so without one, refresh from the app.**
  ([Creating controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system),
  [Controls collection](https://developer.apple.com/documentation/widgetkit/controls-collection))
- **"Open Headroom":** `OpenIntent`. "The system requires the Target Membership of the app intent
  to be set to both the app and the widget extension to open the app."
- **"Ask my Mac to check now":** an `AppIntent` button.
  - **UNVERIFIED** which process runs it on iOS 26 when the intent belongs to both targets. It runs
    in the widget extension by default; iOS 27's `ExecutionTargets` makes this explicit.
  - A KVS write from the short-lived extension should call `synchronize()` before returning.
    Delivery from an extension is **UNVERIFIED**; one 2021 forum post claims extension writes wait
    for the main app.
  - Safer fallback: an `OpenIntent` that opens the app, which then writes the request key.
- **What a control can show:** "Controls contain a symbol image, a title, and, optionally, a value."
  - In Control Center: the symbol, plus title and value at larger sizes.
  - On the Lock Screen: **symbol only**.
  - On the Action button: symbol plus value in the Dynamic Island.
  ([HIG Controls](https://developer.apple.com/design/human-interface-guidelines/controls))
  - `ControlWidgetButton(action:label:actionLabel:)`: `actionLabel(isActive)` shows a subtitle
    while the action runs, such as "Asking your Mac…".
    ([doc](https://developer.apple.com/documentation/widgetkit/controlwidgetbutton/init(action:label:actionlabel:)))
  - Apple publishes no character limit; keep the value very short ("42% left").
  - `privacySensitive()` redacts the value while the device is locked.
- **macOS: yes.** `ControlWidgetButton`, `ControlWidgetToggle`, `StaticControlConfiguration`, and
  `ControlValueProvider` are available on **macOS 26.0+** (doc availability).
  - "On Mac, people place controls from your macOS app in Control Center or as menu bar items."
    ([Controls collection](https://developer.apple.com/documentation/widgetkit/controls-collection))
  - WWDC25: "Controls can be added in the Control Center … Controls can also be placed directly on
    the menu bar." ([WWDC25 278](https://developer.apple.com/videos/play/wwdc2025/278/))
  - iOS apps running on Apple silicon Macs can also provide controls, but Mac availability of the
    iPhone app is off, so **Mac controls must come from the Mac app's widget extension (`HeadroomWidgets`)**
    behind `@available(macOS 26, *)`, since the Mac app targets macOS 15.
  - Parity: a Mac "Check now" or "Open Headroom" control is possible. A menu-bar control mostly
    duplicates Headroom's own menu bar item; record that in the plan as a deliberate parity choice.

---

## 6. Lock Screen accessory widgets (accessoryCircular / Rectangular / Inline)

**Confidence: high on APIs, medium on the iOS 26/27 user-facing changes (sources outside Apple).**

- Rendering: Lock Screen widgets render in **`.vibrant`** mode: "The system desaturates the widget,
  making a monochrome version … The system displays vibrant widgets on the Lock Screen on iPhone."
  ([vibrant](https://developer.apple.com/documentation/widgetkit/widgetrenderingmode/vibrant))
  `.accented` applies to the Home Screen's tinted and clear glass modes (iOS 26) and to watch faces.
  Use `widgetAccentedRenderingMode` for images.
  ([WWDC25 278](https://developer.apple.com/videos/play/wwdc2025/278/),
  [WidgetKit updates](https://developer.apple.com/documentation/updates/widgetkit))
  Headroom already routes rendering mode through `@HeadroomWidgetRendering`.
- iOS 26: no new accessory-family APIs; the June 2025 WidgetKit updates list none. User-facing
  changes:
  - Lock Screen widgets can sit at the **top or the bottom** of the screen.
  - Widgets slide down when the adaptive clock expands.
  - The Lock Screen is drawn in Liquid Glass.
  - iOS 26.2 added a Liquid Glass slider.
  ([MacRumors](https://www.macrumors.com/2025/09/16/ios-26-whats-new-iphone-lock-screen/))
- iOS 27 (third-party reports):
  - a compact clock that can share the widget row
  - a Lock Screen glass-opacity slider that affects widgets
  - an Extra Large Home Screen widget size
  ([9to5Mac](https://9to5mac.com/2026/08/05/ios-27-lock-screen-customization/),
  [mucahitk](https://mucahitk.com/blog/ios-27-widgets-whats-new))
  **UNVERIFIED** against Apple docs; the Apple WidgetKit updates page shows no 2026 entry yet.
- **macOS: none.** `accessoryCircular`, `accessoryRectangular`, and `accessoryInline` list
  iOS 16+, iPadOS 16+, Mac Catalyst, watchOS 9+, and (circular/rectangular) visionOS 27. **They
  have no macOS availability.**
  ([accessoryCircular](https://developer.apple.com/documentation/widgetkit/widgetfamily/accessorycircular))
  → This is a documented parity exception: macOS has no accessory widget surface.
- Lock Screen widgets on iPad need iPadOS 17+, which is covered.

---

## 7. App Store Connect: "You do not have required contracts to perform an operation"

**Cause: an agreement the Account Holder hasn't accepted. Confidence: high. Which revision:
medium.**

- The error (HTTP 403, `FORBIDDEN_ERROR.CONTRACT_NOT_VALID`) means the team lacks a currently
  accepted agreement. DTS (Quinn, Dec 2025): "only the Account Holder is allowed to *accept* legal
  agreements." ([forum 809934](https://developer.apple.com/forums/thread/809934))
  Fix in [forum 744140](https://developer.apple.com/forums/thread/744140): "go to the website and
  click 'accept' on the latest version of the developer agreement."
- Most likely trigger: Apple revised the **Apple Developer Program License Agreement** on **Aug 18,
  2026**, adding the EU business terms, "effective October 1, 2026." The failed upload ran on
  Oct 4. There were earlier revisions on Jun 8 and Jun 18, 2026. Any one of them left unaccepted
  produces this error. ([Apple Developer News](https://developer.apple.com/news/))
- Free apps need no separate contract: "By joining the Apple Developer Program, you automatically
  distribute free apps under the Apple Developer Program License Agreement." The **Paid Apps
  Agreement is not needed** for a free iPhone app with no In-App Purchases.
  ([Sign and update agreements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements))
- **What to tell Kyle:**
  1. Kyle is the Account Holder of the individual team 8D42S4MS38. Sign in at
     developer.apple.com/account and accept the updated **Apple Developer Program License
     Agreement** from the review banner.
  2. Open App Store Connect → Business → Agreements and accept anything listed as pending.
  3. Retry the upload. It may take a few minutes to propagate; forum reports mention up to a day.
- This blocks TestFlight uploads; it isn't a signing problem.

---

## Spike checklist (gates S5-C and U5-B)

1. Hand-signed, notarized Developer ID Mac build with the CloudKit entitlements (`Production`) and
   a regenerated Direct profile on the G2 certificate. It must launch on a clean Mac, return
   `accountStatus = .available`, and land a test record in **Production** in CloudKit Console.
2. TestFlight iPhone build with `aps-environment` that saves a `CKQuerySubscription`, with
   localization args, from the iPhone. The Mac creates a `ReminderEvent`, and the iPhone, locked
   with the app killed, shows title and body from the record fields. Measure latency over
   about 10 trials.
3. KVS phone-to-Mac request key: measure write-to-`didChangeExternally` time on the Mac, awake,
   over about 10 trials. Repeat with the phone writing from a control and widget extension if a
   control writes it.
4. Relaunch an installed Mac 1.4 build after the App ID capability change and profile
   regeneration, to confirm installed copies keep launching.

## Evidence against settled decisions

None of the settled decisions is ruled out. Constraints the plan should absorb:

- **S5-C:**
  - Alert text must come from record fields through localization args (≤100 characters) or a
    Notification Service Extension.
  - An offline iPhone usually gets only the latest alert.
  - Alerts reach every device of the user, including iPad.
  - The Mac must be awake.
  - Needs new profiles, a container, schema deployment, and the G2 certificate.
- **U5-B:** latency is throttled to "several times per minute" with no SLA. The UI needs a
  timeout state.
- **W9 versus controls:** a control's action intent needs `isDiscoverable = false` to keep Siri
  and Shortcuts read-only.
- **Parity:** macOS 26+ supports third-party controls (Control Center and menu bar); accessory
  families have no macOS surface.
