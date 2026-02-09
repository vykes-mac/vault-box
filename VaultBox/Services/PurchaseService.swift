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
    var currentOffering: Offering?
    var isLoading = false

    // MARK: - Configure

    func configure() {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Constants.revenueCatAPIKey)
        Purchases.shared.delegate = self

        Task {
            await checkPremiumStatus()
            try? await fetchOfferings()
        }
    }

    // MARK: - Fetch Offerings

    func fetchOfferings() async throws {
        isLoading = true
        defer { isLoading = false }

        let offerings = try await Purchases.shared.offerings()
        currentOffering = offerings.current
    }

    // MARK: - Purchase

    func purchase(_ package: Package) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        let result = try await Purchases.shared.purchase(package: package)
        let hasPremium = result.customerInfo.entitlements[Constants.premiumEntitlementID]?.isActive == true
        isPremium = hasPremium
        return hasPremium
    }

    // MARK: - Restore

    func restorePurchases() async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        let customerInfo = try await Purchases.shared.restorePurchases()
        let hasPremium = customerInfo.entitlements[Constants.premiumEntitlementID]?.isActive == true
        isPremium = hasPremium
        return hasPremium
    }

    // MARK: - Check Status

    @discardableResult
    func checkPremiumStatus() async -> Bool {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let hasPremium = customerInfo.entitlements[Constants.premiumEntitlementID]?.isActive == true
            isPremium = hasPremium
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
}

// MARK: - PurchasesDelegate

extension PurchaseService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        let hasPremium = customerInfo.entitlements[Constants.premiumEntitlementID]?.isActive == true
        Task { @MainActor in
            self.isPremium = hasPremium
        }
    }
}
