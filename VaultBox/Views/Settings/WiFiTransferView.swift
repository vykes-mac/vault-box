import SwiftUI
import CoreImage.CIFilterBuiltins

struct WiFiTransferView: View {
    let vaultService: VaultService
    let authService: AuthService

    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseService.self) private var purchaseService

    @State private var viewModel: WiFiTransferViewModel?
    @State private var showPaywall = false

    var body: some View {
        List {
            if purchaseService.isPremium {
                if let vm = viewModel {
                    if vm.isRunning {
                        runningSection(vm)
                        statusSection(vm)
                    } else {
                        startSection(vm)
                        howItWorksSection
                    }
                }
            } else {
                premiumRequiredSection
            }
        }
        .navigationTitle("Wi-Fi Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel == nil {
                let purchaseService = self.purchaseService
                viewModel = WiFiTransferViewModel(
                    vaultService: vaultService,
                    authService: authService,
                    modelContext: modelContext,
                    hasPremiumAccess: { purchaseService.isPremium }
                )
            }
            if !purchaseService.isPremium {
                viewModel?.stopServer()
            }
        }
        .onChange(of: purchaseService.isPremium) { _, isPremium in
            if !isPremium {
                viewModel?.stopServer()
            }
        }
        .onDisappear {
            viewModel?.stopServer()
        }
        .sheet(isPresented: Binding(
            get: { viewModel?.showPINReEntry ?? false },
            set: { viewModel?.showPINReEntry = $0 }
        )) {
            PINReEntryView(authService: authService) {
                viewModel?.onPINVerified()
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            VaultBoxPaywallView()
        }
    }

    private var premiumRequiredSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Premium Required", systemImage: "lock.fill")
                    .font(.headline)
                Text("Wi-Fi Transfer is available on Premium.")
                    .font(.subheadline)
                    .foregroundStyle(Color.vaultTextSecondary)
                Button {
                    showPaywall = true
                } label: {
                    Label("Upgrade to Premium", systemImage: "star.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Start Section

    private func startSection(_ vm: WiFiTransferViewModel) -> some View {
        Section {
            Button {
                vm.requestStart()
            } label: {
                HStack {
                    Label("Start Transfer Server", systemImage: "play.fill")
                    Spacer()
                    Image(systemName: "wifi")
                        .foregroundStyle(Color.vaultAccent)
                }
            }
        } footer: {
            Text("Start a local server to transfer files between your device and a computer on the same Wi-Fi network.")
        }
    }

    // MARK: - Running Section

    private func runningSection(_ vm: WiFiTransferViewModel) -> some View {
        Section {
            VStack(alignment: .center, spacing: 16) {
                Text("Server Running")
                    .font(.headline)
                    .foregroundStyle(Color.vaultSuccess)

                if !vm.serverURL.isEmpty {
                    Text(vm.serverURL)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }

                if let qrImage = generateQRCode(from: vm.serverURL) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .padding(8)
                        .background(Color.white)
                        .cornerRadius(Constants.cardCornerRadius)
                }

                Text("Open this URL in a browser on your computer")
                    .font(.caption)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Button(role: .destructive) {
                vm.stopServer()
            } label: {
                HStack {
                    Label("Stop Server", systemImage: "stop.fill")
                    Spacer()
                }
            }
        } footer: {
            Text("Files are decrypted for download and encrypted on upload. The server is only accessible on your local network.")
        }
    }

    // MARK: - Status Section

    private func statusSection(_ vm: WiFiTransferViewModel) -> some View {
        Section("Status") {
            LabeledContent("Active Browsers", value: "\(vm.connectedDeviceCount)")

            LabeledContent("Auto-stop in") {
                Text(formatTime(vm.timeoutSecondsRemaining))
                    .foregroundStyle(vm.timeoutSecondsRemaining < 60 ? Color.vaultDestructive : Color.vaultTextSecondary)
            }
        }
    }

    // MARK: - How It Works

    private var howItWorksSection: some View {
        Section("How It Works") {
            instructionRow(number: "1", text: "Make sure your iPhone and computer are on the same Wi-Fi network")
            instructionRow(number: "2", text: "Tap \"Start Transfer Server\" and enter your PIN")
            instructionRow(number: "3", text: "Open the URL shown on your computer's browser")
            instructionRow(number: "4", text: "Upload or download files through the browser")
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 22, height: 22)
                .background(Color.vaultAccent)
                .foregroundStyle(.white)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextSecondary)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func generateQRCode(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scale = 256.0 / outputImage.extent.size.width
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
