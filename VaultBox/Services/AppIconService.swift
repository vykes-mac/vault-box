import UIKit

@MainActor
class AppIconService {
    static let availableIcons: [(id: String?, displayName: String, systemImage: String)] = [
        (nil, "VaultBox (Default)", "lock.shield.fill"),
        ("CalculatorIcon", "Calculator", "plus.forwardslash.minus"),
        ("NotesIcon", "Notes", "note.text"),
        ("WeatherIcon", "Weather", "cloud.sun.fill"),
        ("CompassIcon", "Compass", "safari"),
        ("ClockIcon", "Clock", "clock.fill"),
        ("StocksIcon", "Stocks", "chart.line.uptrend.xyaxis"),
        ("TranslateIcon", "Translate", "bubble.left.and.text.bubble.right"),
        ("MeasureIcon", "Measure", "ruler"),
    ]

    func setIcon(_ iconName: String?) async throws {
        try await UIApplication.shared.setAlternateIconName(iconName)
    }

    func getCurrentIcon() -> String? {
        UIApplication.shared.alternateIconName
    }
}
