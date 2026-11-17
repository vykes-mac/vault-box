import SwiftUI
import UIKit

/// The question asked before Apple's rating sheet.
///
/// App Store Review Guideline 5.6.1: this is a plain yes/no question. It must never
/// contain stars, a score, or anything that looks like a rating control. Only Apple's
/// own sheet collects ratings, and only after a "Yes".
///
/// "Not really" never leads to the App Store. It turns into an offer to email support.
struct RatingPromptView: View {
    let onYes: () -> Void
    let onNotReally: () -> Void
    let onEmailSupport: () -> Void
    let onNotNow: () -> Void

    @Environment(\.openURL) private var openURL

    @State private var step: Step = .question
    @State private var contentHeight: CGFloat = 380
    @State private var showMailFallback = false

    private enum Step {
        case question
        case feedback
    }

    var body: some View {
        content
            .padding(.horizontal, Constants.standardPadding)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in contentHeight = height }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.vaultBackground.ignoresSafeArea())
            .presentationDetents([.height(contentHeight)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .animation(.snappy, value: step)
            .alert("Couldn't Open Mail", isPresented: $showMailFallback) {
                Button("Copy Address") {
                    UIPasteboard.general.string = Constants.supportEmail
                    onNotNow()
                }
                Button("OK", role: .cancel) { onNotNow() }
            } message: {
                Text("Email us at \(Constants.supportEmail).")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .question:
            questionStep
                .transition(.opacity)
        case .feedback:
            feedbackStep
                .transition(.opacity)
        }
    }

    // MARK: - Question

    private var questionStep: some View {
        VStack(spacing: 22) {
            header(
                systemImage: "lock.shield.fill",
                title: "Enjoying VaultBox?",
                message: "Your answer helps us decide what to improve next."
            )

            VStack(spacing: 12) {
                primaryButton("Yes, I love it", action: onYes)

                Button {
                    onNotReally()
                    step = .feedback
                } label: {
                    Text("Not really")
                        .font(.headline)
                        .foregroundStyle(Color.vaultTextPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.vaultSurface, in: Capsule())
                }

                notNowButton
            }
        }
    }

    // MARK: - Feedback

    private var feedbackStep: some View {
        VStack(spacing: 22) {
            header(
                systemImage: "envelope.fill",
                title: "Sorry to hear that",
                message: "Tell us what isn't working. We read every message and use it to fix VaultBox."
            )

            VStack(spacing: 12) {
                primaryButton("Email Support") {
                    openSupportEmail()
                }
                notNowButton
            }
        }
    }

    // MARK: - Pieces

    private func header(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.vaultAccent.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.vaultAccent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(Color.vaultTextPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func primaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.vaultAccent, in: Capsule())
        }
    }

    private var notNowButton: some View {
        Button(action: onNotNow) {
            Text("Not now")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.vaultTextSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }

    // MARK: - Support Email

    /// The same mailbox as Settings → Contact Support, with a subject that marks it as
    /// coming from the rating question.
    private func openSupportEmail() {
        guard let url = Self.supportEmailURL() else {
            showMailFallback = true
            return
        }
        openURL(url) { accepted in
            if accepted {
                onEmailSupport()
            } else {
                showMailFallback = true
            }
        }
    }

    static func supportEmailURL() -> URL? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Constants.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "VaultBox Feedback"),
            URLQueryItem(name: "body", value: "\n\n---\nVaultBox \(version) (\(build))\niOS \(UIDevice.current.systemVersion)")
        ]
        return components.url
    }
}
