import Foundation
@preconcurrency import DeviceActivity
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

// Compiled into both the app and the HideAppsMonitor extension. The extension wakes when
// a "show for 15 minutes" timer ends and re-hides the apps, even if VaultBox is closed, so
// both sides read and write the same state in the app group.

// MARK: - Constants

enum HideAppsShared {
    static let appGroupIdentifier = "group.com.vaultbox.app"
    static let stateKey = "hideApps.state"
    static let storeName = ManagedSettingsStore.Name("hideApps")
    /// The Screen Time schedule that ends a temporary reveal.
    static let revealActivity = DeviceActivityName("hideApps.reveal")

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}

// MARK: - State

/// Apps shown for a while before they hide again on their own.
struct HideAppsReveal: Codable, Equatable, Sendable {
    /// The apps shown, or nil for every hidden app.
    var tokens: Set<ApplicationToken>?
    var until: Date

    func isActive(at now: Date) -> Bool { until > now }

    func includes(_ token: ApplicationToken) -> Bool {
        tokens?.contains(token) ?? true
    }
}

/// Everything needed to work out which apps should be hidden right now.
struct HideAppsState: Codable, Equatable, Sendable {
    var selection = FamilyActivitySelection()
    /// The user's standing choice: hide the picked apps. A temporary reveal sits on top of
    /// it and expires; turning this off shows everything until they turn it back on.
    var isEnabled = false
    var reveal: HideAppsReveal?
}

// MARK: - Rules

enum HideAppsRules {
    /// Which of the picked apps should be hidden at `now`.
    ///
    /// Generic so the rule can be tested without Screen Time tokens, which only Apple's
    /// picker can create.
    static func appsToHide<Token: Hashable>(
        selected: Set<Token>,
        isEnabled: Bool,
        revealed: Set<Token>?,
        revealUntil: Date?,
        now: Date
    ) -> Set<Token> {
        guard isEnabled else { return [] }
        guard let revealUntil, revealUntil > now else { return selected }
        guard let revealed else { return [] }
        return selected.subtracting(revealed)
    }

    /// When a new reveal lands on top of one still running, the two merge: every app
    /// shown by either stays shown, until the later of the two end times. Re-hiding an app
    /// the user just asked to see would be the surprise this feature must never cause.
    static func merge<Token: Hashable>(
        existing: (tokens: Set<Token>?, until: Date)?,
        adding tokens: Set<Token>?,
        until: Date,
        now: Date
    ) -> (tokens: Set<Token>?, until: Date) {
        guard let existing, existing.until > now else { return (tokens, until) }
        let mergedTokens: Set<Token>?
        if let current = existing.tokens, let new = tokens {
            mergedTokens = current.union(new)
        } else {
            mergedTokens = nil
        }
        return (mergedTokens, max(existing.until, until))
    }
}

// MARK: - Persistence

enum HideAppsStore {
    static func load(from defaults: UserDefaults) -> HideAppsState? {
        guard let data = defaults.data(forKey: HideAppsShared.stateKey) else { return nil }
        return try? JSONDecoder().decode(HideAppsState.self, from: data)
    }

    static func save(_ state: HideAppsState, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: HideAppsShared.stateKey)
    }

    /// Writes `state` to Screen Time and returns it with any expired reveal dropped.
    @discardableResult
    static func apply(_ state: HideAppsState, now: Date = .now) -> HideAppsState {
        var state = state
        if let reveal = state.reveal, !reveal.isActive(at: now) {
            state.reveal = nil
        }
        let hidden = HideAppsRules.appsToHide(
            selected: state.selection.applicationTokens,
            isEnabled: state.isEnabled,
            revealed: state.reveal?.tokens,
            revealUntil: state.reveal?.until,
            now: now
        )
        let store = ManagedSettingsStore(named: HideAppsShared.storeName)
        store.application.blockedApplications = hidden.isEmpty
            ? nil
            : Set(hidden.map { Application(token: $0) })
        return state
    }
}
