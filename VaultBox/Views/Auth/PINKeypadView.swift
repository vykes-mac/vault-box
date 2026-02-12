import SwiftUI

struct PINKeypadView: View {
    let onDigitTap: (String) -> Bool
    let onDeleteTap: () -> Bool
    let onBiometricTap: (() -> Void)?
    let biometricType: BiometricType

    enum BiometricType {
        case faceID
        case touchID
        case none
    }

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private let keys: [[KeypadKey]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.biometric, .digit("0"), .delete]
    ]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(row, id: \.self) { key in
                        keyButton(for: key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(for key: KeypadKey) -> some View {
        switch key {
        case .digit(let digit):
            Button {
                if onDigitTap(digit) {
                    Haptics.pinDigitTap()
                }
            } label: {
                Text(digit)
                    .font(.title)
                    .fontWeight(.medium)
                    .frame(width: Constants.keypadButtonSize, height: Constants.keypadButtonSize)
                    .background(Color.vaultSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.vaultTextPrimary)

        case .biometric:
            if let onBiometricTap, biometricType != .none {
                Button {
                    onBiometricTap()
                } label: {
                    Image(systemName: biometricType == .faceID ? "faceid" : "touchid")
                        .font(.title2)
                        .frame(width: Constants.keypadButtonSize, height: Constants.keypadButtonSize)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.vaultAccent)
            } else {
                Color.clear
                    .frame(width: Constants.keypadButtonSize, height: Constants.keypadButtonSize)
            }

        case .delete:
            Button {
                if onDeleteTap() {
                    Haptics.pinDeleteTap()
                }
            } label: {
                Image(systemName: "delete.backward")
                    .font(.title2)
                    .frame(width: Constants.keypadButtonSize, height: Constants.keypadButtonSize)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.vaultTextPrimary)
        }
    }
}

private enum KeypadKey: Hashable {
    case digit(String)
    case biometric
    case delete
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        PINKeypadView(
            onDigitTap: { _ in true },
            onDeleteTap: { true },
            onBiometricTap: {},
            biometricType: .faceID
        )
    }
}
