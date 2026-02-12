import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    let authService: AuthService
    let onPresented: (() -> Void)?

    @State private var pin: String = ""
    @State private var pinLength: Int = 4
    @State private var dotState: PINDotsView.DotState = .normal
    @State private var shakeOffset: CGFloat = 0
    @State private var isVerifying: Bool = false
    @State private var lockoutRemaining: Int? = nil
    @State private var lockoutTimer: Timer?

    @State private var showRecoveryPrompt = false
    @State private var recoveryCodeInput = ""
    @State private var showRecoveryError = false
    @State private var recoveryErrorMessage = ""
    @State private var showRecoveryPINReset = false

    @State private var isShowingForgotPINSheet: Bool = false
    @State private var forgotPINErrorMessage: String?

    private var biometricType: PINKeypadView.BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        default:
            return .none
        }
    }

    private var isLockedOut: Bool {
        lockoutRemaining != nil
    }

    private var statusText: String {
        if let remaining = lockoutRemaining {
            let minutes = remaining / 60
            let seconds = remaining % 60
            return String(format: "Try again in %d:%02d", minutes, seconds)
        }
        return "Enter your PIN"
    }

    init(authService: AuthService, onPresented: (() -> Void)? = nil) {
        self.authService = authService
        self.onPresented = onPresented
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(maxHeight: .infinity)

            // Lock icon
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.vaultTextPrimary)
                .padding(.bottom, 16)

            // Status text
            Text(statusText)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(isLockedOut ? Color.vaultDestructive : Color.vaultTextPrimary)
                .padding(.bottom, 32)

            // Dots - hidden during lockout
            if !isLockedOut {
                PINDotsView(
                    enteredCount: pin.count,
                    totalLength: pinLength,
                    state: dotState
                )
                .offset(x: shakeOffset)
                .padding(.bottom, 12)
            } else {
                Spacer().frame(height: 14 + 12)
            }

            if let forgotPINErrorMessage {
                Text(forgotPINErrorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.vaultDestructive)
                    .padding(.bottom, 8)
            } else {
                Text(" ")
                    .font(.caption)
                    .padding(.bottom, 8)
            }

            Spacer().frame(height: 44)

            // Keypad - disabled during lockout
            if !isLockedOut {
                PINKeypadView(
                    onDigitTap: { digit in
                        handleDigit(digit)
                    },
                    onDeleteTap: {
                        handleDelete()
                    },
                    onBiometricTap: biometricType != .none ? {
                        handleBiometric()
                    } : nil,
                    biometricType: biometricType
                )

                VStack(spacing: 12) {
                    Button("Use Recovery Code") {
                        forgotPINErrorMessage = nil
                        recoveryCodeInput = ""
                        showRecoveryPrompt = true
                    }
                    .font(.callout)
                    .disabled(isVerifying)

                    if biometricType != .none {
                        Button("Forgot PIN?") {
                            handleForgotPIN()
                        }
                        .font(.callout)
                        .foregroundStyle(Color.vaultAccent)
                        .disabled(isVerifying)
                    }
                }
                .padding(.top, 16)
            }

            Spacer()
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, Constants.standardPadding)
        .background(Color.vaultBackground.ignoresSafeArea())
        .onAppear {
            onPresented?()
            pinLength = authService.getPINLength()
            checkLockout()
            if !isLockedOut && authService.isBiometricsEnabled() {
                handleBiometric()
            }
        }
        .onDisappear {
            lockoutTimer?.invalidate()
            lockoutTimer = nil
        }
        .alert("Recovery Code", isPresented: $showRecoveryPrompt) {
            SecureField("Enter recovery code", text: $recoveryCodeInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Verify") {
                verifyRecoveryCode()
            }
        } message: {
            Text("Enter your one-time recovery code to reset your PIN.")
        }
        .alert("Recovery Code Error", isPresented: $showRecoveryError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recoveryErrorMessage)
        }
        .fullScreenCover(isPresented: $showRecoveryPINReset) {
            PINSetupView(
                authService: authService,
                mode: .recoveryReset(recoveryCode: recoveryCodeInput),
                onFinish: {
                    recoveryCodeInput = ""
                    pin = ""
                    dotState = .normal
                    checkLockout()
                }
            )
        }
        .fullScreenCover(isPresented: $isShowingForgotPINSheet) {
            NavigationStack {
                PINSetupView(
                    authService: authService,
                    createTitle: "Reset your PIN",
                    createSubtitle: "Use a new PIN to secure your vault",
                    confirmTitle: "Confirm new PIN",
                    confirmSubtitle: "Re-enter your new PIN",
                    onPINConfirmed: { newPIN in
                        try await authService.completeBiometricRecoveryReset(newPIN: newPIN)
                    },
                    onSuccess: {
                        isShowingForgotPINSheet = false
                        pin = ""
                        pinLength = authService.getPINLength()
                        forgotPINErrorMessage = nil
                    },
                    showsCloseButton: true
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: - Input Handling

    private func handleDigit(_ digit: String) {
        guard !isVerifying, pin.count < pinLength else { return }

        Haptics.pinDigitTap()
        pin += digit
        dotState = .normal

        if pin.count == pinLength {
            verify()
        }
    }

    private func handleDelete() {
        guard !pin.isEmpty, !isVerifying else { return }
        pin.removeLast()
        dotState = .normal
    }

    private func handleBiometric() {
        guard !isVerifying else { return }
        Task {
            _ = await authService.authenticateWithBiometrics()
        }
    }

    private func handleForgotPIN() {
        guard !isVerifying else { return }
        guard biometricType != .none else {
            forgotPINErrorMessage = "Biometric authentication is not available on this device."
            return
        }

        forgotPINErrorMessage = nil
        Task {
            let success = await authService.beginBiometricRecoveryReset()
            if success {
                isShowingForgotPINSheet = true
            } else {
                forgotPINErrorMessage = "Biometric verification failed."
            }
        }
    }

    // MARK: - Verification

    private func verify() {
        guard !isVerifying else { return }
        isVerifying = true

        Task {
            let result = await authService.verifyPIN(pin)

            switch result {
            case .success, .decoy:
                Haptics.pinCorrect()
                dotState = .success

            case .failure:
                Haptics.pinWrong()
                dotState = .error
                shakeAnimation()
                try? await Task.sleep(for: .seconds(Constants.pinShakeDuration))
                pin = ""
                dotState = .normal
                checkLockout()

            case .locked:
                Haptics.pinWrong()
                dotState = .error
                shakeAnimation()
                try? await Task.sleep(for: .seconds(Constants.pinShakeDuration))
                pin = ""
                dotState = .normal
                startLockoutTimer()
            }

            isVerifying = false
        }
    }

    private func verifyRecoveryCode() {
        let trimmedCode = recoveryCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            recoveryErrorMessage = "Please enter a recovery code."
            showRecoveryError = true
            return
        }

        recoveryCodeInput = trimmedCode
        Task {
            let isValid = await authService.verifyRecoveryCode(trimmedCode)
            if isValid {
                showRecoveryPINReset = true
            } else {
                recoveryErrorMessage = "Invalid, missing, or already-used recovery code."
                showRecoveryError = true
            }
        }
    }

    // MARK: - Lockout

    private func checkLockout() {
        lockoutRemaining = authService.getLockoutRemainingSeconds()
        if lockoutRemaining != nil {
            startLockoutTimer()
        }
    }

    private func startLockoutTimer() {
        lockoutRemaining = authService.getLockoutRemainingSeconds()
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                let remaining = authService.getLockoutRemainingSeconds()
                lockoutRemaining = remaining
                if remaining == nil {
                    lockoutTimer?.invalidate()
                    lockoutTimer = nil
                }
            }
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

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        // LockScreenView requires AuthService
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .padding(.bottom, 16)

            Text("Enter your PIN")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.bottom, 32)

            PINDotsView(enteredCount: 2, totalLength: 4, state: .normal)
                .padding(.bottom, 12)

            Text(" ")
                .font(.caption)
                .padding(.bottom, 8)

            Spacer().frame(height: 44)

            PINKeypadView(
                onDigitTap: { _ in },
                onDeleteTap: {},
                onBiometricTap: {},
                biometricType: .faceID
            )

            Spacer()
        }
        .padding(.horizontal, 16)
    }
}
