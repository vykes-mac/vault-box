import AppIntents
import SwiftUI
import WidgetKit

@main
struct QuickCaptureControlsBundle: WidgetBundle {
    var body: some Widget {
        QuickCaptureControl()
    }
}

/// Control Center / Lock Screen / Action button control that opens the secure capture
/// extension. Name and symbol are neutral so the control doesn't expose the vault.
struct QuickCaptureControl: ControlWidget {
    static let kind = "com.pack6.vaultbox.quickcapture"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: QuickCaptureIntent()) {
                Label("Quick Capture", systemImage: "camera.aperture")
            }
        }
        .displayName("Quick Capture")
        .description("Take photos and videos privately.")
    }
}
