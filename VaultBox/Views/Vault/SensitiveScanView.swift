import SwiftUI

/// Manual, on-device scan of the camera roll that surfaces photos which look
/// sensitive (IDs, cards, financial info, credential screenshots, codes) and
/// offers to move them into the vault.
struct SensitiveScanView: View {
    let vaultService: VaultService
    var onClose: () -> Void

    @State private var viewModel: SensitiveScanViewModel
    @State private var deleteOriginals = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    init(vaultService: VaultService, onClose: @escaping () -> Void) {
        self.vaultService = vaultService
        self.onClose = onClose
        _viewModel = State(initialValue: SensitiveScanViewModel(vaultService: vaultService))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Find Sensitive Photos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { onClose() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            introView
        case .scanning:
            scanningView
        case .results:
            resultsView
        case .importing:
            ProgressView("Moving to vault…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .finished(let count):
            finishedView(count: count)
        case .denied:
            deniedView
        case .error(let message):
            messageView(systemImage: "exclamationmark.triangle", title: "Something went wrong", subtitle: message)
        }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(Color.vaultAccent)
            VStack(spacing: 12) {
                Text("Scan for Sensitive Photos")
                    .font(.title2.bold())
                    .foregroundStyle(Color.vaultTextPrimary)
                Text("VaultBox can look through your recent photos — entirely on this device — to find IDs, cards, and screenshots of passwords or financial info that you may want to lock away. Nothing is ever uploaded.")
                    .font(.body)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                viewModel.startScan()
            } label: {
                Text("Scan My Photos")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.vaultAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius))
            }
        }
        .padding()
    }

    // MARK: - Scanning

    private var scanningView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView(value: viewModel.progressFraction)
                .progressViewStyle(.linear)
                .tint(Color.vaultAccent)
                .padding(.horizontal, 40)
            Text("Scanning \(viewModel.scannedCount) of \(viewModel.totalCount)…")
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextSecondary)
            Text("This runs on your device. Your photos never leave it.")
                .font(.caption)
                .foregroundStyle(Color.vaultTextSecondary)
            Spacer()
        }
        .padding()
    }

    // MARK: - Results

    private var resultsView: some View {
        Group {
            if viewModel.candidates.isEmpty {
                messageView(
                    systemImage: "checkmark.shield",
                    title: "Nothing Sensitive Found",
                    subtitle: "We didn't spot any obviously sensitive photos in your recent camera roll."
                )
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(viewModel.candidates) { candidate in
                                candidateCell(candidate)
                            }
                        }
                        .padding()
                    }
                    footerBar
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(viewModel.allSelected ? "Deselect All" : "Select All") {
                    viewModel.toggleSelectAll()
                }
                .disabled(viewModel.candidates.isEmpty)
            }
        }
    }

    private func candidateCell(_ candidate: SensitiveScanCandidate) -> some View {
        let isSelected = viewModel.selectedIDs.contains(candidate.id)
        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = viewModel.thumbnail(for: candidate.id) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.vaultSurfaceSecondary)
                            .overlay(ProgressView())
                    }
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.vaultAccent : Color.clear, lineWidth: 3)
                )

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.vaultAccent : .white)
                    .background(Circle().fill(.black.opacity(0.3)))
                    .padding(6)
            }

            if let reason = candidate.reasons.first {
                Text(reason.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.toggle(candidate.id)
        }
        .onAppear {
            viewModel.loadThumbnail(for: candidate.id, size: 100)
        }
    }

    private var footerBar: some View {
        VStack(spacing: 12) {
            Toggle("Delete originals from Photos after moving", isOn: $deleteOriginals)
                .font(.subheadline)
                .tint(Color.vaultAccent)

            Button {
                viewModel.moveSelectedToVault(deleteOriginals: deleteOriginals) {}
            } label: {
                Text(viewModel.selectedIDs.isEmpty
                     ? "Select Photos to Move"
                     : "Move \(viewModel.selectedIDs.count) to Vault")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.selectedIDs.isEmpty ? Color.vaultSurfaceSecondary : Color.vaultAccent)
                    .foregroundStyle(viewModel.selectedIDs.isEmpty ? Color.vaultTextSecondary : .white)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius))
            }
            .disabled(viewModel.selectedIDs.isEmpty)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Finished

    private func finishedView(count: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.vaultSuccess)
            Text(count == 1 ? "1 photo moved to your vault" : "\(count) photos moved to your vault")
                .font(.title3.bold())
                .foregroundStyle(Color.vaultTextPrimary)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                onClose()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.vaultAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius))
            }
        }
        .padding()
    }

    // MARK: - Denied / Message

    private var deniedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.slash")
                .font(.system(size: 56))
                .foregroundStyle(Color.vaultTextSecondary)
            Text("Photos Access Needed")
                .font(.title3.bold())
                .foregroundStyle(Color.vaultTextPrimary)
            Text("To scan for sensitive photos, allow VaultBox to access your photo library in Settings.")
                .font(.body)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding()
    }

    private func messageView(systemImage: String, title: String, subtitle: String) -> some View {
        EmptyStateView(systemImage: systemImage, title: title, subtitle: subtitle)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
