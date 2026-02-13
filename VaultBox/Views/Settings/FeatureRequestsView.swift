import SwiftUI
import CloudKit

@MainActor
@Observable
final class FeatureRequestsViewModel {
    private let service: FeatureBoardService

    var features: [FeatureRequestDTO] = []
    var myVotes: [String: FeatureVoteValue] = [:]
    var submitTitle = ""
    var submitDetails = ""
    var isLoading = false
    var isSubmitting = false
    var votingFeatureIDs: Set<String> = []
    var errorMessage: String?
    var showError = false
    var iCloudAvailable = true

    var canInteract: Bool { iCloudAvailable }

    init(service: FeatureBoardService = FeatureBoardService()) {
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let status = await service.getICloudAccountStatus()
        iCloudAvailable = status == .available

        do {
            try await refreshBoardState()
        } catch {
            presentNetworkSafe(error)
        }
    }

    func submitFeature() async {
        guard canInteract else {
            present("Sign in to iCloud to submit feature requests.")
            return
        }
        guard !isSubmitting else { return }
        guard !submitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            present(FeatureBoardError.emptyTitle)
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            _ = try await service.submitFeature(title: submitTitle, details: submitDetails)
            submitTitle = ""
            submitDetails = ""
            try await refreshBoardState()
        } catch {
            presentNetworkSafe(error)
        }
    }

    func toggleVote(featureID: String, vote: FeatureVoteValue) async {
        guard canInteract else {
            present("Sign in to iCloud to vote on features.")
            return
        }
        guard !votingFeatureIDs.contains(featureID) else { return }
        votingFeatureIDs.insert(featureID)
        defer { votingFeatureIDs.remove(featureID) }

        do {
            if myVotes[featureID] == vote {
                try await service.removeVote(featureID: featureID)
            } else {
                try await service.setVote(featureID: featureID, vote: vote)
            }
            try await refreshBoardState()
        } catch {
            presentNetworkSafe(error)
        }
    }

    private func refreshBoardState() async throws {
        let loadedFeatures = try await service.listFeatures(limit: 100)
        let voteMap: [String: FeatureVoteValue]
        if iCloudAvailable {
            voteMap = try await service.myVotes(featureIDs: loadedFeatures.map(\.id))
        } else {
            voteMap = [:]
        }
        features = loadedFeatures
        myVotes = voteMap
    }

    private func presentNetworkSafe(_ error: Error) {
        if let ckError = error as? CKError, ckError.code == .networkUnavailable || ckError.code == .networkFailure {
            if !features.isEmpty { return }
        }
        errorMessage = error.localizedDescription
        showError = true
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    private func present(_ message: String) {
        errorMessage = message
        showError = true
    }
}

struct FeatureRequestsView: View {
    @State private var viewModel = FeatureRequestsViewModel()

    var body: some View {
        List {
            if !viewModel.iCloudAvailable {
                iCloudBanner
            }
            submitSection
            boardSection
        }
        .navigationTitle("Feature Requests")
        .task {
            if viewModel.features.isEmpty {
                await viewModel.load()
            }
        }
        .refreshable {
            await viewModel.load()
        }
        .alert("Feature Board", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
        }
    }

    // MARK: - iCloud Status Banner

    private var iCloudBanner: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("iCloud Sign-In Required")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Sign in to iCloud in Settings to submit requests and vote.")
                        .font(.caption)
                        .foregroundStyle(Color.vaultTextSecondary)
                }
            } icon: {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(Color.vaultDestructive)
            }
        }
    }

    // MARK: - Submit Section

    private var submitSection: some View {
        Section("Request a Feature") {
            TextField("Feature title", text: $viewModel.submitTitle)
                .textInputAutocapitalization(.sentences)
                .disabled(!viewModel.canInteract)

            TextField("Why this matters (optional)", text: $viewModel.submitDetails, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .disabled(!viewModel.canInteract)

            Button {
                Task {
                    await viewModel.submitFeature()
                }
            } label: {
                if viewModel.isSubmitting {
                    ProgressView()
                } else {
                    Label("Submit Request", systemImage: "paperplane")
                }
            }
            .disabled(
                !viewModel.canInteract ||
                viewModel.isSubmitting ||
                viewModel.submitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    // MARK: - Board Section

    private var boardSection: some View {
        Section("Open Requests") {
            if viewModel.isLoading && viewModel.features.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if viewModel.features.isEmpty {
                ContentUnavailableView {
                    Label("No Requests Yet", systemImage: "lightbulb")
                } description: {
                    Text("Be the first to submit a feature request.")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.features) { feature in
                    FeatureRequestRow(
                        feature: feature,
                        currentVote: viewModel.myVotes[feature.id],
                        isVoting: viewModel.votingFeatureIDs.contains(feature.id),
                        canVote: viewModel.canInteract,
                        onUpVote: {
                            Task {
                                await viewModel.toggleVote(featureID: feature.id, vote: .up)
                            }
                        },
                        onDownVote: {
                            Task {
                                await viewModel.toggleVote(featureID: feature.id, vote: .down)
                            }
                        }
                    )
                }
            }
        }
    }
}

private struct FeatureRequestRow: View {
    let feature: FeatureRequestDTO
    let currentVote: FeatureVoteValue?
    let isVoting: Bool
    let canVote: Bool
    let onUpVote: () -> Void
    let onDownVote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(feature.title)
                .font(.headline)
                .foregroundStyle(Color.vaultTextPrimary)

            if !feature.details.isEmpty {
                Text(feature.details)
                    .font(.subheadline)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .lineLimit(3)
            }

            HStack {
                Label("\(feature.score)", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(Color.vaultTextSecondary)

                Text("·")
                    .font(.caption)
                    .foregroundStyle(Color.vaultTextSecondary)

                Text(feature.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(Color.vaultTextSecondary)

                Spacer()

                voteButton(
                    title: "\(feature.upVotes)",
                    imageName: "hand.thumbsup",
                    isSelected: currentVote == .up,
                    action: onUpVote
                )

                voteButton(
                    title: "\(feature.downVotes)",
                    imageName: "hand.thumbsdown",
                    isSelected: currentVote == .down,
                    action: onDownVote
                )
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .topTrailing) {
            if isVoting {
                ProgressView()
                    .scaleEffect(0.75)
            }
        }
    }

    private func voteButton(
        title: String,
        imageName: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "\(imageName).fill" : imageName)
                .labelStyle(.titleAndIcon)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isSelected ? Color.vaultAccent : Color.vaultTextSecondary)
        .disabled(!canVote || isVoting)
    }
}
