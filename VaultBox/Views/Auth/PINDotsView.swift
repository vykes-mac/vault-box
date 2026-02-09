import SwiftUI

struct PINDotsView: View {
    let enteredCount: Int
    let totalLength: Int
    let state: DotState

    enum DotState {
        case normal
        case success
        case error
    }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<totalLength, id: \.self) { index in
                Circle()
                    .fill(dotColor(at: index))
                    .frame(width: 14, height: 14)
            }
        }
    }

    private func dotColor(at index: Int) -> Color {
        switch state {
        case .success:
            return .vaultSuccess
        case .error:
            return index < enteredCount ? .vaultDestructive : dotBaseColor(at: index)
        case .normal:
            return dotBaseColor(at: index)
        }
    }

    private func dotBaseColor(at index: Int) -> Color {
        index < enteredCount ? .vaultTextPrimary : .vaultTextSecondary.opacity(0.3)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 30) {
            PINDotsView(enteredCount: 0, totalLength: 4, state: .normal)
            PINDotsView(enteredCount: 2, totalLength: 4, state: .normal)
            PINDotsView(enteredCount: 4, totalLength: 4, state: .success)
            PINDotsView(enteredCount: 4, totalLength: 4, state: .error)
        }
    }
}
