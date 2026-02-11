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
}

// MARK: - PurchaseService

@MainActor
@Observable
class PurchaseService: NSObject {
    var isPremium = false
    var hasResolvedCustomerInfo = false
    var currentOffering: Offering?
    var isLoading = false
    var offeringsLoadError: String?
    var isOfferingsReady = false
    var isUsingExplicitOffering = false

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

            if let resolvedOffering {
                debugLog(
                    "Resolved offering '\(resolvedOffering.identifier)' (explicit=\(isUsingExplicitOffering))"
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
            debugLog("Offerings fetch failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Purchase

    func purchase(_ package: Package) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        let result = try await Purchases.shared.purchase(package: package)
        let hasPremium = result.customerInfo.entitlements[Constants.premiumEntitlementID]?.isActive == true
        isPremium = hasPremium
        hasResolvedCustomerInfo = true
        return hasPremium
    }

    // MARK: - Restore

    func restorePurchases() async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        let customerInfo = try await Purchases.shared.restorePurchases()
        let hasPremium = customerInfo.entitlements[Constants.premiumEntitlementID]?.isActive == true
        isPremium = hasPremium
        hasResolvedCustomerInfo = true
        return hasPremium
    }

    // MARK: - Check Status

    @discardableResult
    func checkPremiumStatus() async -> Bool {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let hasPremium = customerInfo.entitlements[Constants.premiumEntitlementID]?.isActive == true
            isPremium = hasPremium
            hasResolvedCustomerInfo = true
            return hasPremium
        } catch {
            return isPremium
        }
    }

    // MARK: - Helpers

    func isPremiumRequired(for feature: PremiumFeature, itemCount: Int = 0) -> Bool {
        if isPremium { return false }
        switch feature {
        case .unlimitedItems:
            return itemCount >= Constants.freeItemLimit
        case .iCloudBackup, .decoyVault, .fakeAppIcon, .panicGesture,
             .wifiTransfer, .albumLock, .videoSpeedControl, .breakInGPS:
            return true
        }
    }

    var weeklyPackage: Package? {
        currentOffering?.availablePackages.first { $0.storeProduct.productIdentifier == Constants.weeklyProductID }
    }

    var annualPackage: Package? {
        currentOffering?.availablePackages.first { $0.storeProduct.productIdentifier == Constants.annualProductID }
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
        let hasPremium = customerInfo.entitlements[Constants.premiumEntitlementID]?.isActive == true
        Task { @MainActor in
            self.isPremium = hasPremium
            self.hasResolvedCustomerInfo = true
        }
    }
}
