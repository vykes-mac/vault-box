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
                return String(localized: "Alternate app icons are not available in this build.")
            case let .iconNotConfigured(iconName):
                return String(localized: "The icon '\(iconName)' is not configured in this build.")
            }
        }
    }

    static let iconCatalog: [IconOption] = [
        IconOption(
            id: nil,
            displayName: String(localized: "VaultBox (Default)"),
            systemImage: "lock.shield.fill"
        ),
    ] + AppDisguise.allCases.map { disguise in
        IconOption(
            id: disguise.rawValue,
            displayName: disguise.displayName,
            systemImage: disguise.systemImage
        )
    }

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
        do {
            try await UIApplication.shared.setAlternateIconName(iconName)
        } catch {
            // iOS can apply the icon while still returning a transient system error.
            // Trust the resulting icon state so successful changes can continue normally.
            guard Self.didApplyIcon(
                requestedIconName: iconName,
                actualIconName: UIApplication.shared.alternateIconName
            ) else {
                throw error
            }
        }
    }

    func getCurrentIcon() -> String? {
        UIApplication.shared.alternateIconName
    }

    static func didApplyIcon(
        requestedIconName: String?,
        actualIconName: String?
    ) -> Bool {
        requestedIconName == actualIconName
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
