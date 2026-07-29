import SwiftUI

// MARK: - Hook

/// Opens on the loss, not the feature. The user has to feel the exposure before any
/// benefit claim will land, so the whole screen is one concrete, familiar moment.
struct OnboardingHookStep: View {
    @State private var isLocked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 0)

            PhoneExposureIllustration(isLocked: isLocked)
                .frame(maxWidth: .infinity)
                .frame(height: 230)

            OnboardingHeadline(
                eyebrow: String(localized: "The uncomfortable part"),
                title: String(localized: "Anyone holding your phone is one swipe from everything."),
                subtitle: String(localized: """
                    You hand it over to show one photo. Recents, screenshots, \
                    documents — it's all one swipe away, and you're standing right there.
                    """)
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Constants.standardPadding)
        .task {
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                isLocked = true
            }
        }
    }
}

// MARK: - Phone Illustration

/// A phone full of thumbnails that gets sealed behind a shield a beat after the screen
/// appears. Showing the problem resolve itself previews the relief we're selling.
struct PhoneExposureIllustration: View {
    let isLocked: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 3)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.vaultSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.vaultTextSecondary.opacity(0.25), lineWidth: 2)
                }
                .frame(width: 132, height: 224)
                .overlay {
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(0..<12, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(thumbnailColor(index))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                    .padding(12)
                    .blur(radius: isLocked ? 7 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 62))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.vaultAccent)
                .shadow(color: Color.vaultAccent.opacity(0.5), radius: 18, y: 6)
                .scaleEffect(isLocked ? 1 : 0.3)
                .opacity(isLocked ? 1 : 0)
        }
    }

    private func thumbnailColor(_ index: Int) -> Color {
        let palette: [Color] = [
            Color.vaultAccent.opacity(0.35),
            Color.vaultTextSecondary.opacity(0.35),
            Color.vaultPremium.opacity(0.35),
            Color.vaultAccent.opacity(0.2)
        ]
        return palette[index % palette.count]
    }
}

// MARK: - Proof

/// Recognition, not statistics. Three moments the user has actually lived through do
/// more work than a number they can't verify — and every "yes, that's me" makes the
/// next question feel like it's about them.
struct OnboardingProofStep: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                OnboardingHeadline(
                    eyebrow: String(localized: "You're not being paranoid"),
                    title: String(localized: "It's never the stranger. It's the person next to you."),
                    subtitle: String(localized: "Sound familiar?")
                )

                VStack(spacing: 12) {
                    scenarioCard(
                        icon: "hand.point.up.left.fill",
                        text: String(localized: "\"Let me see that photo\" — and they keep scrolling.")
                    )
                    scenarioCard(
                        icon: "figure.child",
                        text: String(localized: "You hand your phone to a kid and open Photos by muscle memory.")
                    )
                    scenarioCard(
                        icon: "iphone.slash",
                        text: String(localized: "Your phone goes missing and your stomach drops.")
                    )
                }

                OnboardingReviewCard(
                    quote: OnboardingSocialProof.featuredReview.quote,
                    author: OnboardingSocialProof.featuredReview.author
                )
            }
            .padding(.horizontal, Constants.standardPadding)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func scenarioCard(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.vaultAccent)
                .frame(width: 26)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.vaultSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Trust

/// Authority step. Right before we ask for a PIN, remove the "why should I trust an app
/// with this?" objection by explaining what we deliberately cannot do.
struct OnboardingTrustStep: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Self-contained dark hero card: carries its own background so it reads
                // the same in light and dark appearance.
                Image("vault-hero")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 168)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityHidden(true)

                OnboardingHeadline(
                    eyebrow: String(localized: "Why this is safe"),
                    title: String(localized: "Even we can't open your vault."),
                    subtitle: String(localized: """
                        There's no account, no upload, and no back door. \
                        Your key lives in this phone's keychain and nowhere else.
                        """)
                )

                VStack(spacing: 16) {
                    OnboardingFactRow(
                        icon: "lock.fill",
                        title: String(localized: "AES-256 encryption"),
                        detail: String(localized: "The standard banks use, applied the moment a file enters.")
                    )
                    OnboardingFactRow(
                        icon: "iphone",
                        title: String(localized: "Stays on your device"),
                        detail: String(localized: "Nothing reaches a server. No sign-up, no email, no profile.")
                    )
                    OnboardingFactRow(
                        icon: "eye.slash.fill",
                        title: String(localized: "Invisible to the Photos app"),
                        detail: String(localized: "Imported files leave your camera roll and stay encrypted here.")
                    )
                }
            }
            .padding(.horizontal, Constants.standardPadding)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Social Proof Copy

/// Review copy shown during onboarding and on the paywall.
///
/// - Important: These must be verbatim, attributable App Store reviews before release.
///   Swap the placeholders below for real ones — fabricated testimonials are an App
///   Review rejection and a trust problem for a privacy app.
enum OnboardingSocialProof {
    struct Review: Sendable {
        let quote: String
        let author: String
    }

    static let featuredReview = Review(
        quote: String(localized: "\"I stopped panicking every time someone asked to see a photo on my phone.\""),
        author: String(localized: "App Store review")
    )

    static let reviews: [Review] = [
        featuredReview,
        Review(
            quote: String(localized: "\"The break-in photo caught my brother going through my phone. Worth it alone.\""),
            author: String(localized: "App Store review")
        )
    ]
}
