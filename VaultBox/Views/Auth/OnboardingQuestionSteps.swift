import SwiftUI

// MARK: - Targets

/// First micro-commitment. Naming what you want hidden is an admission that something
/// needs hiding — every tap raises the cost of walking away empty-handed.
struct OnboardingTargetsStep: View {
    @Binding var selection: Set<String>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingHeadline(
                    eyebrow: String(localized: "Question 1 of 3"),
                    title: String(localized: "What do you need out of sight?"),
                    subtitle: String(localized: "We'll set your vault up around this.")
                )

                VStack(spacing: 10) {
                    ForEach(ProtectionTarget.allCases) { target in
                        OnboardingChoiceRow(
                            icon: target.systemImage,
                            label: target.label,
                            isSelected: selection.contains(target.rawValue),
                            allowsMultiple: true
                        ) {
                            toggle(target.rawValue)
                        }
                    }
                }
            }
            .padding(.horizontal, Constants.standardPadding)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func toggle(_ value: String) {
        Haptics.itemSelected()
        if selection.contains(value) {
            selection.remove(value)
        } else {
            selection.insert(value)
        }
    }
}

// MARK: - Risks

/// Second micro-commitment, and the one that makes the threat a person rather than an
/// abstraction. "A partner or ex" converts far harder than "unauthorised access".
struct OnboardingRisksStep: View {
    @Binding var selection: Set<String>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingHeadline(
                    eyebrow: String(localized: "Question 2 of 3"),
                    title: String(localized: "Who are you keeping it away from?"),
                    subtitle: String(localized: "This stays on your phone. Nobody sees your answer.")
                )

                VStack(spacing: 10) {
                    ForEach(ExposureRisk.allCases) { risk in
                        OnboardingChoiceRow(
                            icon: risk.systemImage,
                            label: risk.label,
                            isSelected: selection.contains(risk.rawValue),
                            allowsMultiple: true
                        ) {
                            toggle(risk.rawValue)
                        }
                    }
                }
            }
            .padding(.horizontal, Constants.standardPadding)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func toggle(_ value: String) {
        Haptics.itemSelected()
        if selection.contains(value) {
            selection.remove(value)
        } else {
            selection.insert(value)
        }
    }
}

// MARK: - History

/// The sharpest question, saved for last. Whatever they pick, the plan screen quotes it
/// back — and an answer you gave yourself is much harder to argue with than our copy.
struct OnboardingHistoryStep: View {
    @Binding var selection: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingHeadline(
                    eyebrow: String(localized: "Question 3 of 3"),
                    title: String(localized: "Has anyone gone through your phone without asking?"),
                    subtitle: nil
                )

                VStack(spacing: 10) {
                    ForEach(SnoopingHistory.allCases) { history in
                        OnboardingChoiceRow(
                            icon: history.systemImage,
                            label: history.label,
                            isSelected: selection == history.rawValue,
                            allowsMultiple: false
                        ) {
                            Haptics.itemSelected()
                            selection = history.rawValue
                        }
                    }
                }
            }
            .padding(.horizontal, Constants.standardPadding)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
