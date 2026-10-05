/// The one switch that moves phone surfaces (app, widgets, Siri, controls) from the build-33
/// loading path to `CompanionSnapshotLoader` (KTD6, KTD13). It stays off until an account-scope
/// candidate passes the signed device gate and Kyle signs off the KTD22 change (P5): the
/// `ubiquityIdentityToken` candidate failed on device, and its KVS-marker replacement is not yet
/// verified there. With it off, hosts lift what the build-33 path reads through the resolver's
/// v3-only rules, so the new screens still render; nothing serves a v4 cache. Remove the switch
/// once adoption is accepted (Definition of Done: no debug flags).
public enum CompanionLoaderAdoption {
    public static let isEnabled = false
}
