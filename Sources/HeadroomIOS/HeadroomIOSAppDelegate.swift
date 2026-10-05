import UIKit

/// U8 step 8 (stub): the app's UIKit delegate, attached through
/// `@UIApplicationDelegateAdaptor` in `HeadroomIOSApp`. U16 fills it with the CloudKit
/// reminder hooks (KTD19: register for remote notifications on every launch, handle the
/// device token). Until then it adds no behavior.
final class HeadroomIOSAppDelegate: NSObject, UIApplicationDelegate {}
