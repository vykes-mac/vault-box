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
    /// Other apps the user wants off their Home Screen. Only offered when this build can
    /// actually hide apps; see ``available(hideAppsEnabled:)``.
    case apps

    var id: String { rawValue }

    /// The targets this build can deliver on. Offering "Private apps" without Hide Apps
    /// would be a promise the plan screen can't keep.
    static func available(
        hideAppsEnabled: Bool = HideAppsAvailability.isEnabled
    ) -> [ProtectionTarget] {
        allCases.filter { $0 != .apps || hideAppsEnabled }
    }

    var label: String {
        switch self {
        case .photos: String(localized: "Private photos")
        case .screenshots: String(localized: "Screenshots & chats")
        case .documents: String(localized: "IDs & documents")
        case .videos: String(localized: "Private videos")
        case .work: String(localized: "Work & money files")
        case .apps: String(localized: "Private apps")
        }
    }

    var systemImage: String {
        switch self {
        case .photos: "photo.on.rectangle.angled"
        case .screenshots: "text.bubble.fill"
        case .documents: "doc.text.fill"
        case .videos: "play.rectangle.fill"
        case .work: "briefcase.fill"
        case .apps: "square.grid.2x2.fill"
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
        case .apps: String(localized: "private apps")
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

// MARK: - Private App Kind

/// The kinds of apps the user would rather keep off their Home Screen. Asked during
/// onboarding so they learn Hide Apps exists before they ever reach the vault; only
/// offered when this build can hide apps.
enum PrivateAppKind: String, CaseIterable, Identifiable, Sendable {
    case dating
    case chat
    case social
    case money
    case games
    /// "None for now". Picking it clears the others, and picking another clears it.
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dating: String(localized: "Dating apps")
        case .chat: String(localized: "Chat & messaging")
        case .social: String(localized: "Social media")
        case .money: String(localized: "Banking & crypto")
        case .games: String(localized: "Games")
        case .none: String(localized: "None for now")
        }
    }

    var systemImage: String {
        switch self {
        case .dating: "heart.fill"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .social: "person.2.fill"
        case .money: "creditcard.fill"
        case .games: "gamecontroller.fill"
        case .none: "minus.circle"
        }
    }

    /// Lowercase form for inline copy ("Your dating apps and games vanish…").
    var inlineLabel: String {
        switch self {
        case .dating: String(localized: "dating apps")
        case .chat: String(localized: "chat apps")
        case .social: String(localized: "social apps")
        case .money: String(localized: "banking apps")
        case .games: String(localized: "games")
        case .none: ""
        }
    }

    /// Applies a tap to a multi-select answer, keeping "None for now" exclusive.
    static func toggling(_ kind: PrivateAppKind, in selection: Set<String>) -> Set<String> {
        var selection = selection
        if selection.contains(kind.rawValue) {
            selection.remove(kind.rawValue)
        } else if kind == .none {
            selection = [kind.rawValue]
        } else {
            selection.remove(PrivateAppKind.none.rawValue)
            selection.insert(kind.rawValue)
        }
        return selection
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
    /// ``PrivateAppKind`` raw values. Empty for answers saved before this question existed.
    var appKinds: Set<String> = []

    init() {}

    // Written by hand so answers saved before `appKinds` existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targets = try container.decodeIfPresent(Set<String>.self, forKey: .targets) ?? []
        risks = try container.decodeIfPresent(Set<String>.self, forKey: .risks) ?? []
        snoopingHistory = try container.decodeIfPresent(String.self, forKey: .snoopingHistory)
        appKinds = try container.decodeIfPresent(Set<String>.self, forKey: .appKinds) ?? []
    }

    var protectionTargets: [ProtectionTarget] {
        protectionTargets(hideAppsEnabled: HideAppsAvailability.isEnabled)
    }

    func protectionTargets(hideAppsEnabled: Bool) -> [ProtectionTarget] {
        ProtectionTarget.available(hideAppsEnabled: hideAppsEnabled)
            .filter { targets.contains($0.rawValue) }
    }

    var exposureRisks: [ExposureRisk] {
        ExposureRisk.allCases.filter { risks.contains($0.rawValue) }
    }

    var history: SnoopingHistory? {
        snoopingHistory.flatMap(SnoopingHistory.init(rawValue:))
    }

    /// The app kinds picked, in display order, without "None for now".
    var privateAppKinds: [PrivateAppKind] {
        PrivateAppKind.allCases.filter { $0 != .none && appKinds.contains($0.rawValue) }
    }

    /// Plan-screen copy for Hide Apps, naming the apps they said they'd hide.
    var hiddenAppsDetail: String {
        let kinds = privateAppKinds.map(\.inlineLabel)
        guard !kinds.isEmpty else {
            return String(localized: "Pick any app, like dating or chat apps, and it vanishes from your Home Screen. Only VaultBox brings it back.")
        }
        let list = kinds.formatted(.list(type: .and))
        return String(localized: "Your \(list) vanish from your Home Screen, App Library and search. Only VaultBox brings them back.")
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
