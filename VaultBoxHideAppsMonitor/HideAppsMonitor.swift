import Foundation
@preconcurrency import DeviceActivity

/// Re-hides apps when a "show for 15 minutes" timer ends.
///
/// iOS wakes this extension at the end of the Screen Time schedule the app starts for a
/// temporary reveal. It runs whether or not VaultBox is open, which is the whole point:
/// the apps must go away again even if the user never comes back to VaultBox.
final class HideAppsMonitor: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == HideAppsShared.revealActivity,
              let defaults = HideAppsShared.defaults,
              var state = HideAppsStore.load(from: defaults)
        else { return }

        // A longer reveal may have replaced this one since the schedule began. iOS can also
        // wake the extension a little early, so allow a minute of slack.
        if let reveal = state.reveal, reveal.until > Date().addingTimeInterval(60) {
            return
        }

        state.reveal = nil
        state = HideAppsStore.apply(state)
        HideAppsStore.save(state, to: defaults)
    }
}
