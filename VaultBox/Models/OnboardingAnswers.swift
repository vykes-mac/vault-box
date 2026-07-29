import Foundation

// MARK: - Protection Target

/// What the user says they want to hide. Used to personalise later screens so the
/// vault feels built for them rather than generic.
enum ProtectionTarget: String, CaseIterable, Identifiable, Sendable {
    case photos
    case screenshots
    case documents
    case videos
    case work

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photos: String(localized: "Private photos")
        case .screenshots: String(localized: "Screenshots & chats")
        case .documents: String(localized: "IDs & documents")
        case .videos: String(localized: "Private videos")
        case .work: String(localized: "Work & money files")
        }
    }

    var systemImage: String {
        switch self {
        case .photos: "photo.on.rectangle.angled"
        case .screenshots: "text.bubble.fill"
        case .documents: "doc.text.fill"
        case .videos: "play.rectangle.fill"
        case .work: "briefcase.fill"
        }
    }

    /// Sentence-cased form for inline copy ("Encrypted storage for your photos and IDs").
    /// Written out rather than lowercasing ``label``, which would mangle "IDs".
    var inlineLabel: String {
        switch self {
        case .photos: String(localized: "private photos")
        case .screenshots: String(localized: "screenshots")
        case .documents: String(localized: "IDs and documents")
        case .videos: String(localized: "private videos")
        case .work: String(localized: "work files")
        }
    }
}

// MARK: - Exposure Risk

/// Who or what the user is worried about. Drives the agitation copy on the plan screen.
enum ExposureRisk: String, CaseIterable, Identifiable, Sendable {
    case borrowedPhone
    case partner
    case family
    case lostOrStolen
    case cloudLeak

    var id: String { rawValue }

    var label: String {
        switch self {
        case .borrowedPhone: String(localized: "Someone borrowing my phone")
        case .partner: String(localized: "A partner or ex")
        case .family: String(localized: "Family or kids")
        case .lostOrStolen: String(localized: "Losing my phone")
        case .cloudLeak: String(localized: "Cloud leaks & hackers")
        }
    }

    var systemImage: String {
        switch self {
        case .borrowedPhone: "hand.raised.fill"
        case .partner: "heart.slash.fill"
        case .family: "figure.2.and.child.holdinghands"
        case .lostOrStolen: "iphone.slash"
        case .cloudLeak: "icloud.slash.fill"
        }
    }
}

// MARK: - Snooping History

/// Whether the user has already been snooped on. The "yes" path is the hottest lead,
/// so the plan screen mirrors their own answer back at them.
enum SnoopingHistory: String, CaseIterable, Identifiable, Sendable {
    case yes
    case suspected
    case notYet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yes: String(localized: "Yes — it's happened")
        case .suspected: String(localized: "I think so, but I'm not sure")
        case .notYet: String(localized: "Not yet, and I want to keep it that way")
        }
    }

    var systemImage: String {
        switch self {
        case .yes: "exclamationmark.triangle.fill"
        case .suspected: "questionmark.circle.fill"
        case .notYet: "shield.lefthalf.filled"
        }
    }
}

// MARK: - Onboarding Answers

/// Lightweight, UserDefaults-backed record of the onboarding questionnaire.
///
/// Deliberately not a SwiftData model: it is written before the vault exists and is
/// only used for copy personalisation, so it must never block or migrate the store.
struct OnboardingAnswers: Codable, Equatable, Sendable {
    var targets: Set<String> = []
    var risks: Set<String> = []
    var snoopingHistory: String?

    var protectionTargets: [ProtectionTarget] {
        ProtectionTarget.allCases.filter { targets.contains($0.rawValue) }
    }

    var exposureRisks: [ExposureRisk] {
        ExposureRisk.allCases.filter { risks.contains($0.rawValue) }
    }

    var history: SnoopingHistory? {
        snoopingHistory.flatMap(SnoopingHistory.init(rawValue:))
    }

    /// Headline used on the personalised plan screen. Mirrors the user's own words back
    /// to them — self-consistency makes the following commitment (PIN, then trial) easier.
    var planHeadline: String {
        switch history {
        case .yes:
            return String(localized: "It already happened once. Let's make sure it can't happen again.")
        case .suspected:
            return String(localized: "You shouldn't have to wonder who's been looking.")
        case .notYet, .none:
            return String(localized: "The best time to lock things down is before anything happens.")
        }
    }

    /// Short, human summary of what they chose to protect ("private photos and IDs and documents").
    var targetSummary: String {
        let labels = protectionTargets.map(\.inlineLabel)
        switch labels.count {
        case 0: return String(localized: "everything private")
        case 1: return labels[0]
        case 2: return "\(labels[0]) and \(labels[1])"
        default:
            let head = labels.dropLast().joined(separator: ", ")
            return "\(head), and \(labels[labels.count - 1])"
        }
    }
}

// MARK: - Store

/// Persists ``OnboardingAnswers`` across launches so the paywall (and any later
/// re-marketing surface) can reuse the answers the user already gave.
enum OnboardingAnswersStore {
    private static let key = "com.vaultbox.onboardingAnswers"

    static func load(from defaults: UserDefaults = .standard) -> OnboardingAnswers {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(OnboardingAnswers.self, from: data) else {
            return OnboardingAnswers()
        }
        return decoded
    }

    static func save(_ answers: OnboardingAnswers, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(answers) else { return }
        defaults.set(data, forKey: key)
    }
}
