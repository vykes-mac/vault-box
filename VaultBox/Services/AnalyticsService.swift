import Foundation
import Observation
import OSLog

// MARK: - Sink

/// A destination for funnel events. Adding a real backend is implementing one of these
/// and appending it in ``AnalyticsService/makeDefault()`` — nothing else changes.
@MainActor
protocol AnalyticsSink {
    func record(name: String, parameters: [String: String])
}

/// Logs events during development so the funnel can be verified before any vendor is
/// chosen. Filter for subsystem `com.vaultbox.analytics` in Console.app, or:
///
/// ```
/// xcrun simctl spawn booted log stream --predicate 'subsystem == "com.vaultbox.analytics"'
/// ```
@MainActor
struct ConsoleAnalyticsSink: AnalyticsSink {
    private static let logger = Logger(subsystem: "com.vaultbox.analytics", category: "funnel")

    func record(name: String, parameters: [String: String]) {
        #if DEBUG
        let rendered = parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        Self.logger.debug("\(name, privacy: .public) \(rendered, privacy: .public)")
        #endif
    }
}

// MARK: - Service

/// Funnel instrumentation for onboarding and the paywall.
///
/// Vendor-agnostic on purpose: the events are the asset, the backend is a detail. See
/// ``AnalyticsEvent`` for the privacy contract every sink inherits — in particular that
/// onboarding answer *values* are never recorded, only counts.
@MainActor
@Observable
final class AnalyticsService {

    private var sinks: [AnalyticsSink]

    /// Random, app-scoped, regenerated on reinstall. Not the IDFA, not the IDFV, not
    /// tied to the user — just enough to stitch one person's funnel together.
    /// Because it is neither an ad identifier nor linked to identity, this needs no
    /// App Tracking Transparency prompt.
    private(set) var installID: String

    /// Distinguishes one run through onboarding from a later retry by the same install.
    private(set) var funnelSessionID: String = UUID().uuidString

    private let defaults: UserDefaults
    private let now: () -> Date

    private static let installIDKey = "com.vaultbox.analyticsInstallID"

    init(
        sinks: [AnalyticsSink] = [],
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.sinks = sinks
        self.defaults = defaults
        self.now = now

        if let existing = defaults.string(forKey: Self.installIDKey) {
            installID = existing
        } else {
            let generated = UUID().uuidString
            defaults.set(generated, forKey: Self.installIDKey)
            installID = generated
        }
    }

    /// Ships events to TelemetryDeck, plus the local log in Debug so the funnel can be
    /// verified in the simulator without waiting on the dashboard.
    ///
    /// With no app ID configured the TelemetryDeck sink is absent and analytics stay
    /// local-only — misconfiguration costs data, never a crash.
    static func makeDefault() -> AnalyticsService {
        var initialSinks: [AnalyticsSink] = []
        #if DEBUG
        initialSinks.append(ConsoleAnalyticsSink())
        #endif

        // Create the install ID before TelemetryDeck starts. The SDK emits automatic
        // session/acquisition signals, so its default user must match the user attached
        // to VaultBox events from the first signal onward.
        let service = AnalyticsService(sinks: initialSinks)
        if let telemetryDeck = TelemetryDeckAnalyticsSink(defaultUserID: service.installID) {
            service.addSink(telemetryDeck)
        }
        return service
    }

    func addSink(_ sink: AnalyticsSink) {
        sinks.append(sink)
    }

    // MARK: - Recording

    func record(_ event: AnalyticsEvent) {
        var parameters = event.parameters
        parameters["install_id"] = installID
        parameters["funnel_session_id"] = funnelSessionID

        for sink in sinks {
            sink.record(name: event.name, parameters: parameters)
        }
    }

    /// Starts a fresh funnel session. Called when onboarding begins so a user who
    /// reinstalls or restarts the funnel doesn't corrupt the previous run's timings.
    func beginFunnelSession() {
        funnelSessionID = UUID().uuidString
    }

    // MARK: - Step Timing

    private var stepEnteredAt: Date?
    private var funnelStartedAt: Date?

    func markFunnelStart() {
        funnelStartedAt = now()
    }

    func markStepEntered() {
        stepEnteredAt = now()
    }

    /// Seconds since the current step appeared, or 0 if timing never started.
    func secondsOnStep() -> Double {
        guard let stepEnteredAt else { return 0 }
        return now().timeIntervalSince(stepEnteredAt)
    }

    func secondsSinceFunnelStart() -> Double {
        guard let funnelStartedAt else { return 0 }
        return now().timeIntervalSince(funnelStartedAt)
    }
}
