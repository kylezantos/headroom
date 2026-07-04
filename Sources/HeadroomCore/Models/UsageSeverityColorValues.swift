public extension HeadroomSeverityColorValues {
    static func color(for severity: UsageSeverity) -> HeadroomRGBColor {
        switch severity {
        case .healthy: healthy
        case .low: low
        case .critical: critical
        }
    }
}
