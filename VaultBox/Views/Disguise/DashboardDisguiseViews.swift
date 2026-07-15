import Foundation
import SwiftUI

struct WeatherDisguiseView: View {
    @AppStorage("disguise.weatherLocation") private var location = "Kingston"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Image(systemName: daytimeSymbol(for: context.date))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 76))

                        TextField("Location", text: $location)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.words)

                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.subheadline)
                            .foregroundStyle(AppDisguise.weather.secondaryTextColor)
                    }
                    .padding(.vertical, 18)

                    HStack(spacing: 12) {
                        outlookCard(title: "Now", value: daylightLabel(for: context.date), symbol: "sun.max")
                        outlookCard(title: "Forecast", value: "Offline", symbol: "wifi.slash")
                    }

                    Text("This lightweight outlook keeps a location and local daylight status without requesting location access.")
                        .font(.footnote)
                        .foregroundStyle(AppDisguise.weather.secondaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
        }
    }

    private func outlookCard(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppDisguise.weather.secondaryTextColor)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppDisguise.weather.primaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
    }

    private func daytimeSymbol(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        return (6..<18).contains(hour) ? "sun.max.fill" : "moon.stars.fill"
    }

    private func daylightLabel(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        return (6..<18).contains(hour) ? "Daylight" : "Night"
    }
}

struct CompassDisguiseView: View {
    @State private var motion = DisguiseMotionModel()

    private var heading: Double { motion.headingDegrees ?? 0 }
    private var reading: CompassReading { CompassReading(heading: heading) }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.white.opacity(0.58))
                    .overlay(Circle().stroke(.black.opacity(0.12), lineWidth: 1))

                ForEach(Array(stride(from: 0, to: 360, by: 30)), id: \.self) { degree in
                    Rectangle()
                        .fill(degree % 90 == 0 ? Color.primary : Color.secondary.opacity(0.5))
                        .frame(width: 2, height: degree % 90 == 0 ? 16 : 9)
                        .offset(y: -116)
                        .rotationEffect(.degrees(Double(degree)))
                }

                VStack {
                    Text("N").foregroundStyle(AppDisguise.compass.accentColor)
                    Spacer()
                    Text("S")
                }
                .font(.headline)
                .padding(.vertical, 18)

                HStack {
                    Text("W")
                    Spacer()
                    Text("E")
                }
                .font(.headline)
                .padding(.horizontal, 18)
            }
            .frame(width: 270, height: 270)
            .rotationEffect(.degrees(-heading))
            .animation(.smooth(duration: 0.12), value: heading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Compass")
            .accessibilityValue(reading.accessibilityValue)

            Text(motion.headingDegrees == nil ? "Heading unavailable" : reading.displayText)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))

            Text("Magnetic heading may be approximate indoors.")
                .font(.footnote)
                .foregroundStyle(AppDisguise.compass.secondaryTextColor)

            Spacer()
        }
        .foregroundStyle(AppDisguise.compass.primaryTextColor)
        .padding(20)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }
}

struct CompassReading: Equatable {
    let heading: Double

    private var roundedHeading: Int {
        Int(heading.rounded()) % 360
    }

    var displayText: String {
        "\(roundedHeading)°"
    }

    var accessibilityValue: String {
        "\(roundedHeading) degrees magnetic"
    }
}

struct ClockDisguiseView: View {
    @State private var startedAt: Date?
    @State private var elapsedBeforeStart: TimeInterval = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let elapsed = formattedElapsed(at: context.date)

            VStack(spacing: 24) {
                Spacer()

                Text(context.date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 54, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline)
                    .foregroundStyle(AppDisguise.clock.secondaryTextColor)

                Divider().overlay(.white.opacity(0.15))
                    .padding(.vertical, 12)

                Text(elapsed)
                    .font(.system(size: 46, weight: .light, design: .monospaced))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Stopwatch")
                    .accessibilityValue(elapsed)

                HStack(spacing: 20) {
                    Button(startedAt == nil ? "Start" : "Stop") {
                        toggleStopwatch(at: context.date)
                    }
                    .buttonStyle(ClockControlButtonStyle(tint: startedAt == nil ? .green : .orange))

                    Button("Reset") {
                        startedAt = nil
                        elapsedBeforeStart = 0
                    }
                    .buttonStyle(ClockControlButtonStyle(tint: .gray))
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private func toggleStopwatch(at date: Date) {
        if let startedAt {
            elapsedBeforeStart += date.timeIntervalSince(startedAt)
            self.startedAt = nil
        } else {
            startedAt = date
        }
    }

    private func formattedElapsed(at date: Date) -> String {
        let running = startedAt.map { date.timeIntervalSince($0) } ?? 0
        let total = max(0, elapsedBeforeStart + running)
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        let hundredths = Int((total * 100).rounded(.down)) % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }
}

private struct ClockControlButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint)
            .frame(width: 96, height: 52)
            .background(tint.opacity(configuration.isPressed ? 0.28 : 0.16), in: Capsule())
    }
}

struct StocksDisguiseView: View {
    @AppStorage("disguise.marketSymbol") private var symbol = ""

    var body: some View {
        VStack(spacing: 18) {
            TextField("Add a symbol", text: $symbol)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.headline)
                .padding(14)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

            if symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "No Symbols",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Add a ticker to your offline watchlist.")
                )
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(symbol.uppercased())
                            .font(.title2.bold())
                        Text("Quote unavailable offline")
                            .font(.caption)
                            .foregroundStyle(AppDisguise.stocks.secondaryTextColor)
                    }
                    Spacer()
                    Text("—")
                        .font(.largeTitle)
                        .foregroundStyle(AppDisguise.stocks.accentColor)
                }
                .padding(18)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))

                Spacer()
            }
        }
        .foregroundStyle(AppDisguise.stocks.primaryTextColor)
        .padding(20)
    }
}
