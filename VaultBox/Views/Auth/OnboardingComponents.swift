import SwiftUI

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.vaultSurfaceSecondary)
                Capsule()
                    .fill(Color.vaultAccent)
                    .frame(width: max(8, geometry.size.width * progress))
            }
        }
        .frame(height: 6)
        .animation(.snappy(duration: 0.35), value: progress)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

// MARK: - Background

/// Soft accent glow behind every onboarding step. Keeps the funnel feeling like one
/// continuous surface while the content slides through it.
struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            Color.vaultBackground

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.vaultAccent.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 260
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: -120, y: -260)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.vaultAccent.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 240
                    )
                )
                .frame(width: 480, height: 480)
                .offset(x: 150, y: 320)
        }
    }
}

// MARK: - Headline

struct OnboardingHeadline: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?

    init(eyebrow: String? = nil, title: String, subtitle: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.vaultAccent)
            }

            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.vaultTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Selectable Row

/// Tappable answer row used by every question step. Selected state is loud on purpose:
/// visible accumulated choices make the vault feel co-authored by the user.
struct OnboardingChoiceRow: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let allowsMultiple: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.vaultAccent : Color.vaultTextSecondary)
                    .frame(width: 28)

                Text(label)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.vaultTextPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Image(systemName: indicatorImage)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.vaultAccent : Color.vaultTextSecondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.vaultAccent.opacity(0.12) : Color.vaultSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.vaultAccent : Color.clear,
                        lineWidth: 1.5
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var indicatorImage: String {
        if allowsMultiple {
            return isSelected ? "checkmark.circle.fill" : "circle"
        }
        return isSelected ? "largecircle.fill.circle" : "circle"
    }
}

// MARK: - Fact Row

/// Icon + copy pair used on the trust and plan steps.
struct OnboardingFactRow: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color = .vaultAccent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.vaultTextPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Star Rating

struct OnboardingStarRating: View {
    var count: Int = 5
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.system(size: size))
                    .foregroundStyle(Color.vaultPremium)
            }
        }
        .accessibilityLabel("\(count) out of 5 stars")
    }
}

// MARK: - Review Card

struct OnboardingReviewCard: View {
    let quote: String
    let author: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnboardingStarRating()

            Text(quote)
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(author)
                .font(.caption)
                .foregroundStyle(Color.vaultTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.vaultSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
