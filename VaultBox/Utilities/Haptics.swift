import UIKit

@MainActor
enum Haptics {
    static func pinDigitTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func pinDeleteTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func pinCorrect() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func pinWrong() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func itemSelected() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func deleteConfirmed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func purchaseComplete() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func panicTriggered() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
}
