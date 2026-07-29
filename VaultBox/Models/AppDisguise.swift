enum AppDisguise: String, CaseIterable, Identifiable {
    case calculator = "CalculatorIcon"
    case notes = "NotesIcon"
    case weather = "WeatherIcon"
    case compass = "CompassIcon"
    case clock = "ClockIcon"
    case stocks = "StockIcon"
    case translate = "TranslateIcon"
    case measure = "MeasureIcon"

    var id: String { rawValue }

    init?(iconName: String?) {
        guard let iconName else { return nil }
        self.init(rawValue: iconName)
    }

    var displayName: String {
        switch self {
        case .calculator: String(localized: "Calculator")
        case .notes: String(localized: "Notes")
        case .weather: String(localized: "Weather")
        case .compass: String(localized: "Compass")
        case .clock: String(localized: "Clock")
        case .stocks: String(localized: "Stocks")
        case .translate: String(localized: "Translate")
        case .measure: String(localized: "Measure")
        }
    }

    var coverTitle: String {
        switch self {
        case .calculator: String(localized: "Quick Calc")
        case .notes: String(localized: "Scratchpad")
        case .weather: String(localized: "Local Outlook")
        case .compass: String(localized: "Direction")
        case .clock: String(localized: "World Time")
        case .stocks: String(localized: "Market Watch")
        case .translate: String(localized: "Phrasebook")
        case .measure: String(localized: "Level")
        }
    }

    var systemImage: String {
        switch self {
        case .calculator: "plus.forwardslash.minus"
        case .notes: "note.text"
        case .weather: "cloud.sun.fill"
        case .compass: "location.north.circle.fill"
        case .clock: "clock.fill"
        case .stocks: "chart.line.uptrend.xyaxis"
        case .translate: "character.bubble.fill"
        case .measure: "level.fill"
        }
    }
}

func shouldPresentDisguiseUnlockGuide(
    iconName: String?,
    hasLearnedGesture: Bool
) -> Bool {
    !hasLearnedGesture && AppDisguise(iconName: iconName) != nil
}
