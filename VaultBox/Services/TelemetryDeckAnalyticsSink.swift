import Foundation
import TelemetryDeck

/// Sends funnel events to TelemetryDeck.
///
/// Chosen over general-purpose analytics because VaultBox's own onboarding tells the
/// user "nothing reaches a server". TelemetryDeck sends no IDFA, sets no cookies, and
/// salts+hashes its user identifier, so it needs no App Tracking Transparency prompt and
/// nothing here is "tracking" under Apple's definition.
///
/// The privacy contract in ``AnalyticsEvent`` still applies and is stricter than the
/// vendor's: onboarding answer values never leave the device, only counts.
@MainActor
struct TelemetryDeckAnalyticsSink: AnalyticsSink {

    /// Creates the sink and starts the SDK, or returns `nil` when no app ID is
    /// configured — a missing ID must degrade to local-only, never crash a paying user.
    init?(appID: String = Constants.telemetryDeckAppID, defaultUserID: String) {
        guard !appID.isEmpty, !defaultUserID.isEmpty else { return nil }
        TelemetryDeck.initialize(
            config: Self.makeConfiguration(appID: appID, defaultUserID: defaultUserID)
        )
    }

    static func makeConfiguration(
        appID: String,
        defaultUserID: String
    ) -> TelemetryDeck.Config {
        let config = TelemetryDeck.Config(appID: appID)
        config.defaultUser = defaultUserID
        return config
    }

    func record(name: String, parameters: [String: String]) {
        // The SDK hashes its configured default user before sending it. Remove the raw
        // install ID from event parameters so it never leaves the device as metadata.
        var payload = parameters
        payload.removeValue(forKey: "install_id")

        TelemetryDeck.signal(name, parameters: payload)
    }
}
