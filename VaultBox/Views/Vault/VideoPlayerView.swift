import SwiftUI
import AVKit

// MARK: - VideoPlayerView

struct VideoPlayerView: View {
    let item: VaultItem
    let vaultService: VaultService

    @Environment(\.dismiss) private var dismiss
    @Environment(AppPrivacyShield.self) private var privacyShield

    @State private var player: AVPlayer?
    @State private var tempFileURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isMuted = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayerRepresentable(player: player)
                    .ignoresSafeArea()
                    .overlay(alignment: .topTrailing) {
                        muteToggleButton(player: player)
                            .padding(.top, 16)
                            .padding(.trailing, 16)
                    }
            } else if isLoading {
                ProgressView("Decrypting video…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                    Text(errorMessage)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }

            if privacyShield.isVisible {
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .zIndex(10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBar(hidden: true)
        .task {
            await loadVideo()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            dismiss()
        }
        .onDisappear {
            cleanupTempFile()
        }
    }

    // MARK: - Load & Cleanup

    private func loadVideo() async {
        do {
            try configureAudioSession()
            let url = try await vaultService.decryptVideoURL(for: item)
            tempFileURL = url
            let avPlayer = AVPlayer(url: url)
            avPlayer.isMuted = isMuted
            player = avPlayer
            isLoading = false
        } catch {
            errorMessage = "Unable to play this video."
            isLoading = false
        }
    }

    private func cleanupTempFile() {
        player?.pause()
        player = nil
        deactivateAudioSession()
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }

    private func muteToggleButton(player: AVPlayer) -> some View {
        Button {
            isMuted.toggle()
            player.isMuted = isMuted
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.55), in: Circle())
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback, options: [])
        try session.setActive(true)
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - AVPlayerViewController Wrapper

private struct VideoPlayerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        controller.entersFullScreenWhenPlaybackBegins = false
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }
}
