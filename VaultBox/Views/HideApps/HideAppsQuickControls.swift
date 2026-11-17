import SwiftUI

// MARK: - Toolbar Menu

/// The eye button in the vault's toolbar: show hidden apps for a while, or hide them again,
/// one tap after unlocking instead of a trip through Settings.
///
/// Only shown once Hide Apps is set up (access allowed, apps picked), and never in decoy
/// mode — the owning view checks both.
struct HideAppsToolbarMenu: View {
    let onManage: () -> Void
    let onError: (String) -> Void

    @Environment(HideAppsService.self) private var hideApps
    @Environment(PurchaseService.self) private var purchaseService
    @Environment(AnalyticsService.self) private var analytics

    var body: some View {
        Menu {
            if hideApps.isHiding {
                if let reveal = hideApps.activeReveal {
                    Section(HideAppsCopy.visibleUntil(reveal.until)) {
                        Button {
                            hideNow()
                        } label: {
                            Label("Hide Now", systemImage: "eye.slash")
                        }
                    }
                }

                Section {
                    ForEach(HideAppsRevealDuration.allCases) { duration in
                        Button {
                            show(for: duration)
                        } label: {
                            Label(duration.showAllTitle, systemImage: "timer")
                        }
                    }
                    Button {
                        hideApps.showAll()
                        analytics.record(.hideAppsRevealed(entryPoint: .vault))
                    } label: {
                        Label("Show Until I Hide Them", systemImage: "eye")
                    }
                }
            } else {
                Button {
                    hideAgain()
                } label: {
                    Label("Hide Apps Again", systemImage: "eye.slash")
                }
            }

            Button(action: onManage) {
                Label("Manage Hidden Apps", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: hideApps.hiddenAppCount > 0 ? "eye.slash" : "eye")
        }
        .accessibilityLabel(Text("Hidden Apps"))
    }

    private func show(for duration: HideAppsRevealDuration) {
        if let error = hideApps.showTemporarily(nil, for: duration) {
            onError(error)
            return
        }
        analytics.record(
            .hideAppsShownTemporarily(entryPoint: .vault, minutes: duration.rawValue, scope: .all)
        )
    }

    private func hideNow() {
        hideApps.hideNow()
        Haptics.itemSelected()
        analytics.record(.hideAppsApplied(entryPoint: .vault, appCount: hideApps.hiddenAppCount))
    }

    /// Re-hiding is a Premium action; a lapsed user is sent to Manage, where the paywall
    /// explains why.
    private func hideAgain() {
        guard !purchaseService.isPremiumRequired(for: .hideApps) else {
            onManage()
            return
        }
        hideApps.hide()
        Haptics.itemSelected()
        analytics.record(.hideAppsApplied(entryPoint: .vault, appCount: hideApps.hiddenAppCount))
    }
}

// MARK: - Banner

/// A slim bar over the vault while hidden apps are showing, so nobody forgets they are.
/// Forgetting is the main way a hidden app gets seen.
struct HideAppsVisibleBanner: View {
    @Environment(HideAppsService.self) private var hideApps
    @Environment(PurchaseService.self) private var purchaseService
    @Environment(AnalyticsService.self) private var analytics

    let onManage: () -> Void

    var body: some View {
        if let message {
            HStack(spacing: 10) {
                Image(systemName: "eye")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.vaultAccent)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.vaultTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    hide()
                } label: {
                    Text(hideApps.activeReveal == nil ? "Hide" : "Hide Now")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, Constants.standardPadding)
            .padding(.vertical, 10)
            .background(Color.vaultAccent.opacity(0.10))
            .task(id: hideApps.activeReveal?.until) {
                // End the banner, and re-check Screen Time, when the reveal runs out while
                // the vault is open. The extension re-hides the apps either way.
                guard let until = hideApps.activeReveal?.until else { return }
                try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow) + 1))
                guard !Task.isCancelled else { return }
                hideApps.refresh()
            }
        }
    }

    private var message: String? {
        guard hideApps.isAuthorized, hideApps.selectedAppCount > 0 else { return nil }
        if let reveal = hideApps.activeReveal, hideApps.isHiding {
            return reveal.tokens == nil
                ? HideAppsCopy.allVisibleUntil(reveal.until)
                : HideAppsCopy.someVisibleUntil(reveal.until)
        }
        if !hideApps.isHiding {
            return String(localized: "Your hidden apps are showing.")
        }
        return nil
    }

    private func hide() {
        if hideApps.activeReveal != nil && hideApps.isHiding {
            hideApps.hideNow()
        } else if purchaseService.isPremiumRequired(for: .hideApps) {
            onManage()
            return
        } else {
            hideApps.hide()
        }
        Haptics.itemSelected()
        analytics.record(.hideAppsApplied(entryPoint: .vault, appCount: hideApps.hiddenAppCount))
    }
}

// MARK: - Copy

enum HideAppsCopy {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func visibleUntil(_ date: Date) -> String {
        String(localized: "Visible until \(time(date))")
    }

    static func allVisibleUntil(_ date: Date) -> String {
        String(localized: "Hidden apps are showing until \(time(date)).")
    }

    static func someVisibleUntil(_ date: Date) -> String {
        String(localized: "Some hidden apps are showing until \(time(date)).")
    }
}
