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
        case .changePIN: "Change PIN"
        case .decoySetup: "Set Decoy PIN"
        }
    }

    private var subtitle: String {
        switch step {
        case .enterCurrent:
            "Enter your current PIN"
        case .enterNew:
            mode == .decoySetup
                ? "Choose a decoy PIN (must differ from real PIN)"
                : "Enter your new PIN"
        case .confirmNew:
            "Confirm your new PIN"
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
                    guard activePIN.wrappedValue.count < Constants.pinMaxLength else { return }
                    activePIN.wrappedValue.append(digit)
                },
                onDeleteTap: {
                    guard !activePIN.wrappedValue.isEmpty else { return }
                    activePIN.wrappedValue.removeLast()
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
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
                step = .enterNew
            case .failure:
                errorMessage = "Incorrect PIN. Please try again."
                showError = true
                currentPIN = ""
            case .locked:
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
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isProcessing = false
            }
        }
    }
}
