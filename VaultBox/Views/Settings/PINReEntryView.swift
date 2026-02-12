import SwiftUI

struct PINReEntryView: View {
    let authService: AuthService
    let onVerified: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pin = ""
    @State private var pinLength = 4
    @State private var dotState: PINDotsView.DotState = .normal
    @State private var shakeOffset: CGFloat = 0
    @State private var isVerifying = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                    .frame(maxHeight: .infinity)

                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.vaultTextPrimary)
                    .padding(.bottom, 16)

                Text("Re-enter your PIN")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.vaultTextPrimary)
                    .padding(.bottom, 32)

                PINDotsView(
                    enteredCount: pin.count,
                    totalLength: pinLength,
                    state: dotState
                )
                .offset(x: shakeOffset)
                .padding(.bottom, 12)

                Text(" ")
                    .font(.caption)
                    .padding(.bottom, 8)

                Spacer().frame(height: 44)

                PINKeypadView(
                    onDigitTap: { digit in
                        handleDigit(digit)
                    },
                    onDeleteTap: {
                        handleDelete()
                    },
                    onBiometricTap: nil,
                    biometricType: .none
                )

                Spacer()
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, Constants.standardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.vaultBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(Color.vaultBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                pinLength = authService.getPINLength()
            }
        }
        .presentationBackground(Color.vaultBackground)
    }

    // MARK: - Input

    private func handleDigit(_ digit: String) -> Bool {
        guard !isVerifying, pin.count < pinLength else { return false }

        pin += digit
        dotState = .normal

        if pin.count == pinLength {
            verify()
        }
        return true
    }

    private func handleDelete() -> Bool {
        guard !pin.isEmpty, !isVerifying else { return false }
        pin.removeLast()
        dotState = .normal
        return true
    }

    // MARK: - Verification

    private func verify() {
        guard !isVerifying else { return }
        isVerifying = true

        Task {
            let result = await authService.verifyPIN(pin)

            switch result {
            case .success:
                Haptics.pinCorrect()
                dotState = .success
                try? await Task.sleep(for: .seconds(Constants.pinSuccessDelay))
                dismiss()
                onVerified()

            case .decoy:
                // Block Wi-Fi Transfer from decoy mode
                Haptics.pinWrong()
                dotState = .error
                shakeAnimation()
                try? await Task.sleep(for: .seconds(Constants.pinShakeDuration))
                pin = ""
                dotState = .normal

            case .failure, .locked:
                Haptics.pinWrong()
                dotState = .error
                shakeAnimation()
                try? await Task.sleep(for: .seconds(Constants.pinShakeDuration))
                pin = ""
                dotState = .normal
            }

            isVerifying = false
        }
    }

    // MARK: - Animation

    private func shakeAnimation() {
        withAnimation(.default.speed(4).repeatCount(4, autoreverses: true)) {
            shakeOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.pinShakeDuration) {
            shakeOffset = 0
        }
    }
}
