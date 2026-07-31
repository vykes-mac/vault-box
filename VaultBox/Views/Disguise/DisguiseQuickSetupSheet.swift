import SwiftUI
import UIKit

/// First-run disguise picker: choose an icon, apply it, learn the way back in.
///
/// Deliberately *not* a coach-marked tour of Settings → App Icon. Tutorials that teach
/// navigation get skipped; the value here is the outcome, so this sheet performs the
/// change itself and the user learns where it lives by having already done it once.
///
/// Three things this screen has to get right, all of them trust rather than conversion:
///
/// 1. **The iOS confirmation alert is pre-framed.** `setAlternateIconName` shows a system
///    dialog that cannot be suppressed. To someone who just paid to become invisible, an
///    unexpected popup reads as "it went wrong" — so we warn them it is coming and say
///    whose it is.
/// 2. **The Home Screen label is disclosed honestly.** iOS keeps the app name "VaultBox"
///    under whatever icon is showing. Letting someone believe otherwise is how you earn a
///    refund request from the exact person the feature was meant to protect.
/// 3. **The unlock gesture is taught before they can leave.** See ``DisguiseUnlockGuideView``.
struct DisguiseQuickSetupSheet: View {
    /// Called once a disguise is live *and* the user has practised getting back in.
    var onApplied: (AppDisguise) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseService.self) private var purchaseService
    @Environment(AppPrivacyShield.self) private var privacyShield
    @Environment(AnalyticsService.self) private var analytics
    @AppStorage("disguise.hasLearnedPrivateUnlock") private var hasLearnedPrivateUnlock = false

    private let iconService = AppIconService()

    @State private var availableDisguises: [AppDisguise] = []
    @State private var selection: AppDisguise?
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPaywall = false
    @State private var unlockGuideDisguise: AppDisguise?
    /// Set when the icon is live, so dismissing the guide reports success exactly once.
    @State private var appliedDisguise: AppDisguise?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        NavigationStack {
            Group {
                if availableDisguises.isEmpty {
                    unavailableState
                } else {
                    picker
                }
            }
            .background(Color.vaultBackground)
            .navigationTitle("Hide VaultBox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .onAppear {
            availableDisguises = iconService.availableIcons().compactMap { AppDisguise(iconName: $0.id) }
            selection = AppDisguise(iconName: iconService.getCurrentIcon()) ?? availableDisguises.first
        }
        .alert("Couldn't change the icon", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? String(localized: "Please try again."))
        }
        .fullScreenCover(isPresented: $showPaywall) {
            VaultBoxPaywallView()
        }
        .sheet(item: $unlockGuideDisguise, onDismiss: finishAfterGuide) {
            DisguiseUnlockGuideView(disguise: $0) {
                hasLearnedPrivateUnlock = true
                analytics.record(.disguiseUnlockGuideCompleted)
            }
        }
    }

    // MARK: - Picker

    private var picker: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    grid
                    disclosure
                }
                .padding(.horizontal, Constants.standardPadding)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pick what it should look like")
                .font(.title3.bold())
                .foregroundStyle(Color.vaultTextPrimary)

            Text("Anyone scrolling your Home Screen sees a small utility app. Opening it shows a working one — your vault is behind a private gesture.")
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(availableDisguises) { disguise in
                Button {
                    Haptics.itemSelected()
                    selection = disguise
                } label: {
                    DisguiseIconTile(disguise: disguise, isSelected: selection == disguise)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(disguise.displayName)
                .accessibilityAddTraits(selection == disguise ? [.isSelected] : [])
            }
        }
    }

    /// Stated plainly rather than buried. The label limitation is the single most likely
    /// reason a disguise-intent buyer feels misled after paying.
    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("iOS will ask you to confirm the new icon. That alert is Apple's, not ours.")
            } icon: {
                Image(systemName: "bell.badge")
            }

            Label {
                Text("The name under the icon stays “VaultBox”. iOS won't let any app rename itself — only a Shortcut you create yourself can show a different name.")
            } icon: {
                Image(systemName: "textformat")
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.vaultTextSecondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vaultSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                apply()
            } label: {
                ZStack {
                    if isApplying {
                        ProgressView().tint(.white)
                    } else {
                        Text(selection.map {
                            String(
                                format: String(localized: "Disguise as %@"),
                                locale: Locale.current,
                                $0.displayName
                            )
                        } ?? String(localized: "Choose a disguise"))
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.vaultAccent, in: Capsule())
            }
            .disabled(selection == nil || isApplying)

            Text("You'll practise the unlock gesture next.")
                .font(.footnote)
                .foregroundStyle(Color.vaultTextSecondary)
        }
        .padding(.horizontal, Constants.standardPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var unavailableState: some View {
        VStack(spacing: 14) {
            Image(systemName: "app.dashed")
                .font(.system(size: 44))
                .foregroundStyle(Color.vaultTextSecondary)
            Text("Disguises aren't available")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.vaultTextPrimary)
            Text("This device or build doesn't support alternate app icons.")
                .font(.footnote)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func apply() {
        guard let disguise = selection else { return }

        if purchaseService.isPremiumRequired(for: .fakeAppIcon) {
            showPaywall = true
            return
        }

        isApplying = true
        Task {
            privacyShield.beginIconChange()
            defer {
                privacyShield.completeIconChangeRequest()
                isApplying = false
            }

            do {
                try await iconService.setIcon(disguise.rawValue)
                Haptics.pinCorrect()
                analytics.record(.disguiseApplied(disguise: disguise.rawValue))
                appliedDisguise = disguise
                // Always, not just when `hasLearnedPrivateUnlock` is false: this is the
                // user's first disguise, and a stale flag from a previous install must
                // not be what stands between them and their own vault.
                unlockGuideDisguise = disguise
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func finishAfterGuide() {
        guard let applied = appliedDisguise else { return }
        appliedDisguise = nil
        onApplied(applied)
        dismiss()
    }
}

// MARK: - Icon Tile

/// One selectable disguise, drawn with the real icon artwork where the bundle exposes it.
///
/// An SF Symbol cannot answer the only question being asked here — "what will this look
/// like on my Home Screen?" — so the actual icon is preferred and the symbol is a
/// fallback for builds where the image isn't reachable by name.
struct DisguiseIconTile: View {
    let disguise: AppDisguise
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            artwork
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.vaultAccent : Color.clear,
                            lineWidth: 3
                        )
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.white, Color.vaultAccent)
                            .offset(x: 4, y: 4)
                    }
                }

            Text(disguise.displayName)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Color.vaultAccent : Color.vaultTextSecondary)
        }
        .animation(.snappy(duration: 0.16), value: isSelected)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = Self.iconImage(for: disguise) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                disguise.accentColor.opacity(0.16)
                Image(systemName: disguise.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(disguise.accentColor)
            }
        }
    }

    /// `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS` ships each alternate icon as a
    /// named image, so the asset name is tried first; the `-180` variant covers icon sets
    /// that carry a standalone preview file.
    static func iconImage(for disguise: AppDisguise) -> UIImage? {
        UIImage(named: disguise.rawValue) ?? UIImage(named: "\(disguise.rawValue)-180")
    }
}
