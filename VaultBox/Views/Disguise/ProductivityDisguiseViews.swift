import Foundation
import SwiftUI

struct NotesDisguiseView: View {
    @AppStorage("disguise.scratchpad") private var note = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(Date.now, format: .dateTime.month(.wide).day().year())
                    .font(.subheadline)
                    .foregroundStyle(AppDisguise.notes.secondaryTextColor)
                Spacer()
                Text("Saved on device")
                    .font(.caption)
                    .foregroundStyle(AppDisguise.notes.secondaryTextColor)
            }

            TextEditor(text: $note)
                .font(.body)
                .scrollContentBackground(.hidden)
                .foregroundStyle(AppDisguise.notes.primaryTextColor)
                .padding(14)
                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .topLeading) {
                    if note.isEmpty {
                        Text("Write a quick note…")
                            .font(.body)
                            .foregroundStyle(AppDisguise.notes.secondaryTextColor)
                            .padding(.horizontal, 19)
                            .padding(.vertical, 22)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
    }
}

struct TranslateDisguiseView: View {
    @State private var sourceText = ""

    private let translations = [
        "hello": "hola",
        "good morning": "buenos días",
        "good night": "buenas noches",
        "please": "por favor",
        "thank you": "gracias",
        "where is": "dónde está",
        "how much": "cuánto cuesta",
        "yes": "sí",
        "no": "no",
    ]

    private var translation: String {
        let normalized = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return "Traducción" }
        return translations[normalized] ?? String(localized: "Phrase not in offline dictionary")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                languageCard(
                    title: String(localized: "English"),
                    text: $sourceText,
                    isEditable: true
                )

                Image(systemName: "arrow.down")
                    .font(.headline)
                    .foregroundStyle(AppDisguise.translate.accentColor)

                languageCard(
                    title: String(localized: "Spanish"),
                    text: .constant(translation),
                    isEditable: false
                )

                Text("Offline phrasebook supports common travel phrases.")
                    .font(.footnote)
                    .foregroundStyle(AppDisguise.translate.secondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
    }

    private func languageCard(title: String, text: Binding<String>, isEditable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppDisguise.translate.accentColor)

            if isEditable {
                TextField("Enter a phrase", text: text, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .lineLimit(2...4)
            } else {
                Text(text.wrappedValue)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            }
        }
        .font(.title3)
        .foregroundStyle(AppDisguise.translate.primaryTextColor)
        .padding(18)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct MeasureDisguiseView: View {
    @State private var motion = DisguiseMotionModel()

    private var roll: Double { motion.rollDegrees ?? 0 }
    private var pitch: Double { motion.pitchDegrees ?? 0 }
    private var isLevel: Bool { abs(roll) < 1 && abs(pitch) < 1 }
    private var reading: LevelReading { LevelReading(roll: roll, pitch: pitch) }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(AppDisguise.measure.primaryTextColor.opacity(0.18), lineWidth: 2)
                    .frame(width: 240, height: 240)

                Circle()
                    .fill(isLevel ? Color.green : AppDisguise.measure.accentColor)
                    .frame(width: 74, height: 74)
                    .offset(
                        x: CGFloat(max(-75, min(75, roll * 3))),
                        y: CGFloat(max(-75, min(75, pitch * 3)))
                    )
                    .animation(.smooth(duration: 0.12), value: roll)
                    .animation(.smooth(duration: 0.12), value: pitch)

                Circle()
                    .stroke(AppDisguise.measure.primaryTextColor.opacity(0.35), lineWidth: 1)
                    .frame(width: 76, height: 76)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Level")
            .accessibilityValue(reading.accessibilityValue)

            if motion.rollDegrees == nil {
                Text("Motion data is unavailable")
                    .font(.headline)
            } else {
                Text(isLevel ? String(localized: "Level") : reading.displayText)
                    .font(.system(.title, design: .rounded, weight: .semibold))
            }

            Text("Place the device flat on a surface.")
                .font(.subheadline)
                .foregroundStyle(AppDisguise.measure.secondaryTextColor)

            Spacer()
        }
        .foregroundStyle(AppDisguise.measure.primaryTextColor)
        .padding(20)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }
}

struct LevelReading: Equatable {
    let roll: Double
    let pitch: Double

    private var roundedRoll: Int { Int(roll.rounded()) }
    private var roundedPitch: Int { Int(pitch.rounded()) }

    var displayText: String {
        "\(roundedRoll)°  \(roundedPitch)°"
    }

    var accessibilityValue: String {
        String(localized: "Roll \(roundedRoll) degrees, pitch \(roundedPitch) degrees")
    }
}
