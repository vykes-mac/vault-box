import Foundation

struct PaywallAnalyticsContext: Sendable {
    let placement: PaywallPlacement
    let offeringID: String?
    let layout: PaywallConfiguration.Layout
    let isHard: Bool

    var parameters: [String: String] {
        var values = [
            "placement": placement.rawValue,
            "layout": layout.rawValue,
            "is_hard": String(isHard)
        ]
        values["offering_id"] = offeringID
        return values
    }
}

enum PaywallDismissalReason: String, Sendable {
    case closed
    case storeUnavailable = "store_unavailable"
}

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

    case paywallViewed(context: PaywallAnalyticsContext, selectedProductID: String?, trialDays: Int?)
    case paywallPlanSelected(context: PaywallAnalyticsContext, planKind: String, productID: String)
    case paywallPurchaseStarted(context: PaywallAnalyticsContext, productID: String, isTrial: Bool)
    case paywallPurchaseSucceeded(context: PaywallAnalyticsContext, productID: String, isTrial: Bool)
    case paywallPurchaseCancelled(context: PaywallAnalyticsContext, productID: String)
    case paywallPurchaseFailed(context: PaywallAnalyticsContext, productID: String, message: String)
    case paywallRestoreTapped(context: PaywallAnalyticsContext)
    case paywallRestoreSucceeded(context: PaywallAnalyticsContext)
    case paywallRestoreFailed(context: PaywallAnalyticsContext, message: String)
    case paywallDismissed(
        context: PaywallAnalyticsContext,
        secondsOnScreen: Double,
        reason: PaywallDismissalReason
    )
    /// The App Store never returned products. Distinguishes "wouldn't pay" from
    /// "couldn't pay", which are opposite problems with opposite fixes.
    case paywallUnavailable(context: PaywallAnalyticsContext, message: String?)

    // MARK: Activation
    //
    // Everything above measures whether people *buy*. This block measures whether they
    // ever reach the point of getting value, which is what decides refunds and renewals.

    case activationChecklistViewed(completedCount: Int)
    case activationStepTapped(step: ActivationStep)
    /// Which disguise, deliberately. This is a configuration choice about the app, not an
    /// answer to the onboarding questionnaire, so the privacy contract above doesn't
    /// cover it — and knowing that most people pick one or two icons says which artwork
    /// is worth the effort.
    case disguiseApplied(disguise: String)
    /// The user practised the gesture that reopens the vault from behind a cover. A gap
    /// between ``disguiseApplied`` and this event is a population who can't get back in.
    case disguiseUnlockGuideCompleted

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
        case .activationChecklistViewed: "activation_checklist_viewed"
        case .activationStepTapped: "activation_step_tapped"
        case .disguiseApplied: "disguise_applied"
        case .disguiseUnlockGuideCompleted: "disguise_unlock_guide_completed"
        }
    }

    var parameters: [String: String] {
        switch self {
        case .onboardingStarted, .pinSetupStarted, .pinCreated,
             .securitySetupViewed,
             .disguiseUnlockGuideCompleted:
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

        case .paywallViewed(let context, let selectedProductID, let trialDays):
            var params = context.parameters
            params["selected_product_id"] = selectedProductID
            params["trial_days"] = trialDays.map(String.init)
            return params

        case .paywallPlanSelected(let context, let planKind, let productID):
            return context.parameters.merging([
                "plan": planKind,
                "product_id": productID
            ]) { _, new in new }

        case .paywallPurchaseStarted(let context, let productID, let isTrial),
             .paywallPurchaseSucceeded(let context, let productID, let isTrial):
            return context.parameters.merging([
                "product_id": productID,
                "is_trial": String(isTrial)
            ]) { _, new in new }

        case .paywallPurchaseCancelled(let context, let productID):
            return context.parameters.merging(["product_id": productID]) { _, new in new }

        case .paywallPurchaseFailed(let context, let productID, let message):
            return context.parameters.merging([
                "product_id": productID,
                "message": message
            ]) { _, new in new }

        case .paywallRestoreTapped(let context),
             .paywallRestoreSucceeded(let context):
            return context.parameters

        case .paywallRestoreFailed(let context, let message):
            return context.parameters.merging(["message": message]) { _, new in new }

        case .paywallDismissed(let context, let seconds, let reason):
            return context.parameters.merging([
                "seconds_on_screen": Self.format(seconds),
                "reason": reason.rawValue
            ]) { _, new in new }

        case .paywallUnavailable(let context, let message):
            return context.parameters.merging(
                message.map { ["message": $0] } ?? [:]
            ) { _, new in new }

        case .activationChecklistViewed(let completedCount):
            return ["completed_count": String(completedCount)]

        case .activationStepTapped(let step):
            return ["step": step.analyticsName]

        case .disguiseApplied(let disguise):
            return ["disguise": disguise]
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
