import SwiftUI

struct ShareExtensionView: View {
    let model: ShareExtensionModel

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .background(Color(.systemBackground))
                .navigationTitle("VaultBox")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if !isBusy {
                            Button("Cancel") { model.cancel() }
                        }
                    }
                }
        }
        .onAppear { model.start() }
    }

    private var isBusy: Bool {
        switch model.phase {
        case .saving, .finished: true
        default: false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .unavailable:
            message(
                symbol: "lock.shield",
                title: String(localized: "Set up VaultBox first"),
                detail: String(localized: "Open VaultBox, create your PIN and unlock it once, then try sharing again.")
            )
        case .locked:
            unlockView
        case .lockedOut(let until):
            message(
                symbol: "lock.fill",
                title: String(localized: "Too many attempts"),
                detail: String(localized: "Try again \(until.formatted(.relative(presentation: .named))).")
            )
        case .saving(let completed, let total):
            VStack(spacing: 16) {
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
                Text("Encrypting \(min(completed + 1, total)) of \(total)…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .finished(let saved, let skipped):
            message(
                symbol: saved > 0 ? "checkmark.shield.fill" : "exclamationmark.triangle",
                title: saved > 0
                    ? String(localized: "Encrypted \(saved) items")
                    : String(localized: "Nothing was saved"),
                detail: finishedDetail(saved: saved, skipped: skipped)
            )
        }
    }

    private func finishedDetail(saved: Int, skipped: Int) -> String {
        var lines: [String] = []
        if saved > 0 {
            lines.append(String(localized: "They'll appear in your vault next time you unlock VaultBox."))
        }
        if skipped > 0 {
            lines.append(String(localized: "\(skipped) items couldn't be added. Videos over 250 MB and documents over 100 MB aren't supported."))
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Unlock

    private var unlockView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                Text("Enter your VaultBox PIN")
                    .font(.headline)
                Text("to add \(model.itemCount) items to your vault")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                ForEach(0..<model.pinLength, id: \.self) { index in
                    Circle()
                        .fill(index < model.enteredPIN.count ? Color.primary : Color.clear)
                        .overlay(Circle().stroke(model.showsPINError ? Color.red : Color.primary, lineWidth: 1.5))
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityLabel(Text("\(model.enteredPIN.count) of \(model.pinLength) digits entered"))

            Text(model.showsPINError ? String(localized: "Incorrect PIN") : " ")
                .font(.footnote)
                .foregroundStyle(.red)

            keypad

            if model.showsDocumentPremiumNote {
                Text("Documents import with VaultBox Premium. They'll wait safely until you upgrade.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
    }

    private var keypad: some View {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
        return VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(row, id: \.self) { digit in
                        digitButton(digit)
                    }
                }
            }
            HStack(spacing: 24) {
                biometricButton
                digitButton("0")
                Button {
                    model.deleteDigit()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.title2)
                        .frame(width: 72, height: 72)
                }
                .foregroundStyle(.primary)
                .accessibilityLabel(Text("Delete"))
            }
        }
    }

    private func digitButton(_ digit: String) -> some View {
        Button {
            model.appendDigit(digit)
        } label: {
            Text(digit)
                .font(.title)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color(.secondarySystemBackground)))
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var biometricButton: some View {
        if let kind = model.biometricKind {
            Button {
                Task { await model.authenticateWithBiometrics() }
            } label: {
                Image(systemName: symbol(for: kind))
                    .font(.title2)
                    .frame(width: 72, height: 72)
            }
            .foregroundStyle(.primary)
            .accessibilityLabel(Text("Unlock with biometrics"))
        } else {
            Color.clear.frame(width: 72, height: 72)
        }
    }

    private func symbol(for kind: ShareExtensionModel.BiometricKind) -> String {
        switch kind {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        }
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
