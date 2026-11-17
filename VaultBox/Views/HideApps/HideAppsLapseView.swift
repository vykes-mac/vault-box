import SwiftUI
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

/// Shown when Premium has ended and apps are still hidden.
///
/// Hidden apps don't stay hidden for free, but they never reappear behind the user's back
/// either: this screen comes first, inside the real vault, so they choose the moment. It
/// can't be swiped away. The two ways out are renewing, which keeps everything hidden, or
/// showing the apps, which brings them back one at a time.
///
/// It is the single end-of-Premium message when it applies, so it also mentions what else
/// stopped instead of stacking a second alert on top.
struct HideAppsLapseView: View {
    let disguise: AppDisguise?
    let onShowApps: () -> Void
    let onRenew: () -> Void

    @Environment(HideAppsService.self) private var hideApps

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(Color.vaultPremium.opacity(0.14))
                            .frame(width: 84, height: 84)
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color.vaultPremium)
                    }
                    .padding(.top, 40)

                    VStack(spacing: 10) {
                        Text("Premium has ended")
                            .font(.title2.bold())
                            .foregroundStyle(Color.vaultTextPrimary)

                        Text(appsMessage)
                            .font(.body)
                            .foregroundStyle(Color.vaultTextPrimary)
                            .multilineTextAlignment(.center)

                        Text(otherProtectionsMessage)
                            .font(.subheadline)
                            .foregroundStyle(Color.vaultTextSecondary)
                            .multilineTextAlignment(.center)
                    }

                    appPreview
                }
                .padding(.horizontal, Constants.standardPadding)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 12) {
                Button(action: onRenew) {
                    Text("Renew to Keep Them Hidden")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.vaultAccent, in: Capsule())
                }

                Button(action: onShowApps) {
                    Text("Show My Apps")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.vaultTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, Constants.standardPadding)
            .padding(.bottom, 16)
        }
        .background(Color.vaultBackground.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private var appsMessage: String {
        String(
            format: String(
                localized: "Hide Apps is part of Premium. Renew to keep your %lld hidden apps out of sight, or show them now."
            ),
            locale: Locale.current,
            Int64(hideApps.selectedAppCount)
        )
    }

    private var otherProtectionsMessage: String {
        if let disguise {
            return String(
                format: String(
                    localized: "Your %@ disguise stays on. Break-in photos, the decoy vault, and encrypted backup have stopped, and your vault is limited to %lld items again."
                ),
                locale: Locale.current,
                disguise.displayName,
                Int64(Constants.freeItemLimit)
            )
        }
        return String(
            format: String(
                localized: "Break-in photos, the decoy vault, and encrypted backup have also stopped, and your vault is limited to %lld items again."
            ),
            locale: Locale.current,
            Int64(Constants.freeItemLimit)
        )
    }

    /// The apps that will come back, shown with Apple's own labels so the user knows
    /// exactly what is at stake before choosing.
    private var appPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(hideApps.selection.applicationTokens.prefix(6)), id: \.self) { token in
                Label(token)
                    .foregroundStyle(Color.vaultTextPrimary)
            }
            if hideApps.selectedAppCount > 6 {
                Text(
                    String(
                        format: String(localized: "And %lld more"),
                        locale: Locale.current,
                        Int64(hideApps.selectedAppCount - 6)
                    )
                )
                .font(.footnote)
                .foregroundStyle(Color.vaultTextSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vaultSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
