import Observation

enum AppRootRoute: Equatable {
    case onboarding
    case setupPIN
    case lock
    case main
}

@MainActor
@Observable
final class AppPrivacyShield {
    var isVisible = true
}

func determineAppRootRoute(
    hasCompletedOnboarding: Bool,
    isSetupComplete: Bool,
    isUnlocked: Bool
) -> AppRootRoute {
    if isUnlocked {
        return .main
    }
    if !hasCompletedOnboarding && !isSetupComplete {
        return .onboarding
    }
    if !isSetupComplete {
        return .setupPIN
    }
    return .lock
}

struct PostSetupOverlayDecision: Equatable {
    let showSecuritySetup: Bool
    let deferPaywallUntilSecuritySetupCompletes: Bool

    static let none = PostSetupOverlayDecision(
        showSecuritySetup: false,
        deferPaywallUntilSecuritySetupCompletes: false
    )
}

func determinePostSetupOverlayDecision(
    oldRoute: AppRootRoute?,
    newRoute: AppRootRoute?
) -> PostSetupOverlayDecision {
    guard newRoute == .main else { return .none }
    guard oldRoute == .onboarding || oldRoute == .setupPIN else { return .none }

    return PostSetupOverlayDecision(
        showSecuritySetup: true,
        deferPaywallUntilSecuritySetupCompletes: true
    )
}

func resolveDeferredPostSetupPaywall(
    shouldDefer: Bool
) -> (showPaywall: Bool, shouldDefer: Bool) {
    guard shouldDefer else { return (false, false) }
    return (true, false)
}

func shouldDismissMainShellPresentations(
    oldRoute: AppRootRoute?,
    newRoute: AppRootRoute?
) -> Bool {
    oldRoute == .main && newRoute == .lock
}

func shouldRenderMainShell(for route: AppRootRoute) -> Bool {
    route == .main || route == .lock
}

func shouldLockImmediatelyForDisguise(iconName: String?) -> Bool {
    AppDisguise(iconName: iconName) != nil
}
