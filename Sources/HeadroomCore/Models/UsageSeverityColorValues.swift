public extension HeadroomSeverityColorValues {
    static func color(for severity: UsageSeverity, dark: Bool) -> HeadroomRGBColor {
        switch severity {
        case .healthy: healthy(dark: dark)
        case .low: low(dark: dark)
        case .critical: critical(dark: dark)
        }
    }
}
