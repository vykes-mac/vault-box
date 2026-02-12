import SwiftUI
import UIKit

enum PINSetupMode {
    case initialSetup
    case recoveryReset(recoveryCode: String)
}

struct PINSetupView: View {
    let authService: AuthService
    let mode: PINSetupMode
    let createTitle: String
    let createSubtitle: String
    let confirmTitle: String
    let confirmSubtitle: String
    let onPINConfirmed: ((String) async throws -> Void)?
    let onSuccess: (() -> Void)?
    let onFinish: (() -> Void)?
    let showsCloseButton: Bool

    @State private var pin: String = ""
    @State private var confirmPin: String = ""
    @State private var isConfirming = false
    @State private var dotState: PINDotsView.DotState = .normal
    @State private var shakeOffset: CGFloat = 0
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var generatedRecoveryCode: String?
    @State private var showRecoveryCodeSheet = false
    @State private var hasCopiedRecoveryCode = false

    @Environment(\.dismiss) private var dismiss

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

    init(
        authService: AuthService,
        mode: PINSetupMode = .initialSetup,
        createTitle: String? = nil,
        createSubtitle: String? = nil,
        confirmTitle: String? = nil,
        confirmSubtitle: String? = nil,
        onPINConfirmed: ((String) async throws -> Void)? = nil,
        onSuccess: (() -> Void)? = nil,
        onFinish: (() -> Void)? = nil,
        showsCloseButton: Bool = false
    ) {
        self.authService = authService
        self.mode = mode
        self.onPINConfirmed = onPINConfirmed
        self.onSuccess = onSuccess
        self.onFinish = onFinish
        self.showsCloseButton = showsCloseButton

        switch mode {
        case .initialSetup:
            self.createTitle = createTitle ?? "Create a PIN"
            self.createSubtitle = createSubtitle ?? "Choose a PIN to protect your vault"
            self.confirmTitle = confirmTitle ?? "Confirm your PIN"
            self.confirmSubtitle = confirmSubtitle ?? "Enter your PIN again"
        case .recoveryReset:
            self.createTitle = createTitle ?? "Reset your PIN"
            self.createSubtitle = createSubtitle ?? "Set a new PIN to unlock your vault"
            self.confirmTitle = confirmTitle ?? "Confirm New PIN"
            self.confirmSubtitle = confirmSubtitle ?? "Enter your new PIN again"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text(isConfirming ? confirmTitle : createTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.vaultTextPrimary)

                Text(isConfirming ? confirmSubtitle : createSubtitle)
                    .font(.callout)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 40)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Constants.standardPadding)
        .background(Color.vaultBackground.ignoresSafeArea())
        .sheet(isPresented: $showRecoveryCodeSheet) {
            recoveryCodeSheet
                .interactiveDismissDisabled()
        }
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                    }
                    .foregroundStyle(Color.vaultTextPrimary)
                    .accessibilityLabel("Close")
                }
            }
        }
        .toolbarBackground(Color.vaultBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var recoveryCodeSheet: some View {
        VStack(spacing: 18) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.vaultAccent)

            Text("Save Your Recovery Code")
                .font(.title3)
                .fontWeight(.bold)

            Text("You can use this one-time code to reset your PIN if you forget it. It won't be shown again.")
                .font(.callout)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)

            Text(generatedRecoveryCode ?? "")
                .font(.system(.title3, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.vaultSurface, in: RoundedRectangle(cornerRadius: 12))

            Button {
                copyRecoveryCodeToClipboard()
            } label: {
                Label(
                    hasCopiedRecoveryCode ? "Copied" : "Copy Code",
                    systemImage: hasCopiedRecoveryCode ? "checkmark.circle.fill" : "doc.on.doc"
                )
            }
            .buttonStyle(.bordered)
            .tint(hasCopiedRecoveryCode ? .green : Color.vaultAccent)

            Button("I Saved This Code") {
                completeFlow(shouldCompleteInitialSetup: true)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.vaultAccent)
        }
        .padding(Constants.standardPadding)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
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
                    if let onPINConfirmed {
                        try await onPINConfirmed(pin)
                        completeFlow(shouldCompleteInitialSetup: false)
                    } else {
                        switch mode {
                        case .initialSetup:
                            generatedRecoveryCode = try await authService.createPIN(pin)
                            hasCopiedRecoveryCode = false
                            showRecoveryCodeSheet = true
                        case .recoveryReset(let recoveryCode):
                            try await authService.resetPINUsingRecoveryCode(recoveryCode, newPIN: pin)
                            completeFlow(shouldCompleteInitialSetup: false)
                        }
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

    private func completeFlow(shouldCompleteInitialSetup: Bool) {
        do {
            if shouldCompleteInitialSetup {
                try authService.completeInitialSetup()
            }
            hasCopiedRecoveryCode = false
            showRecoveryCodeSheet = false
            isSubmitting = false
            onSuccess?()
            onFinish?()
            dismiss()
        } catch {
            dotState = .error
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }

    private func copyRecoveryCodeToClipboard() {
        guard let generatedRecoveryCode else { return }

        UIPasteboard.general.string = generatedRecoveryCode
        hasCopiedRecoveryCode = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            hasCopiedRecoveryCode = false
        }
    }
}

#Preview {
    Text("PINSetupView requires AuthService")
}
