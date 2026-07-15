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
        case .calculator: "Calculator"
        case .notes: "Notes"
        case .weather: "Weather"
        case .compass: "Compass"
        case .clock: "Clock"
        case .stocks: "Stocks"
        case .translate: "Translate"
        case .measure: "Measure"
        }
    }

    var coverTitle: String {
        switch self {
        case .calculator: "Quick Calc"
        case .notes: "Scratchpad"
        case .weather: "Local Outlook"
        case .compass: "Direction"
        case .clock: "World Time"
        case .stocks: "Market Watch"
        case .translate: "Phrasebook"
        case .measure: "Level"
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
