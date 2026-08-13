import SwiftUI

/// Privacy-led paywall treatment selected by `paywallLayout: privacy_stat` in the
/// RevenueCat Offering metadata. Product prices, trials, purchases, and entitlements
/// remain sourced from RevenueCat; this view changes presentation only.
struct PrivacyStatPaywallContent: View {
    let viewModel: PaywallViewModel
    let canDismiss: Bool
    let ctaTitle: String
    let reassurance: String
    let disclosure: String
    let onDismiss: () -> Void
    let onSelectPlan: (PaywallPlan) -> Void
    let onPurchase: () -> Void
    let onRestore: () -> Void

    @State private var showsBenefits = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                headline
                privacyProof
                benefitsDisclosure
                planPicker
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            purchaseFooter
        }
        .background(Color.vaultBackground.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label {
                Text("VaultBox Premium")
                    .font(.subheadline.weight(.bold))
            } icon: {
                Image(systemName: "checkmark.seal.fill")
            }
            .foregroundStyle(Color.vaultSuccess)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Color.vaultSuccess.opacity(0.14), in: Capsule())

            Spacer(minLength: 0)

            if canDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.vaultTextSecondary)
                        .frame(width: 44, height: 44)
                        .background(Color.vaultSurface, in: Circle())
                }
                .accessibilityLabel("Close")
            }
        }
    }

    private var headline: some View {
        Text(Self.privacyHeadline)
            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
            .foregroundStyle(Color.vaultTextPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var privacyProof: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                statistic(
                    value: "34%",
                    label: String(localized: "U.S. partnered adults")
                )

                Divider()
                    .overlay(Color.vaultTextSecondary.opacity(0.28))

                statistic(
                    value: "26%",
                    label: String(localized: "German adults*")
                )
            }
            .frame(maxWidth: .infinity)

            Text("have secretly checked a partner’s phone")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.vaultTextPrimary)
                .multilineTextAlignment(.center)

            VStack(spacing: 1) {
                Text("*With relationship experience")
                Text("Sources: Pew Research Center · Bitkom Research")
            }
            .font(.caption2)
            .foregroundStyle(Color.vaultTextSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.vaultSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.vaultAccent.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: Color.vaultAccent.opacity(0.28), radius: 14)
        .accessibilityElement(children: .combine)
    }

    private func statistic(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.vaultAccent)
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.vaultTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var benefitsDisclosure: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    showsBenefits.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 31))
                        .foregroundStyle(Color.vaultAccent)
                        .frame(width: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Everything included")
                            .font(.headline)
                            .foregroundStyle(Color.vaultTextPrimary)
                        Text("Storage, disguise, break-in alerts, backup & more")
                            .font(.caption)
                            .foregroundStyle(Color.vaultTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.vaultTextSecondary)
                        .rotationEffect(.degrees(showsBenefits ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsBenefits {
                Divider()
                    .overlay(Color.vaultTextSecondary.opacity(0.15))

                benefits
                    .padding(16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.vaultSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var benefits: some View {
        VStack(spacing: 13) {
            PaywallBenefitRow(
                icon: "infinity",
                title: String(localized: "Unlimited encrypted storage"),
                detail: String(
                    format: String(localized: "Free stops at %lld items. Premium never does."),
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

    private var planPicker: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.plans) { plan in
                PaywallPlanCard(
                    plan: plan,
                    isSelected: viewModel.selectedPlan?.id == plan.id
                ) {
                    onSelectPlan(plan)
                }
            }
        }
    }

    private var purchaseFooter: some View {
        VStack(spacing: 10) {
            Button(action: onPurchase) {
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
            .disabled(viewModel.isPurchasing || viewModel.selectedPlan == nil)

            Text(reassurance)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.vaultTextSecondary)

            PaywallLegalFooter(disclosure: disclosure, onRestore: onRestore)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private static var privacyHeadline: AttributedString {
        let source = String(
            localized: "Your phone gets **shared**. Your **private files** don’t have to."
        )
        var value = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)

        for run in value.runs where
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            value[run.range].foregroundColor = .vaultAccent
        }
        return value
    }
}
