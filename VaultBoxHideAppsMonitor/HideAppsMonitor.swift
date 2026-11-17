import Foundation
import OSLog
@preconcurrency import DeviceActivity

/// Re-hides apps when a "show for 15 minutes" timer ends.
///
/// iOS wakes this extension at the end of the Screen Time schedule the app starts for a
/// temporary reveal. It runs whether or not VaultBox is open, and usually while the phone
/// is locked, which is the whole point: the apps must go away again even if the user
/// never comes back to VaultBox.
///
/// Logs go to Console.app under the subsystem below, so a run can be checked on a
/// connected device.
final class HideAppsMonitor: DeviceActivityMonitor {
    private let log = Logger(subsystem: "com.pack6.vaultbox.HideAppsMonitor", category: "reveal")

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == HideAppsShared.revealActivity else { return }

        guard var state = HideAppsStore.loadShared() else {
            log.error("Reveal ended, but the saved state couldn't be read")
            return
        }

        // iOS also calls this when the app stops an old timer to start a new one. Only act
        // on a reveal that has actually run out: anything else would hide apps the user
        // just asked to see, and saving would overwrite the app's newer state.
        guard let reveal = state.reveal else {
            log.info("Reveal ended with no reveal running; nothing to do")
            return
        }
        // iOS can wake the extension a little early, so allow a minute of slack.
        if reveal.until > Date().addingTimeInterval(60) {
            log.info("A longer reveal replaced this one; leaving apps shown")
            return
        }

        state.reveal = nil
        state = HideAppsStore.apply(state)
        HideAppsStore.saveShared(state)
        log.info("Reveal ended; apps hidden again")
    }
}
