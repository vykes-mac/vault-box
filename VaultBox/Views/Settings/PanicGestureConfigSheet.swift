import SwiftUI

struct PanicGestureConfigSheet: View {
    let currentAction: PanicAction
    let onSave: (PanicAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAction: PanicAction

    init(currentAction: PanicAction, onSave: @escaping (PanicAction) -> Void) {
        self.currentAction = currentAction
        self.onSave = onSave
        self._selectedAction = State(initialValue: currentAction)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Explanation header
                VStack(spacing: 12) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.vaultAccent)

                    Text("Turn your phone face down to instantly lock VaultBox")
                        .font(.body)
                        .foregroundStyle(Color.vaultTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 24)

                // Action picker
                List {
                    Section("When triggered") {
                        ForEach(PanicAction.allCases) { action in
                            Button {
                                selectedAction = action
                            } label: {
                                HStack {
                                    Label(action.label, systemImage: action.systemImage)
                                        .foregroundStyle(Color.vaultTextPrimary)
                                    Spacer()
                                    if selectedAction == action {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.vaultAccent)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDisabled(true)
            }
            .background(Color.vaultBackground.ignoresSafeArea())
            .navigationTitle("Panic Gesture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onSave(selectedAction)
                        dismiss()
                    }
                }
            }
            .toolbarBackground(Color.vaultBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.vaultBackground)
    }
}
