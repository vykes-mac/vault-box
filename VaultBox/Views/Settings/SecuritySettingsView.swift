import SwiftUI
import SwiftData

enum SecuritySettingsMode {
    case changePIN
    case decoySetup
}

struct SecuritySettingsView: View {
    let authService: AuthService
    let mode: SecuritySettingsMode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseService.self) private var purchaseService

    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var step: Step = .enterCurrent
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var isProcessing = false
    @State private var showPaywall = false

    enum Step {
        case enterCurrent
        case enterNew
        case confirmNew
    }

    private var title: String {
        switch mode {
        case .changePIN:
            switch step {
            case .enterCurrent: "Change PIN"
            case .enterNew: "Change PIN"
            case .confirmNew: "Confirm New PIN"
            }
        case .decoySetup:
            switch step {
            case .enterCurrent: "Verify Identity"
            case .enterNew: "Set Decoy PIN"
            case .confirmNew: "Confirm Decoy PIN"
            }
        }
    }

    private var subtitle: String {
        switch step {
        case .enterCurrent:
            mode == .decoySetup
                ? "Enter your real PIN to verify your identity"
                : "Enter your current PIN"
        case .enterNew:
            mode == .decoySetup
                ? "Choose a decoy PIN (must differ from real PIN)"
                : "Enter your new PIN"
        case .confirmNew:
            mode == .decoySetup
                ? "Re-enter the decoy PIN to confirm"
                : "Confirm your new PIN"
        }
    }

    private var activePIN: Binding<String> {
        switch step {
        case .enterCurrent: $currentPIN
        case .enterNew: $newPIN
        case .confirmNew: $confirmPIN
        }
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // PIN dots
            HStack(spacing: 12) {
                ForEach(0..<max(Constants.pinMinLength, activePIN.wrappedValue.count + 1), id: \.self) { index in
                    Circle()
                        .fill(index < activePIN.wrappedValue.count ? Color.vaultTextPrimary : Color.clear)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.vaultTextSecondary, lineWidth: 1.5)
                        )
                }
            }
            .animation(.easeInOut(duration: 0.15), value: activePIN.wrappedValue.count)

            Spacer()

            // Keypad
            PINKeypadView(
                onDigitTap: { digit in
                    guard activePIN.wrappedValue.count < Constants.pinMaxLength else { return false }
                    activePIN.wrappedValue.append(digit)
                    return true
                },
                onDeleteTap: {
                    guard !activePIN.wrappedValue.isEmpty else { return false }
                    activePIN.wrappedValue.removeLast()
                    return true
                },
                onBiometricTap: nil,
                biometricType: .none
            )

            // Continue button
            if activePIN.wrappedValue.count >= Constants.pinMinLength {
                Button {
                    handleContinue()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.vaultAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius))
                }
                .padding(.horizontal, Constants.standardPadding)
                .disabled(isProcessing)
            }

            Spacer().frame(height: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vaultBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .toolbarBackground(Color.vaultBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            VaultBoxPaywallView()
        }
    }

    private func handleContinue() {
        if mode == .decoySetup, purchaseService.isPremiumRequired(for: .decoyVault) {
            showPaywall = true
            return
        }
        switch step {
        case .enterCurrent:
            verifyCurrent()
        case .enterNew:
            if activePIN.wrappedValue.count >= Constants.pinMinLength {
                step = .confirmNew
            }
        case .confirmNew:
            confirmAndSave()
        }
    }

    private func verifyCurrent() {
        isProcessing = true
        Task {
            let result = await authService.verifyPIN(currentPIN)
            isProcessing = false

            switch result {
            case .success, .decoy:
                Haptics.pinCorrect()
                step = .enterNew
            case .failure:
                Haptics.pinWrong()
                errorMessage = "Incorrect PIN. Please try again."
                showError = true
                currentPIN = ""
            case .locked:
                Haptics.pinWrong()
                errorMessage = "Too many attempts. Please wait."
                showError = true
                currentPIN = ""
            }
        }
    }

    private func confirmAndSave() {
        if mode == .decoySetup, purchaseService.isPremiumRequired(for: .decoyVault) {
            showPaywall = true
            return
        }

        guard newPIN == confirmPIN else {
            Haptics.pinWrong()
            errorMessage = "PINs don't match. Try again."
            showError = true
            confirmPIN = ""
            step = .enterNew
            newPIN = ""
            return
        }

        isProcessing = true
        Task {
            do {
                switch mode {
                case .changePIN:
                    try await authService.changePIN(old: currentPIN, new: newPIN)
                case .decoySetup:
                    try await authService.setupDecoyPIN(newPIN)
                }
                Haptics.pinCorrect()
                dismiss()
            } catch {
                Haptics.pinWrong()
                errorMessage = error.localizedDescription
                showError = true
                isProcessing = false
            }
        }
    }
}
