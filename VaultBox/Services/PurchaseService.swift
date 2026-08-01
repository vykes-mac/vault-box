import Foundation
import RevenueCat

// MARK: - PremiumFeature

enum PremiumFeature {
    case unlimitedItems
    case iCloudBackup
    case decoyVault
    case fakeAppIcon
    case panicGesture
    case wifiTransfer
    case albumLock
    case videoSpeedControl
    case breakInGPS
    case timeLimitedSharing
    case customAlbumCovers
    case documentStorage
    case askMyVault
}

// MARK: - PurchaseService

@MainActor
@Observable
class PurchaseService: NSObject {
    enum PurchaseResult: Equatable, Sendable {
        case premiumGranted
        case cancelled
        case premiumNotGranted
    }

    var isPremium = false
    var hasResolvedCustomerInfo = false
    var currentOffering: Offering?
    var isLoading = false
    var offeringsLoadError: String?
    var isOfferingsReady = false
    var isUsingExplicitOffering = false
    private(set) var isHardPaywallEnabled = PaywallConfiguration.defaultIsHardPaywallEnabled
    private(set) var hasResolvedPaywallConfiguration = false
    private let trialReminderService = TrialReminderService()

    // MARK: - Configure

    func configure() {
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        if Constants.revenueCatAPIKey.hasPrefix("test_") {
            print("[RevenueCat] ERROR: Test Store API key detected in non-Debug build.")
        }
        #endif

        Purchases.configure(withAPIKey: Constants.revenueCatAPIKey)
        Purchases.shared.delegate = self
        debugLog("Configured Purchases. API key prefix: \(String(Constants.revenueCatAPIKey.prefix(5)))")

        Task {
            await checkPremiumStatus()
            try? await fetchOfferings()
        }
    }

    // MARK: - Fetch Offerings

    func fetchOfferings() async throws {
        isLoading = true
        offeringsLoadError = nil
        defer { isLoading = false }

        do {
            let offerings = try await Purchases.shared.offerings()
            let explicitOffering = offerings.all[Constants.primaryOfferingID]
            let resolvedOffering = explicitOffering ?? offerings.current

            currentOffering = resolvedOffering
            isUsingExplicitOffering = explicitOffering != nil
            isOfferingsReady = resolvedOffering != nil
            applyPaywallConfiguration(from: resolvedOffering)

            if let resolvedOffering {
                debugLog(
                    "Resolved offering '\(resolvedOffering.identifier)' " +
                    "(explicit=\(isUsingExplicitOffering), isHard=\(isHardPaywallEnabled))"
                )
            } else {
                offeringsLoadError =
                    "No RevenueCat offering available. Verify offering '\(Constants.primaryOfferingID)' " +
                    "exists or set a current offering in the RevenueCat dashboard."
                debugLog("Failed to resolve offering. currentOffering=nil")
            }
        } catch {
            offeringsLoadError = error.localizedDescription
            isOfferingsReady = currentOffering != nil
            applyPaywallConfiguration(from: currentOffering)
            debugLog("Offerings fetch failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Purchase

    func purchase(_ package: Package) async throws -> PurchaseResult {
        isLoading = true
        defer { isLoading = false }

        let result = try await Purchases.shared.purchase(package: package)
        let hasPremium = await apply(result.customerInfo)
        return Self.classifyPurchase(
            userCancelled: result.userCancelled,
            hasPremium: hasPremium
        )
    }

    // MARK: - Restore

    func restorePurchases() async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        let customerInfo = try await Purchases.shared.restorePurchases()
        return await apply(customerInfo)
    }

    // MARK: - Check Status

    @discardableResult
    func checkPremiumStatus() async -> Bool {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            return await apply(customerInfo)
        } catch {
            return isPremium
        }
    }

    // MARK: - Helpers

    nonisolated static func classifyPurchase(
        userCancelled: Bool,
        hasPremium: Bool
    ) -> PurchaseResult {
        if userCancelled { return .cancelled }
        return hasPremium ? .premiumGranted : .premiumNotGranted
    }

    func isPremiumRequired(for feature: PremiumFeature, itemCount: Int = 0) -> Bool {
        if isPremium { return false }
        switch feature {
        case .unlimitedItems:
            return itemCount >= Constants.freeItemLimit
        case .iCloudBackup, .decoyVault, .fakeAppIcon, .panicGesture,
             .wifiTransfer, .albumLock, .videoSpeedControl, .breakInGPS,
             .timeLimitedSharing, .customAlbumCovers, .documentStorage,
             .askMyVault:
            return true
        }
    }

    var weeklyPackage: Package? {
        currentOffering?.availablePackages.first { $0.storeProduct.productIdentifier == Constants.weeklyProductID }
    }

    var annualPackage: Package? {
        currentOffering?.availablePackages.first { $0.storeProduct.productIdentifier == Constants.annualProductID }
    }

    private func applyPaywallConfiguration(from offering: Offering?) {
        isHardPaywallEnabled = PaywallConfiguration.isHardPaywallEnabled(
            in: offering?.metadata ?? [:]
        )
        hasResolvedPaywallConfiguration = true
    }

    @discardableResult
    private func apply(_ customerInfo: CustomerInfo) async -> Bool {
        let entitlement = customerInfo.entitlements[Constants.premiumEntitlementID]
        let hasPremium = entitlement?.isActive == true

        isPremium = hasPremium
        hasResolvedCustomerInfo = true

        await trialReminderService.reconcile(
            with: TrialReminderState(
                isActive: hasPremium,
                isTrial: entitlement?.periodType == .trial,
                willRenew: entitlement?.willRenew == true
                    && entitlement?.unsubscribeDetectedAt == nil,
                expirationDate: entitlement?.expirationDate
            )
        )

        return hasPremium
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[RevenueCat] \(message)")
        #endif
    }
}

// MARK: - PurchasesDelegate

extension PurchaseService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            await self.apply(customerInfo)
        }
    }
}
