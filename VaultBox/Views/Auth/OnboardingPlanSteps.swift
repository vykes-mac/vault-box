import SwiftUI

// MARK: - Building

/// Deliberate, visible work. Configuration this app could do instantly is shown taking a
/// few seconds because effort you can watch is effort you value (the labour illusion) —
/// and it turns three taps of input into something that feels custom-built.
struct OnboardingBuildingStep: View {
    let answers: OnboardingAnswers
    let onComplete: () -> Void

    @State private var completedCount = 0

    private var tasks: [String] {
        [
            String(localized: "Generating your 256-bit encryption key"),
            String(localized: "Configuring vault for \(answers.targetSummary)"),
            String(localized: "Arming break-in detection"),
            String(localized: "Hiding VaultBox from the Photos app"),
            String(localized: "Sealing your vault")
        ]
    }

    private var progress: Double {
        Double(completedCount) / Double(tasks.count)
    }

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.vaultSurfaceSecondary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.vaultAccent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.45), value: progress)

                Text("\(Int(progress * 100))%")
                    .font(.title.bold())
                    .foregroundStyle(Color.vaultTextPrimary)
                    .contentTransition(.numericText())
            }
            .frame(width: 128, height: 128)

            Text("Building your vault")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.vaultTextPrimary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                    taskRow(task, isDone: index < completedCount, isActive: index == completedCount)
                }
            }
            .padding(.horizontal, Constants.standardPadding)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .task {
            for index in tasks.indices {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 450 : 620))
                withAnimation(.snappy(duration: 0.3)) {
                    completedCount = index + 1
                }
                Haptics.itemSelected()
            }
            try? await Task.sleep(for: .milliseconds(550))
            onComplete()
        }
    }

    private func taskRow(_ task: String, isDone: Bool, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.vaultAccent)
                } else if isActive {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(Color.vaultTextSecondary.opacity(0.35))
                }
            }
            .font(.system(size: 17))
            .frame(width: 22, height: 22)

            Text(task)
                .font(.subheadline)
                .foregroundStyle(isDone || isActive ? Color.vaultTextPrimary : Color.vaultTextSecondary.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.25), value: isDone)
    }
}

// MARK: - Plan

/// The payoff. Their three answers come back as a finished, named plan — the vault now
/// belongs to them, and the only thing standing between them and it is a PIN.
struct OnboardingPlanStep: View {
    let answers: OnboardingAnswers

    @State private var hasAppeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.vaultSuccess)
                    Text("Your vault is ready")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.vaultSuccess)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.vaultSuccess.opacity(0.12), in: Capsule())

                OnboardingHeadline(
                    title: answers.planHeadline,
                    subtitle: String(localized: "Here's what's switched on for you:")
                )

                VStack(spacing: 18) {
                    OnboardingFactRow(
                        icon: "lock.doc.fill",
                        title: String(localized: "Encrypted storage for \(answers.targetSummary)"),
                        detail: String(localized: "Locked with AES-256 the second it's imported, and wiped from your camera roll.")
                    )

                    ForEach(answers.exposureRisks) { risk in
                        OnboardingFactRow(
                            icon: risk.systemImage,
                            title: protectionTitle(for: risk),
                            detail: protectionDetail(for: risk)
                        )
                    }

                    OnboardingFactRow(
                        icon: "camera.metering.center.weighted",
                        title: String(localized: "Break-in alerts"),
                        detail: String(localized: "A silent photo of anyone who guesses your PIN wrong, with the time it happened.")
                    )
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 14)
            }
            .padding(.horizontal, Constants.standardPadding)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task {
            withAnimation(.easeOut(duration: 0.45).delay(0.15)) {
                hasAppeared = true
            }
        }
    }

    private func protectionTitle(for risk: ExposureRisk) -> String {
        switch risk {
        case .borrowedPhone: String(localized: "Disguised app icon")
        case .partner: String(localized: "Decoy vault")
        case .family: String(localized: "PIN + Face ID lock")
        case .lostOrStolen: String(localized: "Auto-lock & panic gesture")
        case .cloudLeak: String(localized: "Encrypted iCloud backup")
        }
    }

    private func protectionDetail(for risk: ExposureRisk) -> String {
        switch risk {
        case .borrowedPhone:
            String(localized: "VaultBox can look like a calculator, notes app, or clock on your home screen.")
        case .partner:
            String(localized: "A second PIN opens a harmless-looking vault, so being asked to unlock costs you nothing.")
        case .family:
            String(localized: "Nothing opens without your PIN or your face — not even the app switcher preview.")
        case .lostOrStolen:
            String(localized: "Locks itself the moment you leave the app, and a shake can slam it shut instantly.")
        case .cloudLeak:
            String(localized: "Backups are encrypted before they leave your phone, so the cloud only ever holds noise.")
        }
    }
}
