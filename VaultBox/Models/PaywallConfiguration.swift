import Foundation

/// Remote behavior attached to the active RevenueCat offering.
///
/// Set `isHard` in RevenueCat's offering metadata to change the onboarding paywall
/// without shipping an app update. Missing or malformed values preserve the intended
/// hard-paywall rollout.
enum PaywallConfiguration {
    static let hardPaywallMetadataKey = "isHard"
    static let defaultIsHardPaywallEnabled = true

    static func isHardPaywallEnabled(in metadata: [String: Any]) -> Bool {
        guard let value = metadata[hardPaywallMetadataKey] else {
            return defaultIsHardPaywallEnabled
        }

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

        return defaultIsHardPaywallEnabled
    }
}
