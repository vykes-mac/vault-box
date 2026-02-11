import SwiftUI

struct PINSetupView: View {
    let authService: AuthService

    @State private var pin: String = ""
    @State private var confirmPin: String = ""
    @State private var isConfirming = false
    @State private var dotState: PINDotsView.DotState = .normal
    @State private var shakeOffset: CGFloat = 0
    @State private var errorMessage: String?
    @State private var showBiometricPrompt = false
    @State private var isSubmitting = false

    private var currentPin: String {
        isConfirming ? confirmPin : pin
    }

    private var maxLength: Int {
        isConfirming ? pin.count : Constants.pinMaxLength
    }

    private var setupHintText: String {
        if isConfirming {
            return "Re-enter your \(pin.count)-digit PIN"
        }
        if pin.count < Constants.pinMinLength {
            return "Enter \(Constants.pinMinLength)-\(Constants.pinMaxLength) digits"
        }
        return "Minimum met. Continue now or add up to \(Constants.pinMaxLength) digits."
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Title
            VStack(spacing: 8) {
                Text(isConfirming ? "Confirm your PIN" : "Create a PIN")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.vaultTextPrimary)

                Text(isConfirming ? "Enter your PIN again" : "Choose a PIN to protect your vault")
                    .font(.callout)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 40)

            // Dots
            PINDotsView(
                enteredCount: currentPin.count,
                totalLength: isConfirming ? pin.count : Constants.pinMaxLength,
                state: dotState
            )
            .offset(x: shakeOffset)
            .padding(.bottom, 10)

            Text(setupHintText)
                .font(.caption)
                .foregroundStyle(Color.vaultTextSecondary)
                .padding(.bottom, 10)

            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.vaultDestructive)
                    .padding(.bottom, 8)
            } else {
                Text(" ")
                    .font(.caption)
                    .padding(.bottom, 8)
            }

            // Continue button (only in first entry, after 4+ digits)
            if !isConfirming && pin.count >= Constants.pinMinLength {
                Button("Continue with \(pin.count)-digit PIN") {
                    isConfirming = true
                    errorMessage = nil
                    dotState = .normal
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.vaultAccent)
                .padding(.bottom, 20)
            } else {
                Spacer().frame(height: 44)
            }

            // Keypad
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
        }
        .padding(.horizontal, Constants.standardPadding)
        .background(Color.vaultBackground.ignoresSafeArea())
        .alert("Enable Face ID?", isPresented: $showBiometricPrompt) {
            Button("Enable") {
                Task {
                    _ = await authService.authenticateWithBiometrics(
                        localizedReason: "Enable biometrics to quickly unlock your vault.",
                        unlockSession: false
                    )
                    completeInitialSetup()
                }
            }
            Button("Not Now", role: .cancel) {
                completeInitialSetup()
            }
        } message: {
            Text("Use Face ID to quickly unlock your vault.")
        }
    }

    private func handleDigit(_ digit: String) {
        guard !isSubmitting, currentPin.count < maxLength else { return }

        if isConfirming {
            confirmPin += digit
            if confirmPin.count == pin.count {
                verifyConfirmation()
            }
        } else {
            pin += digit
        }
    }

    private func handleDelete() {
        guard !isSubmitting else { return }
        if isConfirming {
            guard !confirmPin.isEmpty else { return }
            confirmPin.removeLast()
        } else {
            guard !pin.isEmpty else { return }
            pin.removeLast()
        }
        dotState = .normal
        errorMessage = nil
    }

    private func verifyConfirmation() {
        guard !isSubmitting else { return }
        if confirmPin == pin {
            isSubmitting = true
            dotState = .success
            Task {
                try? await Task.sleep(for: .seconds(Constants.pinSuccessDelay))
                do {
                    try await authService.createPIN(pin)
                    if authService.isBiometricsAvailable() {
                        showBiometricPrompt = true
                    } else {
                        completeInitialSetup()
                    }
                } catch {
                    dotState = .error
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        } else {
            dotState = .error
            errorMessage = "PINs don't match. Try again."
            shakeAnimation()
            Task {
                try? await Task.sleep(for: .seconds(Constants.pinShakeDuration))
                confirmPin = ""
                isConfirming = false
                pin = ""
                dotState = .normal
                errorMessage = nil
            }
        }
    }

    private func shakeAnimation() {
        withAnimation(.default.speed(4).repeatCount(4, autoreverses: true)) {
            shakeOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.pinShakeDuration) {
            shakeOffset = 0
        }
    }

    private func completeInitialSetup() {
        do {
            try authService.completeInitialSetup()
        } catch {
            dotState = .error
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }
}

#Preview {
    // Preview requires a mock - just show the layout
    Text("PINSetupView requires AuthService")
}
