/// The one switch that moves phone surfaces (app, widgets, Siri, controls) from the build-33
/// loading path to `CompanionSnapshotLoader` (KTD6, KTD13). On since 2026-10-05: Kyle approved
/// the KVS scope marker (`CompanionKVSScopeMarker`) in place of `ubiquityIdentityToken`, which
/// failed on device (app and widget differ; nil with iCloud Drive off), and chose everyday-use
/// acceptance over the DEBUG probe (KTD22, P5). Turning it off restores the build-33 path. Remove
/// the switch once 1.5 has shipped with it on (Definition of Done: no debug flags).
public enum CompanionLoaderAdoption {
    public static let isEnabled = true
}
