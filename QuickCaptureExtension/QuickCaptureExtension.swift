import ExtensionFoundation
import ExtensionKit
import LockedCameraCapture
import SwiftUI

@main
struct QuickCaptureExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            QuickCaptureView(session: session)
        }
    }
}
