import Foundation
import OSLog
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

// MARK: - RevenueCat Identity

struct RevenueCatAppUserIDStore {
    private let keyStorage: any KeyStorage

    init(keyStorage: any KeyStorage = KeychainKeyStorage()) {
        self.keyStorage = keyStorage
    }

    func getOrCreate() throws -> String {
        if let data = try keyStorage.getData(Constants.keychainRevenueCatAppUserID),
           let existing = String(data: data, encoding: .utf8),
           !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString
        try keyStorage.set(Data(generated.utf8), forKey: Constants.keychainRevenueCatAppUserID)
        return generated
    }
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
    private(set) var isTrial = false
    /// Non-nil while Apple is retrying a failed charge. The entitlement stays active
    /// during this window, so premium access continues but will be revoked at
    /// `entitlementExpirationDate` unless the customer fixes their payment method.
    private(set) var billingIssueDetectedAt: Date?
    private(set) var entitlementExpirationDate: Date?
    var currentOffering: Offering?
    var isLoading = false
    var offeringsLoadError: String?
    var isOfferingsReady = false
    var isUsingExplicitOffering = false
    private(set) var isHardPaywallEnabled = PaywallConfiguration.defaultIsHardPaywallEnabled
    private(set) var hasResolvedPaywallConfiguration = false
    private let trialReminderService = TrialReminderService()
    private let appUserIDStore: RevenueCatAppUserIDStore
    private var trialExpirationTask: Task<Void, Never>?
    private var isConfigured = false

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.pack6.vaultbox",
        category: "RevenueCat"
    )

    init(appUserIDStore: RevenueCatAppUserIDStore = RevenueCatAppUserIDStore()) {
        self.appUserIDStore = appUserIDStore
        super.init()
    }

    // MARK: - Configure

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        if Constants.revenueCatAPIKey.hasPrefix("test_") {
            print("[RevenueCat] ERROR: Test Store API key detected in non-Debug build.")
        }
        #endif

        let appUserID: String?
        do {
            appUserID = try appUserIDStore.getOrCreate()
            Self.logger.notice("Configured stable RevenueCat identity")
        } catch {
            appUserID = nil
            Self.logger.error(
                "Could not persist RevenueCat identity; using an anonymous ID: \(error.localizedDescription, privacy: .public)"
            )
        }

        Purchases.configure(withAPIKey: Constants.revenueCatAPIKey, appUserID: appUserID)
        Purchases.shared.delegate = self

        // Forwards Apple's AdServices attribution token to RevenueCat so Apple Search Ads
        // keywords can be tied to subscription revenue. No ATT prompt required: the token
        // is campaign-level and carries no device identifier.
        Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()

        debugLog("Configured Purchases. API key prefix: \(String(Constants.revenueCatAPIKey.prefix(5)))")

        Task {
            await refreshPremiumStatus()
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
            // The initial entitlement lookup has completed even when RevenueCat could
            // not answer. A marked install must continue to the paywall's unavailable
            // state, never fall through to the vault because this flag stayed false.
            hasResolvedCustomerInfo = true
            debugLog("Customer info lookup failed: \(error.localizedDescription)")
            Self.logger.error(
                "CustomerInfo refresh failed: \(error.localizedDescription, privacy: .public)"
            )
            await expireKnownTrialIfNeeded()
            return isPremium
        }
    }

    @discardableResult
    func refreshPremiumStatus() async -> Bool {
        guard isConfigured else { return isPremium }
        Purchases.shared.invalidateCustomerInfoCache()
        return await checkPremiumStatus()
    }

    // MARK: - Helpers

    nonisolated static func classifyPurchase(
        userCancelled: Bool,
        hasPremium: Bool
    ) -> PurchaseResult {
        if userCancelled { return .cancelled }
        return hasPremium ? .premiumGranted : .premiumNotGranted
    }

    nonisolated static func grantsPremiumAccess(
        entitlementIsActive: Bool,
        isTrial: Bool,
        expirationDate: Date?,
        now: Date
    ) -> Bool {
        guard entitlementIsActive else { return false }
        guard isTrial, let expirationDate else { return true }
        return expirationDate > now
    }

    /// True when premium is still granted but Apple has failed to collect payment.
    /// This is the only window in which the customer can recover the subscription
    /// themselves, so it is what the recovery banner keys off.
    var hasBillingIssue: Bool {
        isPremium && billingIssueDetectedAt != nil
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
        let entitlementIsTrial = entitlement?.periodType == .trial
        let hasPremium = Self.grantsPremiumAccess(
            entitlementIsActive: entitlement?.isActive == true,
            isTrial: entitlementIsTrial,
            expirationDate: entitlement?.expirationDate,
            now: Date()
        )

        isPremium = hasPremium
        isTrial = hasPremium && entitlementIsTrial
        hasResolvedCustomerInfo = true
        billingIssueDetectedAt = entitlement?.billingIssueDetectedAt
        entitlementExpirationDate = entitlement?.expirationDate
        logPremiumEntitlementStatus(entitlement, customerInfo: customerInfo, accessGranted: hasPremium)
        scheduleTrialExpirationIfNeeded()

        await trialReminderService.reconcile(
            with: TrialReminderState(
                isActive: hasPremium,
                isTrial: entitlement?.periodType == .trial,
                willRenew: entitlement?.willRenew == true
                    && entitlement?.unsubscribeDetectedAt == nil,
                expirationDate: entitlement?.expirationDate,
                purchaseDate: entitlement?.latestPurchaseDate,
                billingIssueDetectedAt: entitlement?.billingIssueDetectedAt
            )
        )

        return hasPremium
    }

    private func scheduleTrialExpirationIfNeeded() {
        trialExpirationTask?.cancel()
        guard isPremium, isTrial, let expirationDate = entitlementExpirationDate else { return }

        trialExpirationTask = Task { [weak self] in
            let delay = max(0, expirationDate.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            await self.refreshPremiumStatus()
        }
    }

    private func expireKnownTrialIfNeeded() async {
        guard isPremium,
              isTrial,
              let expirationDate = entitlementExpirationDate,
              expirationDate <= Date() else { return }

        trialExpirationTask?.cancel()
        isPremium = false
        isTrial = false
        await trialReminderService.reconcile(
            with: TrialReminderState(
                isActive: false,
                isTrial: true,
                willRenew: false,
                expirationDate: expirationDate,
                purchaseDate: nil,
                billingIssueDetectedAt: nil
            )
        )
        Self.logger.notice("Known free trial expired; premium access revoked")
    }

    private func logPremiumEntitlementStatus(
        _ entitlement: EntitlementInfo?,
        customerInfo: CustomerInfo,
        accessGranted: Bool
    ) {
        let customerSuffix = String(customerInfo.originalAppUserId.suffix(6))
        let requestDate = ISO8601DateFormatter().string(from: customerInfo.requestDate)

        guard let entitlement else {
            Self.logger.notice(
                "premium_entitlement active=false accessGranted=false product=none period=none willRenew=false expires=none customerSuffix=\(customerSuffix, privacy: .public) requestDate=\(requestDate, privacy: .public)"
            )
            return
        }

        let expiration = entitlement.expirationDate.map {
            ISO8601DateFormatter().string(from: $0)
        } ?? "none"

        let period = String(describing: entitlement.periodType)
        Self.logger.notice(
            "premium_entitlement active=\(entitlement.isActive, privacy: .public) accessGranted=\(accessGranted, privacy: .public) product=\(entitlement.productIdentifier, privacy: .public) period=\(period, privacy: .public) willRenew=\(entitlement.willRenew, privacy: .public) expires=\(expiration, privacy: .public) customerSuffix=\(customerSuffix, privacy: .public) requestDate=\(requestDate, privacy: .public)"
        )
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
