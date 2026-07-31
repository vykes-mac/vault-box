import SwiftUI

/// Teaches the gesture that reopens the real vault from behind a utility cover.
///
/// This is the most dangerous moment in the whole disguise feature. A user who applies a
/// disguise and then cannot get back in does not file a support ticket — they delete the
/// app and leave a one-star review saying it locked them out of their own photos. So the
/// guide makes them *perform* the gesture before it will let them leave, rather than
/// describing it and hoping. Every path that applies a disguise must route through here.
///
/// The instructions deliberately live only inside VaultBox. Printing "press and hold to
/// unlock" on the cover itself would defeat the cover.
struct DisguiseUnlockGuideView: View {
    @Environment(\.dismiss) private var dismiss

    let disguise: AppDisguise
    let onCompleted: () -> Void

    @State private var didPracticeGesture = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.vaultAccent)
                    .frame(width: 82, height: 82)
                    .background(Color.vaultAccent.opacity(0.12), in: Circle())

                VStack(spacing: 8) {
                    Text("Remember Your Private Unlock")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text("Practice it here before leaving VaultBox. No instructions or unlock symbol will appear on the utility cover.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                practiceCard

                Spacer(minLength: 0)

                Button(
                    didPracticeGesture
                        ? String(localized: "Done")
                        : String(localized: "Press and hold the title above")
                ) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!didPracticeGesture)
            }
            .padding(24)
            .navigationTitle("Disguise Ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(!didPracticeGesture)
    }

    private var practiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PRACTICE AREA")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Image(systemName: disguise.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(disguise.accentColor)
                    .frame(width: 40, height: 40)
                    .background(disguise.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))

                Text(disguise.coverTitle)
                    .font(.headline)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.8) {
                        guard !didPracticeGesture else { return }
                        Haptics.pinCorrect()
                        onCompleted()
                        withAnimation(.snappy) {
                            didPracticeGesture = true
                        }
                    }
                    .accessibilityLabel("Practice unlock using \(disguise.coverTitle)")

                Spacer()

                if didPracticeGesture {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text(
                didPracticeGesture
                    ? String(localized: "Gesture learned. Use the same hold on the utility title.")
                    : String(localized: "Press and hold “\(disguise.coverTitle)” until you feel the confirmation.")
            )
                .font(.callout)
                .foregroundStyle(didPracticeGesture ? .green : .secondary)
        }
        .padding(18)
        .background(Color.vaultSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
