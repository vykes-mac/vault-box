import Foundation
import UIKit
@preconcurrency import DeviceActivity
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

// MARK: - Availability

/// Whether this build may offer Hide Apps at all.
///
/// Hide Apps runs on Apple's Screen Time API, which needs the Family Controls entitlement
/// (granted to the developer account). The `HIDE_APPS_ENABLED` build setting in
/// project.yml reaches the app through the `HideAppsEnabled` Info.plist key, so the whole
/// feature can be switched off without touching code.
enum HideAppsAvailability {
    static let infoPlistKey = "HideAppsEnabled"

    static let isEnabled = isEnabled(infoDictionary: Bundle.main.infoDictionary)

    static func isEnabled(infoDictionary: [String: Any]?) -> Bool {
        guard let value = infoDictionary?[infoPlistKey] as? String else { return false }
        return ["YES", "TRUE", "1"].contains(value.uppercased())
    }
}

// MARK: - Entry Point

/// Where the user opened Hide Apps from. Sent with analytics so the onboarding, the
/// checklist and Settings can be compared.
enum HideAppsEntryPoint: String, Sendable {
    case settings
    case securitySetup = "security_setup"
    case checklist
    /// The eye button in the vault's toolbar.
    case vault
    /// Re-hidden automatically when Premium came back after a lapse.
    case renewal
}

/// How the end-of-Premium screen for hidden apps was resolved.
enum HideAppsLapseOutcome: String, Sendable {
    case renewed
    case shown
}

/// Whether a temporary reveal covers every hidden app or a single one.
enum HideAppsRevealScope: String, Sendable {
    case all
    case one
}

// MARK: - Reveal Duration

/// How long hidden apps stay visible before they hide again on their own.
///
/// Screen Time schedules can't be shorter than 15 minutes, which sets the shortest option.
enum HideAppsRevealDuration: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case oneHour = 60

    var id: Int { rawValue }

    var seconds: TimeInterval { TimeInterval(rawValue * 60) }

    var showAllTitle: String {
        switch self {
        case .fifteenMinutes: String(localized: "Show for 15 Minutes")
        case .oneHour: String(localized: "Show for 1 Hour")
        }
    }

    var showOneTitle: String {
        switch self {
        case .fifteenMinutes: String(localized: "Show This App for 15 Minutes")
        case .oneHour: String(localized: "Show This App for 1 Hour")
        }
    }
}

// MARK: - Selection Rules

/// Problems with a set of apps picked in Apple's app picker.
///
/// Apple's picker also offers whole categories and websites, but only individual apps can
/// be hidden; categories can only be dimmed, which isn't what this feature promises.
enum HideAppsSelectionIssue: Equatable, Sendable {
    /// Categories or websites were picked but no individual apps.
    case noAppsPicked
    /// Apps were picked alongside categories or websites, which will be left alone.
    case ignoresCategories
    /// More apps than Screen Time accepts in one go.
    case tooManyApps(limit: Int)

    /// Apple caps per-app Screen Time restrictions at 50 apps (documented for shields).
    /// Staying inside it here too avoids a limit that would fail silently.
    static let appLimit = 50

    static func issue(appCount: Int, otherCount: Int) -> HideAppsSelectionIssue? {
        if appCount > appLimit { return .tooManyApps(limit: appLimit) }
        if appCount == 0 && otherCount > 0 { return .noAppsPicked }
        if otherCount > 0 { return .ignoresCategories }
        return nil
    }

    var message: String {
        switch self {
        case .noAppsPicked:
            String(localized: "Only individual apps can be hidden. Open the list and tap the apps themselves, not a category.")
        case .ignoresCategories:
            String(localized: "Categories and websites you picked are left alone. Only individual apps are hidden.")
        case .tooManyApps(let limit):
            String(localized: "You can hide up to \(limit) apps. Remove a few and try again.")
        }
    }

    /// Whether the selection can't be used at all and must not be saved.
    var blocksSaving: Bool {
        switch self {
        case .tooManyApps: true
        case .noAppsPicked, .ignoresCategories: false
        }
    }
}

// MARK: - Premium Lapse

/// When hidden apps come back because Premium ended, and when to warn first.
///
/// Hidden apps must not stay hidden for free forever, or a trial would buy the feature for
/// good. But for a privacy app the worst outcome is a private app reappearing while
/// someone else holds the phone, so every rule here leans towards waiting:
/// - only a lapse RevenueCat itself confirmed counts (never an offline launch, never
///   Apple's billing grace period, during which Premium is still active);
/// - nothing reappears until the user has opened the real vault and read why;
/// - while auto-renew is off, they're warned in the vault before the end date.
enum HideAppsLapsePolicy {
    /// How far ahead of the end date the vault starts warning.
    static let warningWindow: TimeInterval = 7 * 24 * 60 * 60

    static func shouldAskAfterLapse(
        isMainRoute: Bool,
        isDecoyMode: Bool,
        isPremium: Bool,
        hasConfirmedCustomerInfo: Bool,
        isHidingApps: Bool
    ) -> Bool {
        isMainRoute && !isDecoyMode && hasConfirmedCustomerInfo && !isPremium && isHidingApps
    }

    static func shouldWarnBeforeLapse(
        isPremium: Bool,
        isLifetime: Bool,
        willRenew: Bool,
        hasBillingIssue: Bool,
        expirationDate: Date?,
        isHidingApps: Bool,
        dismissedForExpiration: Date?,
        now: Date
    ) -> Bool {
        guard isPremium, !isLifetime, !willRenew, !hasBillingIssue, isHidingApps,
              let expirationDate, expirationDate > now,
              expirationDate.timeIntervalSince(now) <= warningWindow
        else { return false }
        // Dismissing covers this end date only; a new one (after resubscribing and
        // cancelling again) warns again.
        guard let dismissedForExpiration else { return true }
        return abs(dismissedForExpiration.timeIntervalSince(expirationDate)) > 1
    }
}

// MARK: - Service

/// Hides other apps from the Home Screen, App Library and search through Screen Time.
///
/// Uses `ManagedSettingsStore.application.blockedApplications`, which removes the apps
/// rather than `shield`, which only dims them. Hidden apps stay hidden after VaultBox
/// closes and after a restart; the user brings them back from inside VaultBox, by
/// revoking Screen Time access in Settings, or by deleting VaultBox. All three are
/// deliberate escape hatches: nobody can be locked out of their own apps. When Premium
/// ends they come back too, but only after the user has seen why; see
/// ``HideAppsLapsePolicy``.
///
/// Apps can also be shown for a while — all of them or one — and hide again on their own.
/// The timer is a Screen Time schedule, and the HideAppsMonitor extension re-hides the apps
/// when it ends, even if VaultBox is closed. The app double-checks on every launch.
///
/// Apple hands back opaque tokens for the picked apps. VaultBox never learns which apps
/// they are; the UI shows them with Apple's own label view.
@MainActor
@Observable
final class HideAppsService {
    let isAvailable: Bool

    private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    private(set) var state = HideAppsState()

    @ObservationIgnored private let defaults: UserDefaults
    /// The copy of the state the extension reads while the phone is locked.
    @ObservationIgnored private let stateFile: URL?
    @ObservationIgnored private let activityCenter = DeviceActivityCenter()
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    @ObservationIgnored private var releaseBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// Gap between apps when several come back at once. iOS needs them released
    /// separately to put each back in its own Home Screen spot.
    private static let releaseInterval: Duration = .seconds(1)

    /// Where the pick lived before the app group, in the first Hide Apps builds.
    private static let legacySelectionKey = "hideApps.selection"

    init(
        isAvailable: Bool = HideAppsAvailability.isEnabled,
        defaults: UserDefaults? = HideAppsShared.defaults,
        stateFile: URL? = HideAppsStore.sharedStateFileURL
    ) {
        self.isAvailable = isAvailable
        self.defaults = defaults ?? .standard
        self.stateFile = stateFile
        guard isAvailable else { return }
        // The file first: the extension may have updated it while the phone was locked.
        state = stateFile.flatMap(HideAppsStore.load(fromFile:))
            ?? HideAppsStore.load(from: self.defaults)
            ?? Self.migratedState()
        refresh()
    }

    // MARK: State

    var selection: FamilyActivitySelection { state.selection }

    var isAuthorized: Bool { authorizationStatus == .approved }

    /// Hiding is switched on. Apps may still be showing for a while; see ``activeReveal``.
    var isHiding: Bool { isAuthorized && state.isEnabled }

    var selectedAppCount: Int { state.selection.applicationTokens.count }

    /// Apps hidden right now, after any temporary reveal.
    var hiddenAppCount: Int {
        guard isAuthorized else { return 0 }
        return HideAppsRules.appsToHide(
            selected: state.selection.applicationTokens,
            isEnabled: state.isEnabled,
            revealed: state.reveal?.tokens,
            revealUntil: state.reveal?.until,
            now: .now
        ).count
    }

    /// The temporary reveal still running, if any.
    var activeReveal: HideAppsReveal? {
        guard let reveal = state.reveal, reveal.isActive(at: .now) else { return nil }
        return reveal
    }

    func isTemporarilyVisible(_ token: ApplicationToken) -> Bool {
        activeReveal?.includes(token) ?? false
    }

    var selectionIssue: HideAppsSelectionIssue? {
        HideAppsSelectionIssue.issue(
            appCount: state.selection.applicationTokens.count,
            otherCount: state.selection.categoryTokens.count + state.selection.webDomainTokens.count
        )
    }

    /// Re-reads Screen Time access and re-applies the hidden apps, ending any reveal whose
    /// time is up. Call when the app becomes active: the user can revoke access in
    /// Settings, and a reveal can expire while VaultBox is closed.
    func refresh() {
        guard isAvailable else { return }
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        guard isAuthorized else { return }
        let hadReveal = state.reveal != nil
        commit(state)
        if hadReveal && state.reveal == nil {
            activityCenter.stopMonitoring([HideAppsShared.revealActivity])
        }
    }

    // MARK: Actions

    /// Shows Apple's Screen Time prompt (Face ID or passcode). Returns a message to show
    /// the user when it fails, or nil when it succeeded or they cancelled.
    func requestAuthorization() async -> String? {
        guard isAvailable else { return nil }
        var failure: String?
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            failure = Self.message(for: error)
        }
        refresh()
        return failure
    }

    /// Saves a new pick from Apple's app picker. Hides immediately when this is the first
    /// set of apps, and keeps already-hidden apps in step with the new pick.
    ///
    /// - Returns: the problem with the pick, if any. A blocking problem leaves the
    ///   previous pick in place.
    @discardableResult
    func updateSelection(_ newSelection: FamilyActivitySelection) -> HideAppsSelectionIssue? {
        guard isAvailable else { return nil }
        let issue = HideAppsSelectionIssue.issue(
            appCount: newSelection.applicationTokens.count,
            otherCount: newSelection.categoryTokens.count + newSelection.webDomainTokens.count
        )
        if issue?.blocksSaving == true { return issue }

        var next = state
        let wasEmpty = next.selection.applicationTokens.isEmpty
        next.selection = newSelection
        if newSelection.applicationTokens.isEmpty {
            next.isEnabled = false
            next.reveal = nil
        } else if wasEmpty {
            next.isEnabled = true
        }
        commit(next)
        if state.reveal == nil {
            activityCenter.stopMonitoring([HideAppsShared.revealActivity])
        }
        return issue
    }

    /// Hides every picked app, ending any temporary reveal.
    func hide() {
        guard isAvailable, isAuthorized, !state.selection.applicationTokens.isEmpty else { return }
        var next = state
        next.isEnabled = true
        next.reveal = nil
        next.lapsePausedAt = nil
        activityCenter.stopMonitoring([HideAppsShared.revealActivity])
        commit(next)
    }

    /// Shows every picked app until the user hides them again.
    func showAll() {
        guard isAvailable else { return }
        var next = state
        next.isEnabled = false
        next.reveal = nil
        next.lapsePausedAt = nil
        activityCenter.stopMonitoring([HideAppsShared.revealActivity])
        commit(next)
    }

    /// Shows every picked app because Premium ended, remembering the pick so renewing can
    /// hide the same apps again.
    func showAllForLapse(now: Date = .now) {
        guard isAvailable else { return }
        var next = state
        next.isEnabled = false
        next.reveal = nil
        next.lapsePausedAt = now
        activityCenter.stopMonitoring([HideAppsShared.revealActivity])
        commit(next)
    }

    /// Hides the apps shown at a lapse again once Premium is back.
    /// - Returns: whether anything was hidden.
    @discardableResult
    func resumeAfterRenewal() -> Bool {
        guard isAvailable, isAuthorized, state.lapsePausedAt != nil,
              !state.selection.applicationTokens.isEmpty
        else { return false }
        hide()
        return true
    }

    /// Shows apps for a while, then hides them again on their own.
    ///
    /// - Parameter tokens: the apps to show, or nil for all of them.
    /// - Returns: a message to show the user when the timer couldn't be set. Nothing is
    ///   shown in that case: apps that appear without a working timer would stay visible.
    func showTemporarily(
        _ tokens: Set<ApplicationToken>?,
        for duration: HideAppsRevealDuration,
        now: Date = .now
    ) -> String? {
        guard isAvailable, isHiding else { return nil }

        let merged = HideAppsRules.merge(
            existing: activeReveal.map { ($0.tokens, $0.until) },
            adding: tokens,
            until: now.addingTimeInterval(duration.seconds),
            now: now
        )

        do {
            try startRevealTimer(from: now, until: merged.until)
        } catch {
            return String(localized: "The timer to hide your apps again couldn't be set, so nothing was shown. Please try again.")
        }

        var next = state
        next.reveal = HideAppsReveal(tokens: merged.tokens, until: merged.until)
        commit(next)
        return nil
    }

    /// Ends a temporary reveal early.
    func hideNow() {
        guard isAvailable, state.reveal != nil else { return }
        var next = state
        next.reveal = nil
        activityCenter.stopMonitoring([HideAppsShared.revealActivity])
        commit(next)
    }

    // MARK: Private

    /// Saves `next` and brings Screen Time in line with it.
    ///
    /// The state, and so the UI, updates at once; Screen Time catches up over a few seconds
    /// when several apps come back, releasing them one at a time.
    private func commit(_ next: HideAppsState) {
        let next = HideAppsStore.dropExpiredReveal(next, now: .now)
        state = next
        HideAppsStore.save(next, to: defaults)
        if let stateFile {
            HideAppsStore.save(next, toFile: stateFile)
        }
        guard isAuthorized else { return }
        applyToScreenTime(HideAppsStore.appsToHide(for: next, now: .now))
    }

    private func applyToScreenTime(_ target: Set<ApplicationToken>) {
        releaseTask?.cancel()
        let steps = HideAppsRules.releaseSteps(from: HideAppsStore.currentlyHidden(), to: target)
        guard steps.count > 1 else {
            HideAppsStore.write(target)
            endReleaseBackgroundTask()
            return
        }

        // Someone who taps "Show" usually leaves for the app straight away. Ask for a little
        // background time so the rest still come back; if iOS cuts it short, the next
        // launch finishes the job.
        endReleaseBackgroundTask()
        releaseBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "HideAppsRelease") { [weak self] in
            self?.endReleaseBackgroundTask()
        }

        releaseTask = Task { [weak self] in
            for (index, step) in steps.enumerated() {
                if index > 0 {
                    try? await Task.sleep(for: Self.releaseInterval)
                }
                guard !Task.isCancelled else { return }
                HideAppsStore.write(step)
            }
            self?.endReleaseBackgroundTask()
        }
    }

    private func endReleaseBackgroundTask() {
        guard releaseBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(releaseBackgroundTask)
        releaseBackgroundTask = .invalid
    }

    private func startRevealTimer(from start: Date, until end: Date) throws {
        // Time of day only. Schedules that also carry the year, month and day are the ones
        // developers report never reaching intervalDidEnd (Apple forums 774285, 751597);
        // time-of-day schedules are the form Apple documents and Screen Time apps rely on.
        // A reveal never lasts a day, and an end earlier than the start rolls to tomorrow.
        let calendar = Calendar.current
        let parts: Set<Calendar.Component> = [.hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: start),
            intervalEnd: calendar.dateComponents(parts, from: end),
            repeats: false
        )
        activityCenter.stopMonitoring([HideAppsShared.revealActivity])
        try activityCenter.startMonitoring(HideAppsShared.revealActivity, during: schedule)
    }

    /// State for someone upgrading from the first Hide Apps build, which kept the pick in
    /// standard defaults and wrote the hidden apps straight to Screen Time.
    private static func migratedState() -> HideAppsState {
        var state = HideAppsState()
        if let data = UserDefaults.standard.data(forKey: legacySelectionKey),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            state.selection = selection
        }
        let hidden = ManagedSettingsStore(named: HideAppsShared.storeName)
            .application.blockedApplications ?? []
        state.isEnabled = !hidden.isEmpty
        return state
    }

    private static func message(for error: Error) -> String? {
        guard let error = error as? FamilyControlsError else {
            return String(localized: "Screen Time access didn't go through. Please try again.")
        }
        switch error {
        case .authorizationCanceled:
            return nil
        case .restricted:
            return String(localized: "Screen Time is restricted on this iPhone, so apps can't be hidden.")
        case .authenticationMethodUnavailable:
            return String(localized: "Set a passcode for this iPhone first, then try again.")
        case .networkError:
            return String(localized: "Connect to the internet and try again. Apple checks the request online.")
        case .authorizationConflict:
            return String(localized: "Another app is managing Screen Time on this iPhone. Turn it off there, then try again.")
        default:
            return String(localized: "Screen Time access didn't go through. Please try again.")
        }
    }
}
