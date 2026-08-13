import Foundation

/// Allowlisted presentation values read from RevenueCat Offering metadata.
///
/// The dashboard selects bundled, localized experiences rather than delivering remote
/// marketing copy. That keeps every variant reviewable, accessible, and available in
/// every language VaultBox supports.
struct PaywallConfiguration: Equatable, Sendable {
    enum Layout: String, Sendable {
        case classic
        case privacyStat = "privacy_stat"
    }

    enum DefaultPlan: String, Sendable {
        case annual
        case weekly
    }

    static let hardPaywallMetadataKey = "isHard"
    static let layoutMetadataKey = "paywallLayout"
    static let defaultPlanMetadataKey = "defaultPlan"
    static let trialTimelineMetadataKey = "showTrialTimeline"

    static let defaultIsHardPaywallEnabled = true
    static let fallback = PaywallConfiguration(
        isHardPaywallEnabled: defaultIsHardPaywallEnabled,
        layout: .classic,
        defaultPlan: .annual,
        showsTrialTimeline: true
    )

    let isHardPaywallEnabled: Bool
    let layout: Layout
    let defaultPlan: DefaultPlan
    let showsTrialTimeline: Bool

    init(metadata: [String: Any]) {
        isHardPaywallEnabled = Self.bool(
            metadata[Self.hardPaywallMetadataKey],
            fallback: Self.defaultIsHardPaywallEnabled
        )
        layout = Self.token(
            metadata[Self.layoutMetadataKey],
            as: Layout.self
        ) ?? .classic
        defaultPlan = Self.token(
            metadata[Self.defaultPlanMetadataKey],
            as: DefaultPlan.self
        ) ?? .annual
        showsTrialTimeline = Self.bool(
            metadata[Self.trialTimelineMetadataKey],
            fallback: true
        )
    }

    private init(
        isHardPaywallEnabled: Bool,
        layout: Layout,
        defaultPlan: DefaultPlan,
        showsTrialTimeline: Bool
    ) {
        self.isHardPaywallEnabled = isHardPaywallEnabled
        self.layout = layout
        self.defaultPlan = defaultPlan
        self.showsTrialTimeline = showsTrialTimeline
    }

    static func isHardPaywallEnabled(in metadata: [String: Any]) -> Bool {
        PaywallConfiguration(metadata: metadata).isHardPaywallEnabled
    }

    private static func token<Value: RawRepresentable>(
        _ value: Any?,
        as type: Value.Type
    ) -> Value? where Value.RawValue == String {
        guard let string = value as? String else { return nil }
        return Value(rawValue: string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func bool(_ value: Any?, fallback: Bool) -> Bool {
        if let value = value as? Bool {
            return value
        }

        if let value = value as? NSNumber {
            return value.boolValue
        }

        if let value = value as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes", "on":
                return true
            case "false", "0", "no", "off":
                return false
            default:
                break
            }
        }

        return fallback
    }
}
