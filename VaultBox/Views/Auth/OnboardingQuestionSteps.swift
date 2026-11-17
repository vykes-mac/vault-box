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
                    eyebrow: OnboardingStep.targets.questionEyebrow(),
                    title: String(localized: "What do you need out of sight?"),
                    subtitle: String(localized: "We'll set your vault up around this.")
                )

                VStack(spacing: 10) {
                    ForEach(ProtectionTarget.available()) { target in
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
                    eyebrow: OnboardingStep.risks.questionEyebrow(),
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
                    eyebrow: OnboardingStep.history.questionEyebrow(),
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

// MARK: - Apps

/// Primes Hide Apps. Most people don't know an app can hide other apps, so the question
/// doubles as the introduction: each kind they tick vanishes from a little Home Screen
/// above the answers, showing the feature before they've seen the vault.
struct OnboardingAppsStep: View {
    @Binding var selection: Set<String>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingHeadline(
                    eyebrow: OnboardingStep.apps.questionEyebrow(),
                    title: String(localized: "Any apps you'd rather nobody saw?"),
                    subtitle: String(localized: "VaultBox can make apps vanish from your Home Screen, App Library and search.")
                )

                OnboardingHomeScreenPreview(hiddenKinds: hiddenKinds)

                VStack(spacing: 10) {
                    ForEach(PrivateAppKind.allCases) { kind in
                        OnboardingChoiceRow(
                            icon: kind.systemImage,
                            label: kind.label,
                            isSelected: selection.contains(kind.rawValue),
                            allowsMultiple: true
                        ) {
                            Haptics.itemSelected()
                            withAnimation(.snappy(duration: 0.3)) {
                                selection = PrivateAppKind.toggling(kind, in: selection)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Constants.standardPadding)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var hiddenKinds: Set<PrivateAppKind> {
        Set(selection.compactMap(PrivateAppKind.init(rawValue:)))
    }
}

/// A stylised Home Screen of generic app icons. Icons for the kinds the user picked fade
/// to an empty outline, the way the real apps will disappear.
struct OnboardingHomeScreenPreview: View {
    let hiddenKinds: Set<PrivateAppKind>

    private struct Tile: Identifiable {
        let id: Int
        let symbol: String
        let color: Color
        let kind: PrivateAppKind?
    }

    private let tiles: [Tile] = [
        Tile(id: 0, symbol: "cloud.sun.fill", color: .blue, kind: nil),
        Tile(id: 1, symbol: "heart.fill", color: .pink, kind: .dating),
        Tile(id: 2, symbol: "camera.fill", color: .gray, kind: nil),
        Tile(id: 3, symbol: "bubble.left.and.bubble.right.fill", color: .green, kind: .chat),
        Tile(id: 4, symbol: "person.2.fill", color: .indigo, kind: .social),
        Tile(id: 5, symbol: "music.note", color: .red, kind: nil),
        Tile(id: 6, symbol: "creditcard.fill", color: .teal, kind: .money),
        Tile(id: 7, symbol: "gamecontroller.fill", color: .orange, kind: .games)
    ]

    private var hiddenCount: Int {
        tiles.filter { $0.kind.map(hiddenKinds.contains) ?? false }.count
    }

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 16) {
                ForEach(tiles) { tile in
                    tileView(tile, isHidden: tile.kind.map(hiddenKinds.contains) ?? false)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: hiddenCount > 0 ? "eye.slash.fill" : "hand.tap.fill")
                Text(caption)
                    .contentTransition(.numericText())
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(hiddenCount > 0 ? Color.vaultAccent : Color.vaultTextSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.vaultSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.vaultTextSecondary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(caption))
    }

    private var caption: String {
        hiddenCount == 0
            ? String(localized: "Pick below and watch them disappear")
            : String(localized: "\(hiddenCount) hidden from your Home Screen")
    }

    private func tileView(_ tile: Tile, isHidden: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tile.color.gradient)
                    .overlay {
                        Image(systemName: tile.symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .opacity(isHidden ? 0 : 1)
                    .scaleEffect(isHidden ? 0.6 : 1)

                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        Color.vaultTextSecondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                    )
                    .opacity(isHidden ? 1 : 0)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 56)

            Capsule()
                .fill(Color.vaultTextSecondary.opacity(isHidden ? 0 : 0.25))
                .frame(width: 30, height: 4)
        }
        .animation(.snappy(duration: 0.3), value: isHidden)
    }
}
