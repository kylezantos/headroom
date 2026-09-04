public extension HeadroomSeverityColorValues {
    static func color(for severity: UsageSeverity, dark: Bool) -> HeadroomRGBColor {
        switch severity {
        case .healthy: healthy(dark: dark)
        case .low: low(dark: dark)
        case .critical: critical(dark: dark)
        }
    }

    /// Meter-bar fill tier (see `BrandColorValues.swift`). Text, icons, and the "Low" pill
    /// keep using `color(for:dark:)`.
    static func fill(
        for severity: UsageSeverity,
        dark: Bool,
        increasedContrast: Bool
    ) -> HeadroomRGBColor {
        switch severity {
        case .healthy: healthyFill(dark: dark, increasedContrast: increasedContrast)
        case .low: lowFill(dark: dark, increasedContrast: increasedContrast)
        case .critical: criticalFill(dark: dark, increasedContrast: increasedContrast)
        }
    }
}
