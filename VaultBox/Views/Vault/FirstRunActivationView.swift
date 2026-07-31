import SwiftUI

/// Stands in for the empty vault on first run and points at the two things that make the
/// app worth keeping.
///
/// It replaces the empty state rather than overlaying it. An empty screen that says
/// "No Items Yet" is the moment a paid install decides the app is a filing cabinet it
/// doesn't need; the same pixels can instead be a short list with one obvious next tap.
///
/// A checklist beats a modal walkthrough here for three reasons: a dismissed walkthrough
/// is gone forever while this comes back until it's done, there is no "Skip" to punish,
/// and an unfinished list is an open loop people come back to close (Zeigarnik) — the same
/// mechanic the onboarding progress bar already uses.
/// Purely presentational: the "viewed" event is recorded by the owning view, whose
/// identity is stable. Recording it here double-counted, because this view is recreated
/// when the vault query settles and a `.task` runs again on the new identity.
struct FirstRunActivationView: View {
    let checklist: ActivationChecklist
    let onSelect: (ActivationStep) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                steps
                dismissButton
            }
            .padding(.horizontal, Constants.standardPadding)
            .padding(.vertical, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.vaultAccent.opacity(0.12))
                    .frame(width: 76, height: 76)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.vaultAccent)
            }

            Text("Your vault is ready")
                .font(.title2.bold())
                .foregroundStyle(Color.vaultTextPrimary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)

            progress
                .padding(.top, 4)
        }
    }

    private var subtitle: String {
        let remaining = checklist.totalCount - checklist.completedCount
        switch remaining {
        case 0: return String(localized: "Everything's set up.")
        case 1: return String(localized: "One step left to make it genuinely private.")
        default:
            return String(
                format: String(localized: "%lld steps left to make it genuinely private."),
                locale: Locale.current,
                Int64(remaining)
            )
        }
    }

    private var progress: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.vaultSurfaceSecondary)
                    Capsule()
                        .fill(Color.vaultAccent)
                        .frame(
                            width: proxy.size.width
                                * CGFloat(checklist.completedCount)
                                / CGFloat(max(1, checklist.totalCount))
                        )
                }
            }
            .frame(height: 6)
            .animation(.snappy, value: checklist.completedCount)

            Text(
                String(
                    format: String(localized: "%lld of %lld complete"),
                    locale: Locale.current,
                    Int64(checklist.completedCount),
                    Int64(checklist.totalCount)
                )
            )
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.vaultTextSecondary)
        }
        .frame(maxWidth: 260)
    }

    // MARK: - Steps

    private var steps: some View {
        VStack(spacing: 10) {
            ForEach(ActivationStep.allCases) { step in
                ActivationStepRow(
                    step: step,
                    isComplete: checklist.isComplete(step),
                    // Exactly one row gets the accent. Two competing calls to action read
                    // as none, and the ordering already encodes which matters more.
                    isNext: checklist.nextStep == step,
                    action: { onSelect(step) }
                )
            }
        }
    }

    private var dismissButton: some View {
        Button("I'll explore on my own", action: onDismiss)
            .font(.footnote)
            .foregroundStyle(Color.vaultTextSecondary)
    }
}

// MARK: - Row

struct ActivationStepRow: View {
    let step: ActivationStep
    let isComplete: Bool
    let isNext: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                indicator

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            isComplete ? Color.vaultTextSecondary : Color.vaultTextPrimary
                        )
                        .multilineTextAlignment(.leading)

                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(Color.vaultTextSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                if !isComplete {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(
                            isNext ? Color.vaultAccent : Color.vaultTextSecondary.opacity(0.6)
                        )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isNext ? Color.vaultAccent.opacity(0.10) : Color.vaultSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isNext ? Color.vaultAccent : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(isComplete)
        .accessibilityLabel(step.title)
        .accessibilityValue(
            isComplete
                ? String(localized: "Complete")
                : String(localized: "Not started")
        )
        .accessibilityHint(isComplete ? "" : step.actionLabel)
    }

    private var indicator: some View {
        ZStack {
            Circle()
                .fill(
                    isComplete
                        ? Color.vaultSuccess.opacity(0.15)
                        : (isNext ? Color.vaultAccent : Color.vaultSurfaceSecondary)
                )
                .frame(width: 34, height: 34)

            Image(systemName: isComplete ? "checkmark" : step.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(
                    isComplete
                        ? Color.vaultSuccess
                        : (isNext ? .white : Color.vaultTextSecondary)
                )
        }
    }
}

#Preview {
    FirstRunActivationView(
        checklist: ActivationChecklist(isDisguised: false, hasItems: false),
        onSelect: { _ in },
        onDismiss: {}
    )
    .background(Color.vaultBackground)
}
