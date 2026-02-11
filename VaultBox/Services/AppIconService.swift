import UIKit

@MainActor
final class AppIconService {
    struct IconOption {
        let id: String?
        let displayName: String
        let systemImage: String
    }

    enum AppIconError: LocalizedError {
        case alternateIconsUnavailable
        case iconNotConfigured(String)

        var errorDescription: String? {
            switch self {
            case .alternateIconsUnavailable:
                return "Alternate app icons are not available in this build."
            case let .iconNotConfigured(iconName):
                return "The icon '\(iconName)' is not configured in this build."
            }
        }
    }

    static let iconCatalog: [IconOption] = [
        IconOption(id: nil, displayName: "VaultBox (Default)", systemImage: "lock.shield.fill"),
        IconOption(id: "CalculatorIcon", displayName: "Calculator", systemImage: "plus.forwardslash.minus"),
        IconOption(id: "NotesIcon", displayName: "Notes", systemImage: "note.text"),
        IconOption(id: "WeatherIcon", displayName: "Weather", systemImage: "cloud.sun.fill"),
        IconOption(id: "CompassIcon", displayName: "Compass", systemImage: "safari"),
        IconOption(id: "ClockIcon", displayName: "Clock", systemImage: "clock.fill"),
        IconOption(id: "StocksIcon", displayName: "Stocks", systemImage: "chart.line.uptrend.xyaxis"),
        IconOption(id: "TranslateIcon", displayName: "Translate", systemImage: "bubble.left.and.text.bubble.right"),
        IconOption(id: "MeasureIcon", displayName: "Measure", systemImage: "ruler"),
    ]

    func availableIcons() -> [IconOption] {
        let configured = configuredAlternateIconIDs()
        guard UIApplication.shared.supportsAlternateIcons, !configured.isEmpty else {
            return Self.iconCatalog.filter { $0.id == nil }
        }
        return Self.iconCatalog.filter { icon in
            guard let id = icon.id else { return true }
            return configured.contains(id)
        }
    }

    func setIcon(_ iconName: String?) async throws {
        if let iconName {
            guard UIApplication.shared.supportsAlternateIcons else {
                throw AppIconError.alternateIconsUnavailable
            }
            guard configuredAlternateIconIDs().contains(iconName) else {
                throw AppIconError.iconNotConfigured(iconName)
            }
        }
        if UIApplication.shared.alternateIconName == iconName {
            return
        }
        try await UIApplication.shared.setAlternateIconName(iconName)
    }

    func getCurrentIcon() -> String? {
        UIApplication.shared.alternateIconName
    }

    private func configuredAlternateIconIDs() -> Set<String> {
        let iconContainerKeys = ["CFBundleIcons", "CFBundleIcons~ipad"]
        var configuredIDs = Set<String>()

        for key in iconContainerKeys {
            guard
                let icons = Bundle.main.object(forInfoDictionaryKey: key) as? [String: Any],
                let alternates = icons["CFBundleAlternateIcons"] as? [String: Any]
            else {
                continue
            }
            configuredIDs.formUnion(alternates.keys)
        }

        return configuredIDs
    }
}
