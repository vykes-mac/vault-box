import SwiftUI
import Combine

// MARK: - ScreenCaptureMonitor

/// Monitors screenshot events using `UIApplication.userDidTakeScreenshotNotification`.
/// Used purely for UX feedback (showing a brief "screenshot captured blank" banner)
/// since `ScreenshotProofView` handles actual prevention via the secure layer.
@MainActor
final class ScreenCaptureMonitor: ObservableObject {
    @Published var screenshotDetected = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.screenshotDetected = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self?.screenshotDetected = false
                    }
                }
            }
            .store(in: &cancellables)
    }
}
