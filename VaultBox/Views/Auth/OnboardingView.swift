import SwiftData
import SwiftUI

// MARK: - Step

/// Ordered funnel. The three question steps sit between the emotional hook and the
/// trust/authority payoff on purpose: commitment is cheapest to collect right after
/// the problem lands and before we ask for anything real (a PIN, then money).
enum OnboardingStep: Int, CaseIterable, Equatable {
    case hook
    case proof
    case targets
    case risks
    case history
    case trust
    case building
    case plan

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    /// Steps the user can walk back into. The build animation is not one of them.
    var allowsBack: Bool {
        switch self {
        case .hook, .building: false
        default: true
        }
    }

    /// Fraction of the funnel complete. Never reaches 1.0 — leaving the bar visibly
    /// short of the end is what makes finishing feel unfinished (Zeigarnik).
    var progress: Double {
        Double(rawValue + 1) / Double(OnboardingStep.allCases.count + 1)
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    let authService: AuthService

    @Environment(AnalyticsService.self) private var analytics
    @Environment(\.scenePhase) private var scenePhase

    @State private var step: OnboardingStep = .hook
    @State private var answers = OnboardingAnswers()
    @State private var showPINSetup = false

    var body: some View {
        VStack(spacing: 0) {
            header

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            footer
        }
        .background {
            OnboardingBackground()
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPINSetup) {
            PINSetupView(
                authService: authService,
                createTitle: String(localized: "Lock your vault"),
                createSubtitle: String(localized: "This PIN is the only way in. Nobody can reset it for you."),
                confirmTitle: String(localized: "Confirm your PIN"),
                confirmSubtitle: String(localized: "Enter it once more so it's locked in."),
                onSuccess: { analytics.record(.pinCreated) }
            )
        }
        .onAppear {
            answers = OnboardingAnswersStore.load()
            analytics.beginFunnelSession()
            analytics.markFunnelStart()
            analytics.record(.onboardingStarted)
            enterStep(step)
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving mid-funnel is the drop-off we'd otherwise never see: these users
            // don't reach another screen we control.
            guard phase == .background, !showPINSetup else { return }
            analytics.record(
                .onboardingBackgrounded(step: step, secondsOnStep: analytics.secondsOnStep())
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .frame(width: 32, height: 32)
            }
            .opacity(step.allowsBack ? 1 : 0)
            .disabled(!step.allowsBack)
            .accessibilityLabel("Back")

            OnboardingProgressBar(progress: step.progress)

            // Balances the leading chevron so the bar stays centred.
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, Constants.standardPadding)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: - Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .hook:
            OnboardingHookStep()
        case .proof:
            OnboardingProofStep()
        case .targets:
            OnboardingTargetsStep(selection: $answers.targets)
        case .risks:
            OnboardingRisksStep(selection: $answers.risks)
        case .history:
            OnboardingHistoryStep(selection: $answers.snoopingHistory)
        case .trust:
            OnboardingTrustStep()
        case .building:
            OnboardingBuildingStep(answers: answers, onComplete: { advance() })
        case .plan:
            OnboardingPlanStep(answers: answers)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if step == .building {
            // No escape hatch while the plan "builds" — the wait is the payoff.
            Color.clear.frame(height: 84)
        } else {
            VStack(spacing: 10) {
                Button {
                    handlePrimaryAction()
                } label: {
                    HStack(spacing: 8) {
                        Text(primaryButtonTitle)
                            .font(.headline)
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        canAdvance ? Color.vaultAccent : Color.vaultAccent.opacity(0.3),
                        in: Capsule()
                    )
                }
                .disabled(!canAdvance)
                .animation(.easeInOut(duration: 0.2), value: canAdvance)

                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .frame(height: 14)
            }
            .padding(.horizontal, Constants.standardPadding)
            .padding(.bottom, 12)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .hook: String(localized: "Lock My Photos Down")
        case .plan: String(localized: "Create My PIN")
        case .targets, .risks: String(localized: "Continue")
        default: String(localized: "Continue")
        }
    }

    private var footnote: String {
        switch step {
        case .hook: String(localized: "Takes about 60 seconds")
        case .targets, .risks: String(localized: "Select all that apply")
        case .plan: String(localized: "Your PIN never leaves this device")
        default: ""
        }
    }

    /// Selection-gated steps refuse to advance until the user has committed to an
    /// answer. The friction is the point: an answer given is an answer defended.
    private var canAdvance: Bool {
        switch step {
        case .targets: !answers.targets.isEmpty
        case .risks: !answers.risks.isEmpty
        case .history: answers.snoopingHistory != nil
        default: true
        }
    }

    // MARK: - Navigation

    private func handlePrimaryAction() {
        guard canAdvance else { return }
        if step == .plan {
            OnboardingAnswersStore.save(answers)
            // Everyone who completes the new funnel is an ad-acquired user: gate them.
            PaywallGate.markRequired()
            Haptics.pinCorrect()
            recordAnswerIfNeeded(for: step)
            analytics.record(
                .onboardingStepAdvanced(step: step, secondsOnStep: analytics.secondsOnStep())
            )
            analytics.record(
                .onboardingCompleted(secondsTotal: analytics.secondsSinceFunnelStart())
            )
            analytics.record(.pinSetupStarted)
            showPINSetup = true
            return
        }
        advance()
    }

    private func advance() {
        guard let next = step.next else { return }
        Haptics.itemSelected()
        OnboardingAnswersStore.save(answers)
        recordAnswerIfNeeded(for: step)
        analytics.record(
            .onboardingStepAdvanced(step: step, secondsOnStep: analytics.secondsOnStep())
        )
        withAnimation(.snappy(duration: 0.32)) {
            step = next
        }
        enterStep(next)
    }

    private func goBack() {
        guard let previous = step.previous, step.allowsBack else { return }
        analytics.record(.onboardingStepBack(from: step, to: previous))
        withAnimation(.snappy(duration: 0.32)) {
            step = previous
        }
        enterStep(previous)
    }

    private func enterStep(_ step: OnboardingStep) {
        analytics.markStepEntered()
        analytics.record(.onboardingStepViewed(step: step))
    }

    /// Records *how many* options the user picked — never which ones. The risks screen
    /// promises the answers never leave the phone, and that promise outranks the metric.
    private func recordAnswerIfNeeded(for step: OnboardingStep) {
        let count: Int
        switch step {
        case .targets: count = answers.targets.count
        case .risks: count = answers.risks.count
        case .history: count = answers.snoopingHistory == nil ? 0 : 1
        default: return
        }
        analytics.record(.onboardingAnswered(step: step, selectedCount: count))
    }
}

#Preview {
    let container = try! ModelContainer(
        for: AppSettings.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    context.insert(AppSettings())
    return OnboardingView(
        authService: AuthService(
            encryptionService: EncryptionService(),
            modelContext: context
        )
    )
    .modelContainer(container)
}
