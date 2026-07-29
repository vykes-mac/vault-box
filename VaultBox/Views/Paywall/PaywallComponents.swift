import SwiftUI

// MARK: - Plan Card

/// One selectable subscription option. The yearly card carries the badge and the
/// per-week price so the weekly option reads as the expensive one at a glance.
struct PaywallPlanCard: View {
    let plan: PaywallPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.vaultAccent : Color.vaultTextSecondary.opacity(0.45))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.headline)
                            .foregroundStyle(Color.vaultTextPrimary)

                        if let savings = plan.savingsPercent {
                            Text(
                                String(
                                    format: String(localized: "SAVE %lld%%"),
                                    locale: Locale.current,
                                    Int64(savings)
                                )
                            )
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.vaultPremium, in: Capsule())
                        }
                    }

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.vaultTextSecondary)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.priceString)
                        .font(.headline)
                        .foregroundStyle(Color.vaultTextPrimary)
                    Text(plan.pricePeriod)
                        .font(.caption2)
                        .foregroundStyle(Color.vaultTextSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.vaultAccent.opacity(0.12) : Color.vaultSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.vaultAccent : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var subtitle: String {
        if let trialDays = plan.trialDays {
            return String(
                format: String(localized: "%lld days free, then %@"),
                locale: Locale.current,
                Int64(trialDays),
                plan.priceString
            )
        }
        if let perWeek = plan.perWeekString, plan.kind == .annual {
            return String(
                format: String(localized: "Just %@ per week"),
                locale: Locale.current,
                perWeek
            )
        }
        return String(
            format: String(localized: "Billed %@"),
            locale: Locale.current,
            plan.pricePeriod
        )
    }
}

// MARK: - Trial Timeline

/// Removes the two objections that kill trial starts: "when am I charged?" and
/// "will I forget?". Showing the reminder as a step is only fair because
/// ``TrialReminderService`` actually schedules it.
struct PaywallTrialTimeline: View {
    let trialDays: Int
    let priceString: String

    private var reminderDay: Int {
        max(1, trialDays - TrialReminderService.leadDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineRow(
                icon: "lock.open.fill",
                title: String(localized: "Today — everything unlocks"),
                detail: String(localized: "Full access to every feature. You pay nothing now."),
                isLast: false,
                isFilled: true
            )
            timelineRow(
                icon: "bell.badge.fill",
                title: String(
                    format: String(localized: "Day %lld — we remind you"),
                    locale: Locale.current,
                    Int64(reminderDay)
                ),
                detail: String(localized: "A notification before your trial ends, so nothing is a surprise."),
                isLast: false,
                isFilled: true
            )
            timelineRow(
                icon: "creditcard.fill",
                title: String(
                    format: String(localized: "Day %lld — trial ends"),
                    locale: Locale.current,
                    Int64(trialDays)
                ),
                detail: String(
                    format: String(localized: "You're charged %@ unless you cancel before then."),
                    locale: Locale.current,
                    priceString
                ),
                isLast: true,
                isFilled: false
            )
        }
        .padding(16)
        .background(Color.vaultSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func timelineRow(
        icon: String,
        title: String,
        detail: String,
        isLast: Bool,
        isFilled: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isFilled ? Color.vaultAccent : Color.vaultSurfaceSecondary)
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isFilled ? .white : Color.vaultTextSecondary)
                }

                if !isLast {
                    Rectangle()
                        .fill(Color.vaultAccent.opacity(0.35))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.vaultTextPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 18)

            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Benefit Row

/// Compact benefit line. Kept to one row each so the plan cards and the CTA stay
/// above the fold — a benefit nobody scrolls to sells nothing.
struct PaywallBenefitRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.vaultAccent)
                .frame(width: 26, height: 26)
                .background(Color.vaultAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.vaultTextPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Legal Footer

struct PaywallLegalFooter: View {
    let disclosure: String
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(disclosure)
                .font(.caption2)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Button("Restore", action: onRestore)
                Link(
                    String(localized: "Terms"),
                    destination: URL(string: "https://vaultbox.pacsix.com/terms/")!
                )
                Link(
                    String(localized: "Privacy"),
                    destination: URL(string: "https://vaultbox.pacsix.com/privacy/")!
                )
            }
            .font(.caption)
            .foregroundStyle(Color.vaultTextSecondary)
        }
    }
}
