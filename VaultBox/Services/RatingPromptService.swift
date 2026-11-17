import Foundation
import Observation

// MARK: - Store

/// Persists ``RatingPromptHistory`` in UserDefaults. Rating state is app-level and
/// device-local, so it doesn't belong in the encrypted SwiftData store or in iCloud.
struct RatingPromptStore {
    private let defaults: UserDefaults
    static let historyKey = "ratingPrompt.history"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> RatingPromptHistory {
        guard let data = defaults.data(forKey: Self.historyKey),
              let history = try? JSONDecoder().decode(RatingPromptHistory.self, from: data) else {
            return RatingPromptHistory()
        }
        return history
    }

    func save(_ history: RatingPromptHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: Self.historyKey)
    }
}

// MARK: - Service

/// Collects positive moments from anywhere in the vault and hands them to the presenting
/// view (``RatingPromptHost``), which applies ``RatingPromptPolicy`` against live UI state.
///
/// Trigger sites only call ``registerPositiveMoment(_:)``. They don't know about the
/// policy, the sheet, or Apple's review API.
@MainActor
@Observable
final class RatingPromptService {

    private(set) var history: RatingPromptHistory
    /// The most recent positive moment waiting to be evaluated. Bumped with a new token
    /// each time so the same trigger twice in a row is still observed.
    private(set) var pendingMoment: PendingMoment?
    /// Drives the pre-prompt sheet.
    var presentedTrigger: RatingPromptTrigger?

    struct PendingMoment: Equatable {
        let trigger: RatingPromptTrigger
        let token: UUID
    }

    private let store: RatingPromptStore
    private let now: () -> Date

    init(store: RatingPromptStore = RatingPromptStore(), now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        self.history = store.load()
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: Inputs

    func registerPositiveMoment(_ trigger: RatingPromptTrigger) {
        pendingMoment = PendingMoment(trigger: trigger, token: UUID())
    }

    func consumePendingMoment() -> RatingPromptTrigger? {
        defer { pendingMoment = nil }
        return pendingMoment?.trigger
    }

    func recordActiveDay() {
        guard history.recordActiveDay(now: now()) else { return }
        store.save(history)
    }

    func recordPaywallSeen() {
        history.lastPaywallAt = now()
        store.save(history)
    }

    // MARK: Decision

    func decision(
        for trigger: RatingPromptTrigger,
        isDecoyMode: Bool,
        isUnlocked: Bool,
        isOtherUIPresented: Bool,
        vaultItemCount: Int,
        importCount: Int
    ) -> RatingPromptPolicy.Decision {
        RatingPromptPolicy.evaluate(
            RatingPromptPolicy.Context(
                trigger: trigger,
                now: now(),
                appVersion: appVersion,
                isDecoyMode: isDecoyMode,
                isUnlocked: isUnlocked,
                isOtherUIPresented: isOtherUIPresented,
                vaultItemCount: vaultItemCount,
                importCount: importCount
            ),
            history: history
        )
    }

    // MARK: Presentation

    func present(_ trigger: RatingPromptTrigger) {
        history.recordShown(now: now())
        store.save(history)
        presentedTrigger = trigger
    }

    func recordAnswer(_ answer: RatingPromptAnswer) {
        history.recordAnswer(answer, appVersion: appVersion)
        store.save(history)
    }

    // MARK: Paywall Signal

    @ObservationIgnored private var isObservingPaywalls = false

    /// Watches the existing paywall analytics events so "never right after a paywall"
    /// works without every paywall call site knowing about ratings.
    func observePaywalls(in analytics: AnalyticsService) {
        guard !isObservingPaywalls else { return }
        isObservingPaywalls = true
        analytics.addSink(RatingPromptPaywallSink(service: self))
    }
}

// MARK: - Paywall Sink

/// Notes when any paywall appears or closes. Reads only the event name.
@MainActor
private struct RatingPromptPaywallSink: AnalyticsSink {
    weak var service: RatingPromptService?

    func record(name: String, parameters: [String: String]) {
        guard name == "paywall_viewed" || name == "paywall_dismissed" else { return }
        service?.recordPaywallSeen()
    }
}
