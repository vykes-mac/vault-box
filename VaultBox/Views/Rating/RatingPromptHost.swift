import StoreKit
import SwiftData
import SwiftUI
import UIKit

extension View {
    /// Presents the rating pre-prompt after positive moments reported to `service`, when
    /// ``RatingPromptPolicy`` allows it. Attach once, near the root of the unlocked vault.
    func ratingPromptHost(_ service: RatingPromptService, authService: AuthService) -> some View {
        modifier(RatingPromptHost(service: service, authService: authService))
    }
}

/// Owns the pre-prompt sheet and the hand-off to Apple's rating sheet.
struct RatingPromptHost: ViewModifier {
    let service: RatingPromptService
    let authService: AuthService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @Environment(AnalyticsService.self) private var analytics
    @Environment(AppPrivacyShield.self) private var privacyShield

    @State private var evaluationTask: Task<Void, Never>?
    @State private var shownTrigger: RatingPromptTrigger?
    @State private var hasAnswered = false

    /// Pause before the first check, so the sheet or cover where the success happened
    /// has finished closing.
    private static let settleDelay: Duration = .milliseconds(700)
    /// Something else may still be on screen (an alert after an import, a sheet closing).
    /// Check again a few times, then let the moment go.
    private static let retryDelay: Duration = .seconds(1)
    private static let maxAttempts = 6
    /// Apple's sheet is silently dropped if requested while ours is still animating away.
    private static let reviewRequestDelay: Duration = .milliseconds(600)

    func body(content: Content) -> some View {
        content
            .onAppear {
                service.observePaywalls(in: analytics)
                recordActiveDayIfNeeded()
            }
            .onChange(of: authService.isUnlocked) { _, isUnlocked in
                if isUnlocked {
                    recordActiveDayIfNeeded()
                } else {
                    evaluationTask?.cancel()
                    service.presentedTrigger = nil
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { recordActiveDayIfNeeded() }
            }
            .onChange(of: service.pendingMoment) { _, moment in
                guard moment != nil else { return }
                scheduleEvaluation()
            }
            .sheet(
                item: Binding(
                    get: { service.presentedTrigger },
                    set: { service.presentedTrigger = $0 }
                ),
                onDismiss: handleDismiss
            ) { trigger in
                RatingPromptView(
                    onYes: { answerYes(trigger) },
                    onNotReally: { answerNotReally(trigger) },
                    onEmailSupport: {
                        analytics.record(.ratingPromptFeedbackOpened(trigger: trigger))
                        service.presentedTrigger = nil
                    },
                    onNotNow: { service.presentedTrigger = nil }
                )
            }
    }

    // MARK: - Engagement

    private func recordActiveDayIfNeeded() {
        // Decoy openings may not be the owner, so they don't count as engagement.
        guard authService.isUnlocked, !authService.isDecoyMode else { return }
        service.recordActiveDay()
    }

    // MARK: - Evaluation

    private func scheduleEvaluation() {
        evaluationTask?.cancel()
        evaluationTask = Task { @MainActor in
            for attempt in 0..<Self.maxAttempts {
                try? await Task.sleep(for: attempt == 0 ? Self.settleDelay : Self.retryDelay)
                guard !Task.isCancelled else { return }
                guard let trigger = service.pendingMoment?.trigger else { return }

                let decision = service.decision(
                    for: trigger,
                    isDecoyMode: authService.isDecoyMode,
                    isUnlocked: authService.isUnlocked,
                    isOtherUIPresented: isOtherUIPresented(),
                    vaultItemCount: (try? VaultItem.liveItemCount(in: modelContext)) ?? 0,
                    importCount: currentImportCount()
                )
                switch decision {
                case .show:
                    _ = service.consumePendingMoment()
                    present(trigger)
                    return
                case .skip(.otherUIPresented):
                    continue
                case .skip:
                    _ = service.consumePendingMoment()
                    return
                }
            }
            _ = service.consumePendingMoment()
        }
    }

    private func currentImportCount() -> Int {
        let settings = try? modelContext.fetch(FetchDescriptor<AppSettings>()).first
        return settings?.importCount ?? 0
    }

    /// Any sheet, cover, alert or paywall already up, or the app not in front.
    private func isOtherUIPresented() -> Bool {
        if service.presentedTrigger != nil || privacyShield.isVisible { return true }
        guard UIApplication.shared.applicationState == .active else { return true }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return true
        }
        return root.presentedViewController != nil
    }

    // MARK: - Answers

    private func present(_ trigger: RatingPromptTrigger) {
        hasAnswered = false
        shownTrigger = trigger
        service.present(trigger)
        analytics.record(
            .ratingPromptShown(trigger: trigger, promptNumber: service.history.promptCount)
        )
    }

    private func answerYes(_ trigger: RatingPromptTrigger) {
        hasAnswered = true
        service.recordAnswer(.yes)
        analytics.record(.ratingPromptAnsweredYes(trigger: trigger))
        service.presentedTrigger = nil

        let requestReview = requestReview
        Task { @MainActor in
            try? await Task.sleep(for: Self.reviewRequestDelay)
            // Apple decides whether its sheet actually appears (at most three times a
            // year, never in TestFlight). Nothing to do if it doesn't.
            requestReview()
        }
    }

    private func answerNotReally(_ trigger: RatingPromptTrigger) {
        hasAnswered = true
        service.recordAnswer(.notReally)
        analytics.record(.ratingPromptAnsweredNotReally(trigger: trigger))
    }

    private func handleDismiss() {
        defer { shownTrigger = nil }
        // History already counts an unanswered prompt as dismissed.
        guard !hasAnswered, let shownTrigger else { return }
        analytics.record(.ratingPromptDismissed(trigger: shownTrigger))
    }
}
