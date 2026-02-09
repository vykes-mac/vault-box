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
    @State private var isComplete = false

    private var currentPin: String {
        isConfirming ? confirmPin : pin
    }

    private var maxLength: Int {
        isConfirming ? pin.count : Constants.pinMaxLength
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

                Text(isConfirming ? "Enter your PIN again" : "Choose a 4-8 digit PIN to protect your vault")
                    .font(.callout)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 40)

            // Dots
            PINDotsView(
                enteredCount: currentPin.count,
                totalLength: isConfirming ? pin.count : max(currentPin.count, Constants.pinMinLength),
                state: dotState
            )
            .offset(x: shakeOffset)
            .padding(.bottom, 12)

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
                Button("Continue") {
                    isConfirming = true
                    errorMessage = nil
                    dotState = .normal
                }
                .font(.headline)
                .foregroundStyle(Color.vaultAccent)
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
                    let context = await authService.authenticateWithBiometrics()
                    if context {
                        // Biometrics enabled via successful auth
                    }
                    isComplete = true
                }
            }
            Button("Not Now", role: .cancel) {
                isComplete = true
            }
        } message: {
            Text("Use Face ID to quickly unlock your vault.")
        }
    }

    private func handleDigit(_ digit: String) {
        guard currentPin.count < maxLength else { return }

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
        if confirmPin == pin {
            dotState = .success
            Task {
                try? await Task.sleep(for: .seconds(Constants.pinSuccessDelay))
                do {
                    try await authService.createPIN(pin)
                    if authService.isBiometricsAvailable() {
                        showBiometricPrompt = true
                    } else {
                        isComplete = true
                    }
                } catch {
                    dotState = .error
                    errorMessage = error.localizedDescription
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
}

#Preview {
    // Preview requires a mock - just show the layout
    Text("PINSetupView requires AuthService")
}
