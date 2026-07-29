import Foundation

/// Every measurable moment in the acquisition funnel, from first launch to purchase.
///
/// ## Privacy contract
///
/// Onboarding asks the user what they hide and who they hide it from, and the risks
/// screen promises: *"This stays on your phone. Nobody sees your answer."* That promise
/// is load-bearing for a vault app, so **no event here ever carries an answer value** —
/// only how many options were chosen. Counts are enough to spot a question that stalls
/// people; the answers themselves are none of our business.
///
/// Nothing here carries vault contents, filenames, PINs, or any device identifier
/// beyond the app's own random install ID.
enum AnalyticsEvent {

    // MARK: Onboarding

    case onboardingStarted
    case onboardingStepViewed(step: OnboardingStep)
    case onboardingStepAdvanced(step: OnboardingStep, secondsOnStep: Double)
    case onboardingStepBack(from: OnboardingStep, to: OnboardingStep)
    /// - Parameter selectedCount: how many options, never which ones.
    case onboardingAnswered(step: OnboardingStep, selectedCount: Int)
    /// Fired when the app is backgrounded mid-funnel — the drop-off we can't see any
    /// other way, because these users never come back to a screen we control.
    case onboardingBackgrounded(step: OnboardingStep, secondsOnStep: Double)
    case onboardingCompleted(secondsTotal: Double)

    // MARK: Setup

    case pinSetupStarted
    case pinCreated
    case securitySetupViewed
    case securitySetupCompleted(cameraGranted: Bool, notificationsGranted: Bool)

    // MARK: Paywall

    case paywallViewed(isHard: Bool, offeringID: String?, trialDays: Int?)
    case paywallPlanSelected(planKind: String)
    case paywallPurchaseStarted(productID: String, isTrial: Bool)
    case paywallPurchaseSucceeded(productID: String, isTrial: Bool)
    case paywallPurchaseCancelled(productID: String)
    case paywallPurchaseFailed(productID: String, message: String)
    case paywallRestoreTapped
    case paywallRestoreSucceeded
    case paywallRestoreFailed(message: String)
    case paywallDismissed(isHard: Bool, secondsOnScreen: Double)
    /// The App Store never returned products. Distinguishes "wouldn't pay" from
    /// "couldn't pay", which are opposite problems with opposite fixes.
    case paywallUnavailable(message: String?)

    // MARK: - Wire format

    var name: String {
        switch self {
        case .onboardingStarted: "onboarding_started"
        case .onboardingStepViewed: "onboarding_step_viewed"
        case .onboardingStepAdvanced: "onboarding_step_advanced"
        case .onboardingStepBack: "onboarding_step_back"
        case .onboardingAnswered: "onboarding_answered"
        case .onboardingBackgrounded: "onboarding_backgrounded"
        case .onboardingCompleted: "onboarding_completed"
        case .pinSetupStarted: "pin_setup_started"
        case .pinCreated: "pin_created"
        case .securitySetupViewed: "security_setup_viewed"
        case .securitySetupCompleted: "security_setup_completed"
        case .paywallViewed: "paywall_viewed"
        case .paywallPlanSelected: "paywall_plan_selected"
        case .paywallPurchaseStarted: "paywall_purchase_started"
        case .paywallPurchaseSucceeded: "paywall_purchase_succeeded"
        case .paywallPurchaseCancelled: "paywall_purchase_cancelled"
        case .paywallPurchaseFailed: "paywall_purchase_failed"
        case .paywallRestoreTapped: "paywall_restore_tapped"
        case .paywallRestoreSucceeded: "paywall_restore_succeeded"
        case .paywallRestoreFailed: "paywall_restore_failed"
        case .paywallDismissed: "paywall_dismissed"
        case .paywallUnavailable: "paywall_unavailable"
        }
    }

    var parameters: [String: String] {
        switch self {
        case .onboardingStarted, .pinSetupStarted, .pinCreated,
             .securitySetupViewed, .paywallRestoreTapped, .paywallRestoreSucceeded:
            return [:]

        case .onboardingStepViewed(let step):
            return ["step": step.analyticsName, "step_index": String(step.rawValue)]

        case .onboardingStepAdvanced(let step, let seconds):
            return [
                "step": step.analyticsName,
                "step_index": String(step.rawValue),
                "seconds_on_step": Self.format(seconds)
            ]

        case .onboardingStepBack(let from, let to):
            return ["from_step": from.analyticsName, "to_step": to.analyticsName]

        case .onboardingAnswered(let step, let selectedCount):
            return ["step": step.analyticsName, "selected_count": String(selectedCount)]

        case .onboardingBackgrounded(let step, let seconds):
            return [
                "step": step.analyticsName,
                "step_index": String(step.rawValue),
                "seconds_on_step": Self.format(seconds)
            ]

        case .onboardingCompleted(let seconds):
            return ["seconds_total": Self.format(seconds)]

        case .securitySetupCompleted(let camera, let notifications):
            return [
                "camera_granted": String(camera),
                "notifications_granted": String(notifications)
            ]

        case .paywallViewed(let isHard, let offeringID, let trialDays):
            var params = ["is_hard": String(isHard)]
            params["offering_id"] = offeringID
            params["trial_days"] = trialDays.map(String.init)
            return params

        case .paywallPlanSelected(let planKind):
            return ["plan": planKind]

        case .paywallPurchaseStarted(let productID, let isTrial),
             .paywallPurchaseSucceeded(let productID, let isTrial):
            return ["product_id": productID, "is_trial": String(isTrial)]

        case .paywallPurchaseCancelled(let productID):
            return ["product_id": productID]

        case .paywallPurchaseFailed(let productID, let message):
            return ["product_id": productID, "message": message]

        case .paywallRestoreFailed(let message):
            return ["message": message]

        case .paywallDismissed(let isHard, let seconds):
            return ["is_hard": String(isHard), "seconds_on_screen": Self.format(seconds)]

        case .paywallUnavailable(let message):
            return message.map { ["message": $0] } ?? [:]
        }
    }

    private static func format(_ seconds: Double) -> String {
        String(format: "%.1f", seconds)
    }
}

// MARK: - Step Names

extension OnboardingStep {
    /// Stable wire name. Deliberately not derived from the enum case order — renaming or
    /// reordering steps must not silently rewrite history in the dashboard.
    var analyticsName: String {
        switch self {
        case .hook: "hook"
        case .proof: "proof"
        case .targets: "question_targets"
        case .risks: "question_risks"
        case .history: "question_history"
        case .trust: "trust"
        case .building: "building"
        case .plan: "plan"
        }
    }
}
