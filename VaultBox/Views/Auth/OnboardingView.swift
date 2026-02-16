import SwiftData
import SwiftUI

struct OnboardingView: View {
    let authService: AuthService

    @State private var currentPage = 0
    @State private var showPINSetup = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                valueHookPage
                    .tag(0)
                permissionsPrimerPage
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Page indicator dots
            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.accentColor : Color.accentColor.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 16)

            // CTA Button
            Button {
                if currentPage == 0 {
                    withAnimation {
                        currentPage = 1
                    }
                } else {
                    showPINSetup = true
                }
            } label: {
                Text(currentPage == 0 ? "Get Started" : "Create PIN")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, Constants.standardPadding)
            .padding(.bottom, 32)
        }
        .background {
            ZStack {
                Color.vaultBackground
                concentricArcs
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPINSetup) {
            PINSetupView(authService: authService)
        }
    }

    // MARK: - Value Hook (Screen 1)

    private var valueHookPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("shield")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            VStack(spacing: 12) {
                Text("Your photos.\nYour documents.\nYour rules.")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.vaultTextPrimary)

                Text("Encrypted the moment they\nenter VaultBox.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.vaultTextSecondary)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Constants.standardPadding)
    }

    // MARK: - Permissions Primer (Screen 2)

    private var permissionsPrimerPage: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Break-in protection needs\na few permissions")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.vaultTextPrimary)

                Text("After you create your PIN, we'll guide you through security permissions with clear context.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.vaultTextSecondary)
            }

            VStack(spacing: 20) {
                permissionRow(
                    icon: "bell.badge",
                    title: "Notifications",
                    subtitle: "Get instant break-in alerts"
                )
                permissionRow(
                    icon: "camera.fill",
                    title: "Camera",
                    subtitle: "Capture intruder photos on failed PIN attempts"
                )
                permissionRow(
                    icon: "location.fill",
                    title: "Location (Premium)",
                    subtitle: "Record GPS evidence when available"
                )
            }
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Constants.standardPadding)
    }

    // MARK: - Background Pattern

    private var concentricArcs: some View {
        let arcColor = Color.accentColor.opacity(0.07)
        let lineWidth: CGFloat = 2.5
        return ZStack {
            // Top-left arcs
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .stroke(arcColor, lineWidth: lineWidth)
                    .frame(width: 120 + CGFloat(i) * 80, height: 120 + CGFloat(i) * 80)
                    .offset(x: -80, y: -120)
            }
            // Bottom-right arcs
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .stroke(arcColor, lineWidth: lineWidth)
                    .frame(width: 120 + CGFloat(i) * 80, height: 120 + CGFloat(i) * 80)
                    .offset(x: 80, y: 120)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func permissionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.vaultTextPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.vaultTextSecondary)
            }

            Spacer()
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: AppSettings.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    context.insert(AppSettings())
    return OnboardingView(
        authService: AuthService(
            encryptionService: EncryptionService(),
            modelContext: context
        )
    )
    .modelContainer(container)
}
