import Foundation
import RevenueCat

// MARK: - Paywall Plan

/// A single purchasable option rendered on the paywall, pre-formatted for display.
struct PaywallPlan: Identifiable {
    enum Kind: String, Sendable {
        case annual
        case weekly
    }

    let kind: Kind
    let package: Package
    /// Number of free trial days, if the product carries an introductory free trial
    /// **and** this customer is still eligible for it.
    let trialDays: Int?
    /// Whole-percent saving versus paying the weekly price for a year. Anchor value.
    let savingsPercent: Int?

    var id: String { package.identifier }

    var title: String {
        switch kind {
        case .annual: String(localized: "Yearly")
        case .weekly: String(localized: "Weekly")
        }
    }

    var priceString: String {
        package.storeProduct.localizedPriceString
    }

    var pricePeriod: String {
        switch kind {
        case .annual: String(localized: "per year")
        case .weekly: String(localized: "per week")
        }
    }

    /// "$1.15/wk" — lets the yearly plan be compared on the weekly plan's own terms.
    var perWeekString: String? {
        package.storeProduct.localizedPricePerWeek
    }

    var hasTrial: Bool { trialDays != nil }
}

// MARK: - Paywall View Model

@MainActor
@Observable
final class PaywallViewModel {
    private(set) var plans: [PaywallPlan] = []
    private(set) var isLoadingPlans = false
    private(set) var loadError: String?

    var selectedPlanID: String?
    var isPurchasing = false
    var purchaseError: String?

    /// True once we know there is at least one thing the user can buy. Until then a hard
    /// paywall must not trap anyone — see ``PaywallGate``.
    var hasPurchasablePlans: Bool { !plans.isEmpty }

    var selectedPlan: PaywallPlan? {
        plans.first { $0.id == selectedPlanID } ?? plans.first
    }

    var annualPlan: PaywallPlan? { plans.first { $0.kind == .annual } }

    /// Trial days on the plan we would actually charge for — drives the CTA copy and
    /// the trial timeline.
    var trialDays: Int? { selectedPlan?.trialDays }

    // MARK: - Loading

    func load(purchaseService: PurchaseService, force: Bool = false) async {
        guard !isLoadingPlans else { return }
        guard force || plans.isEmpty else { return }

        isLoadingPlans = true
        loadError = nil
        defer { isLoadingPlans = false }

        if purchaseService.currentOffering == nil || force {
            do {
                try await purchaseService.fetchOfferings()
            } catch {
                loadError = error.localizedDescription
            }
        }

        let offering = purchaseService.currentOffering
        // Product IDs first, then package type, then the product's own billing period.
        // An offering renamed in the dashboard must never render an empty paywall.
        let annualPackage = purchaseService.annualPackage
            ?? offering?.availablePackages.first { $0.packageType == .annual }
            ?? offering?.availablePackages.first { $0.storeProduct.subscriptionPeriod?.unit == .year }
        let weeklyPackage = purchaseService.weeklyPackage
            ?? offering?.availablePackages.first { $0.packageType == .weekly }
            ?? offering?.availablePackages.first { $0.storeProduct.subscriptionPeriod?.unit == .week }
        let weeklyPrice = weeklyPackage?.storeProduct.price

        #if DEBUG
        let available = offering?.availablePackages.map(\.storeProduct.productIdentifier) ?? []
        print("[Paywall] offering=\(offering?.identifier ?? "nil") packages=\(available)")
        #endif

        var resolved: [PaywallPlan] = []

        if let annualPackage {
            resolved.append(
                PaywallPlan(
                    kind: .annual,
                    package: annualPackage,
                    trialDays: await trialDays(for: annualPackage),
                    savingsPercent: Self.savingsPercent(
                        annualPrice: annualPackage.storeProduct.price,
                        weeklyPrice: weeklyPrice
                    )
                )
            )
        }

        // A single-package offering can satisfy both lookups; never list it twice.
        if let weeklyPackage, weeklyPackage.identifier != annualPackage?.identifier {
            resolved.append(
                PaywallPlan(
                    kind: .weekly,
                    package: weeklyPackage,
                    trialDays: await trialDays(for: weeklyPackage),
                    savingsPercent: nil
                )
            )
        }

        plans = resolved

        if loadError == nil, resolved.isEmpty {
            loadError = purchaseService.offeringsLoadError
                ?? String(localized: "Subscription options are unavailable right now.")
        }

        // Default to the yearly plan: it carries the trial and it is the anchor we want
        // the weekly price compared against.
        if selectedPlanID == nil || !resolved.contains(where: { $0.id == selectedPlanID }) {
            selectedPlanID = resolved.first { $0.kind == .annual }?.id ?? resolved.first?.id
        }
    }

    // MARK: - Purchase

    /// - Returns: `true` when the customer now holds the premium entitlement.
    /// Outcome of a purchase attempt. Cancelling and failing look identical to the user
    /// (nothing happens) but mean opposite things to the funnel: one is a pricing
    /// objection, the other is a bug.
    enum PurchaseOutcome: Equatable {
        case purchased
        case cancelled
        case failed(String)
        case unavailable
    }

    func purchaseSelected(purchaseService: PurchaseService) async -> PurchaseOutcome {
        guard let plan = selectedPlan, !isPurchasing else { return .unavailable }

        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            switch try await purchaseService.purchase(plan.package) {
            case .premiumGranted:
                return .purchased
            case .cancelled:
                return .cancelled
            case .premiumNotGranted:
                return .failed(
                    String(localized: "The purchase completed but premium wasn't granted.")
                )
            }
        } catch {
            if Self.isUserCancelled(error) {
                return .cancelled
            }
            purchaseError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    enum RestoreOutcome: Equatable {
        case restored
        case nothingToRestore
        case failed(String)
    }

    func restore(purchaseService: PurchaseService) async -> RestoreOutcome {
        guard !isPurchasing else { return .nothingToRestore }

        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let restored = try await purchaseService.restorePurchases()
            guard restored else {
                purchaseError = String(localized: "No active subscription found for this Apple Account.")
                return .nothingToRestore
            }
            return .restored
        } catch {
            purchaseError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func trialDays(for package: Package) async -> Int? {
        let product = package.storeProduct
        guard let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }

        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: product)
        // `.unknown` happens offline or pre-receipt; showing the trial is the right call
        // there because StoreKit still gates the actual grant.
        guard eligibility != .ineligible else { return nil }

        return Self.days(in: intro.subscriptionPeriod) * max(1, intro.numberOfPeriods)
    }

    nonisolated static func days(in period: SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return period.value
        }
    }

    nonisolated static func savingsPercent(annualPrice: Decimal, weeklyPrice: Decimal?) -> Int? {
        guard let weeklyPrice, weeklyPrice > 0 else { return nil }
        let yearAtWeeklyRate = weeklyPrice * 52
        guard yearAtWeeklyRate > annualPrice else { return nil }
        let saved = (yearAtWeeklyRate - annualPrice) / yearAtWeeklyRate * 100
        return Int(NSDecimalNumber(decimal: saved).doubleValue.rounded())
    }

    private static func isUserCancelled(_ error: Error) -> Bool {
        (error as? ErrorCode) == .purchaseCancelledError
            || (error as NSError).code == ErrorCode.purchaseCancelledError.rawValue
    }
}
