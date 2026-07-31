import Foundation

// MARK: - Step

/// A task on the first-run checklist that stands in for the empty vault.
///
/// The order is deliberate and specific to where this app's installs come from. Most
/// paid traffic arrives on disguise intent, so the disguise step leads: it is the
/// promise the ad made, and keeping that promise inside the first session is what makes
/// the app feel like the thing they tapped on. Importing comes second because it is what
/// makes them *stay* — a disguised empty vault protects nothing, and a user whose vault
/// is still empty on day two has no reason to keep paying.
enum ActivationStep: String, CaseIterable, Identifiable, Sendable {
    /// Already done by everyone who can see this list. Present on purpose — see
    /// ``ActivationChecklist/isSecured``.
    case secured
    case disguise
    case firstImport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .secured: String(localized: "Your vault is locked")
        case .disguise: String(localized: "Hide it on your Home Screen")
        case .firstImport: String(localized: "Move your first files in")
        }
    }

    var detail: String {
        switch self {
        case .secured:
            String(localized: "PIN set, AES-256 encryption on.")
        case .disguise:
            String(localized: "Make VaultBox look like a calculator or a clock.")
        case .firstImport:
            String(localized: "They leave Photos and land here, encrypted.")
        }
    }

    /// Label for the row's action button. Verbs, not destinations — the row does the
    /// thing rather than teaching the user where the setting lives.
    var actionLabel: String {
        switch self {
        case .secured: String(localized: "Done")
        case .disguise: String(localized: "Choose a disguise")
        case .firstImport: String(localized: "Add files")
        }
    }

    var systemImage: String {
        switch self {
        case .secured: "lock.fill"
        case .disguise: "app.dashed"
        case .firstImport: "square.and.arrow.down.fill"
        }
    }

    /// Stable wire name for analytics, independent of case order.
    var analyticsName: String {
        switch self {
        case .secured: "secured"
        case .disguise: "disguise"
        case .firstImport: "first_import"
        }
    }
}

// MARK: - Checklist

/// Completion state of the first-run checklist.
///
/// Every step is *derived* from something observably true — the live alternate icon name
/// and the real item count — rather than from a "user tapped this" flag. A checklist that
/// bookkeeps its own progress can drift out of sync with the app (icon reverted on a
/// lapsed subscription, items deleted) and then lies to the user. This one cannot.
struct ActivationChecklist: Equatable, Sendable {
    var isDisguised: Bool
    var hasItems: Bool

    init(isDisguised: Bool, hasItems: Bool) {
        self.isDisguised = isDisguised
        self.hasItems = hasItems
    }

    /// Always true: the vault is unreachable without a PIN, so anyone who can see this
    /// list has already done it. Shown anyway because crediting finished work turns an
    /// intimidating 0-of-3 into a 1-of-3 that is already moving — the goal-gradient
    /// effect makes people likelier to close a list that has started than to start one.
    var isSecured: Bool { true }

    func isComplete(_ step: ActivationStep) -> Bool {
        switch step {
        case .secured: isSecured
        case .disguise: isDisguised
        case .firstImport: hasItems
        }
    }

    var completedCount: Int {
        ActivationStep.allCases.filter { isComplete($0) }.count
    }

    var totalCount: Int { ActivationStep.allCases.count }

    /// The first unfinished step, used to give exactly one row the primary emphasis.
    /// Two competing calls to action on one screen is the same as none.
    var nextStep: ActivationStep? {
        ActivationStep.allCases.first { !isComplete($0) }
    }

    var isFullyComplete: Bool { nextStep == nil }
}

// MARK: - Visibility

/// Whether the checklist should stand in for the empty-vault state.
///
/// - Parameter isDecoyMode: the decoy vault has to look like an ordinary, slightly boring
///   vault to whoever is holding the phone. Offering to disguise the app there would
///   announce that a real vault exists somewhere else, which is the one thing the decoy
///   is for. Never show it in decoy mode.
/// - Parameter isSearching: an active search means the user is looking for something
///   specific; a setup prompt is noise on top of a "no results" answer.
func shouldShowActivationChecklist(
    isVaultEmpty: Bool,
    isSearching: Bool,
    isDecoyMode: Bool,
    hasDismissed: Bool
) -> Bool {
    isVaultEmpty && !isSearching && !isDecoyMode && !hasDismissed
}
