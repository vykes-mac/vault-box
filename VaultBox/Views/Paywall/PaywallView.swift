import RevenueCat
import SwiftUI

/// The app's only paywall.
///
/// Two modes:
/// - **Soft** (default) — reached from a locked feature. Dismissible.
/// - **Hard** — reached once, immediately after onboarding. There is no close button:
///   the only ways out are purchasing, restoring, or a store failure we can't blame the
///   user for. Paid acquisition traffic converts on the first screen or not at all, so
///   this is the screen the ad spend is actually buying.
struct VaultBoxPaywallView: View {
    var isHard = false
    var placement: PaywallPlacement = .featureGate
    var onStoreUnavailableContinue: () -> Void = {}

    @Environment(PurchaseService.self) private var purchaseService
    @Environment(AnalyticsService.self) private var analytics
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = PaywallViewModel()
    @State private var answers = OnboardingAnswers()
    @State private var appearedAt: Date?
    /// `.task` can re-run when the view swaps between its loading/content/unavailable
    /// branches. Counting that twice would halve every conversion rate computed from it.
    @State private var hasRecordedView = false
    @State private var hasRecordedUnavailable = false

    /// Time the user spent weighing the offer. Short exits are a price/copy problem;
    /// long ones without a purchase point at the plan cards or the trial terms.
    private var secondsOnScreen: Double {
        guard let appearedAt else { return 0 }
        return Date().timeIntervalSince(appearedAt)
    }

    var body: some View {
        ZStack {
            Color.vaultBackground.ignoresSafeArea()

            if viewModel.isLoadingPlans && !viewModel.hasPurchasablePlans {
                loadingView
            } else if viewModel.hasPurchasablePlans {
                if viewModel.configuration.layout == .privacyStat {
                    privacyStatContent
                } else {
                    content
                }
            } else {
                unavailableView
            }
        }
        .task {
            answers = OnboardingAnswersStore.load()
            await loadPlans()
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.purchaseError != nil },
                set: { if !$0 { viewModel.purchaseError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.purchaseError = nil }
        } message: {
            Text(viewModel.purchaseError ?? "")
        }
    }

    // MARK: - Content

    private var privacyStatContent: some View {
        PrivacyStatPaywallContent(
            viewModel: viewModel,
            canDismiss: !isHard,
            ctaTitle: ctaTitle,
            reassurance: reassurance,
            disclosure: disclosure,
            onDismiss: { dismissRecordingExit(reason: .closed) },
            onSelectPlan: selectPlan,
            onPurchase: startPurchase,
            onRestore: restore
        )
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    benefits

                    // Picker first: the weekly-vs-yearly anchor is what makes the yearly
                    // price feel small, and it does nothing below the fold. The timeline
                    // then reads as consequences of the plan already chosen.
                    planPicker

                    if viewModel.configuration.showsTrialTimeline,
                       let trialDays = viewModel.trialDays,
                       let plan = viewModel.selectedPlan {
                        PaywallTrialTimeline(trialDays: trialDays, priceString: plan.priceString)
                    }
                }
                .padding(.horizontal, Constants.standardPadding)
                .padding(.top, isHard ? 12 : 8)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            purchaseFooter
        }
        .overlay(alignment: .topTrailing) {
            if !isHard {
                Button {
                    dismissRecordingExit(reason: .closed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.vaultTextSecondary)
                        .padding(10)
                        .background(Color.vaultSurface, in: Circle())
                }
                .padding(.trailing, Constants.standardPadding)
                .padding(.top, 8)
                .accessibilityLabel("Close")
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Color.vaultSuccess)
                Text(
                    isHard
                        ? String(localized: "Vault created")
                        : String(localized: "VaultBox Premium")
                )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.vaultSuccess)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.vaultSuccess.opacity(0.12), in: Capsule())

            Text(headline)
                .font(.title.bold())
                .foregroundStyle(Color.vaultTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(subheadline)
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headline: String {
        guard isHard else {
            return String(localized: "Unlock everything VaultBox can do.")
        }
        return String(localized: "Your vault is built. Turn the key.")
    }

    private var subheadline: String {
        if isHard, !answers.protectionTargets.isEmpty {
            return String(
                format: String(
                    localized: "Premium is what actually keeps %@ hidden — no limits, no leaks."
                ),
                locale: Locale.current,
                answers.targetSummary
            )
        }
        return String(localized: "Every protection, unlimited storage, on every file you own.")
    }

    // MARK: - Benefits

    private var benefits: some View {
        VStack(spacing: 12) {
            PaywallBenefitRow(
                icon: "infinity",
                title: String(localized: "Unlimited encrypted storage"),
                detail: String(
                    format: String(
                        localized: "Free stops at %lld items. Premium never does."
                    ),
                    locale: Locale.current,
                    Int64(Constants.freeItemLimit)
                )
            )
            PaywallBenefitRow(
                icon: "app.dashed",
                title: String(localized: "Disguise the app + decoy vault"),
                detail: String(localized: "Look like a calculator. Keep a second, harmless PIN.")
            )
            PaywallBenefitRow(
                icon: "camera.metering.center.weighted",
                title: String(localized: "Break-in photos with location"),
                detail: String(localized: "See who tried to get in, and where they stood.")
            )
            PaywallBenefitRow(
                icon: "icloud.and.arrow.up.fill",
                title: String(localized: "Encrypted backup & Ask My Vault"),
                detail: String(localized: "Survive a lost phone. Search your vault on-device.")
            )
        }
    }

    // MARK: - Plans

    private var planPicker: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.plans) { plan in
                PaywallPlanCard(
                    plan: plan,
                    isSelected: viewModel.selectedPlan?.id == plan.id
                ) {
                    selectPlan(plan)
                }
            }
        }
    }

    // MARK: - Footer

    private var purchaseFooter: some View {
        VStack(spacing: 12) {
            Button {
                startPurchase()
            } label: {
                ZStack {
                    if viewModel.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(ctaTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.vaultAccent, in: Capsule())
            }
            .disabled(viewModel.isPurchasing)

            Text(reassurance)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.vaultTextSecondary)

            PaywallLegalFooter(disclosure: disclosure) {
                restore()
            }
        }
        .padding(.horizontal, Constants.standardPadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.bar)
    }

    private var ctaTitle: String {
        if let trialDays = viewModel.trialDays {
            return String(
                format: String(localized: "Start My %lld-Day Free Trial"),
                locale: Locale.current,
                Int64(trialDays)
            )
        }
        return String(localized: "Unlock VaultBox")
    }

    private var reassurance: String {
        if viewModel.trialDays != nil {
            return String(localized: "No payment now · Cancel anytime")
        }
        return String(localized: "Cancel anytime in Settings")
    }

    private var disclosure: String {
        guard let plan = viewModel.selectedPlan else { return "" }
        if let trialDays = plan.trialDays {
            let format = String(
                localized: "%lld days free, then %@ %@. Auto-renews unless cancelled 24 hours before the period ends. Manage in Apple Account settings."
            )
            return String(
                format: format,
                locale: Locale.current,
                Int64(trialDays),
                plan.priceString,
                plan.pricePeriod
            )
        }
        let format = String(
            localized: "%@ %@. Auto-renews unless cancelled 24 hours before the period ends. Manage in Apple Account settings."
        )
        return String(
            format: format,
            locale: Locale.current,
            plan.priceString,
            plan.pricePeriod
        )
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Preparing your vault...")
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextSecondary)
        }
    }

    /// Shown when the App Store never returned products. A hard paywall must still let
    /// people in here — the failure is ours, and trapping them earns a 1-star review.
    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Color.vaultTextSecondary)

            Text("Can't reach the App Store")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.vaultTextPrimary)

            Text(viewModel.loadError ?? String(localized: "Check your connection and try again."))
                .font(.footnote)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await loadPlans(force: true) }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.vaultAccent)
            .disabled(viewModel.isLoadingPlans)

            Button(
                isHard
                    ? String(localized: "Continue to Vault")
                    : String(localized: "Close")
            ) {
                if isHard {
                    onStoreUnavailableContinue()
                }
                dismissRecordingExit(reason: .storeUnavailable)
            }
            .buttonStyle(.bordered)
        }
        .padding(28)
    }

    // MARK: - Actions

    private var analyticsContext: PaywallAnalyticsContext {
        PaywallAnalyticsContext(
            placement: placement,
            offeringID: viewModel.offering?.identifier,
            layout: viewModel.configuration.layout,
            isHard: isHard
        )
    }

    private func loadPlans(force: Bool = false) async {
        await viewModel.load(
            purchaseService: purchaseService,
            placement: placement,
            force: force
        )

        if viewModel.hasPurchasablePlans, !hasRecordedView {
            hasRecordedView = true
            appearedAt = Date()

            analytics.record(.paywallViewed(
                context: analyticsContext,
                selectedProductID: viewModel.selectedPlan?.package.storeProduct.productIdentifier,
                trialDays: viewModel.trialDays
            ))

            if let offering = viewModel.offering {
                Purchases.shared.trackCustomPaywallImpression(
                    CustomPaywallImpressionParams(
                        paywallId: "vaultbox_\(viewModel.configuration.layout.rawValue)",
                        offering: offering
                    )
                )
            }
        } else if !viewModel.hasPurchasablePlans, !hasRecordedUnavailable {
            hasRecordedUnavailable = true
            analytics.record(.paywallUnavailable(
                context: analyticsContext,
                message: viewModel.loadError
            ))
        }
    }

    private func selectPlan(_ plan: PaywallPlan) {
        Haptics.itemSelected()
        viewModel.selectedPlanID = plan.id
        analytics.record(.paywallPlanSelected(
            context: analyticsContext,
            planKind: plan.kind.rawValue,
            productID: plan.package.storeProduct.productIdentifier
        ))
    }

    private func startPurchase() {
        guard let plan = viewModel.selectedPlan else { return }
        let productID = plan.package.storeProduct.productIdentifier
        let isTrial = plan.hasTrial

        analytics.record(.paywallPurchaseStarted(
            context: analyticsContext,
            productID: productID,
            isTrial: isTrial
        ))

        Task {
            switch await viewModel.purchaseSelected(purchaseService: purchaseService) {
            case .purchased:
                analytics.record(.paywallPurchaseSucceeded(
                    context: analyticsContext,
                    productID: productID,
                    isTrial: isTrial
                ))
                Haptics.purchaseComplete()
                dismiss()
            case .cancelled:
                analytics.record(.paywallPurchaseCancelled(
                    context: analyticsContext,
                    productID: productID
                ))
            case .failed(let message):
                analytics.record(.paywallPurchaseFailed(
                    context: analyticsContext,
                    productID: productID,
                    message: message
                ))
            case .unavailable:
                break
            }
        }
    }

    private func restore() {
        analytics.record(.paywallRestoreTapped(context: analyticsContext))
        Task {
            switch await viewModel.restore(purchaseService: purchaseService) {
            case .restored:
                analytics.record(.paywallRestoreSucceeded(context: analyticsContext))
                Haptics.purchaseComplete()
                dismiss()
            case .nothingToRestore:
                analytics.record(
                    .paywallRestoreFailed(
                        context: analyticsContext,
                        message: "no_active_subscription"
                    )
                )
            case .failed(let message):
                analytics.record(.paywallRestoreFailed(
                    context: analyticsContext,
                    message: message
                ))
            }
        }
    }

    private func dismissRecordingExit(reason: PaywallDismissalReason) {
        analytics.record(
            .paywallDismissed(
                context: analyticsContext,
                secondsOnScreen: secondsOnScreen,
                reason: reason
            )
        )
        dismiss()
    }
}

#Preview {
    VaultBoxPaywallView(isHard: true)
        .environment(PurchaseService())
}
