import Foundation

// MARK: - DocumentExpiryResult

struct DocumentExpiryResult: Sendable, Equatable {
    /// User-facing document type, e.g. "Passport", "Payment Card".
    let documentType: String
    /// The detected expiry date (normalized to the start of that day, local time).
    let expiryDate: Date
}

// MARK: - DocumentExpiryParser

/// Pure, on-device parser that extracts a document type and a confident expiry
/// date from OCR'd text already stored on a `VaultItem`.
///
/// Design bias: prefer **missing** an expiry over reporting a wrong one. A wrong
/// reminder ("your passport expires soon" when it doesn't) erodes trust more
/// than a silent miss. The parser therefore only returns a result when it can
/// tie a date to an explicit expiry cue (or a card's MM/YY pattern on a payment
/// card) and the year is plausible.
enum DocumentExpiryParser {

    /// Characters of look-ahead from an expiry keyword within which a date must
    /// appear to be considered "associated" with that keyword.
    private static let associationWindow = 40

    static func parse(text: String?, smartTags: [String] = []) -> DocumentExpiryResult? {
        guard let raw = text, !raw.isEmpty else { return nil }
        let lower = raw.lowercased()

        guard let documentType = detectDocumentType(lower: lower, smartTags: smartTags) else {
            return nil
        }

        guard let expiry = detectExpiryDate(in: raw, lower: lower, documentType: documentType) else {
            return nil
        }

        return DocumentExpiryResult(documentType: documentType, expiryDate: expiry)
    }

    // MARK: - Document Type

    private static func detectDocumentType(lower: String, smartTags: [String]) -> String? {
        // Order matters: most specific first.
        if contains(lower, ["passport"]) { return "Passport" }
        if contains(lower, ["driver license", "driver's license", "driving licence", "driving license", "driver licence"]) {
            return "Driver's License"
        }
        if contains(lower, ["residence permit", "permanent resident", "green card"]) { return "Residence Permit" }
        // Payment cards are checked before the travel-visa heuristic: a Visa/Amex
        // *card* contains the word "visa" but is unambiguously a card thanks to a
        // Luhn-valid number or card-specific phrasing ("valid thru", "cardholder").
        if contains(lower, ["credit card", "debit card", "card number", "cardholder", "card holder", "valid thru", "valid through", "mastercard", "american express", "visa debit", "visa credit"])
            || ImageSignalDetectors.containsLikelyCardNumber(lower) {
            return "Payment Card"
        }
        if contains(lower, ["visa"]) && contains(lower, ["expir", "valid", "entries", "issued"]) { return "Visa" }
        if contains(lower, ["health insurance", "insurance card", "insurance policy", "policy number"]) { return "Insurance" }
        if contains(lower, ["vehicle registration", "registration card", "certificate of registration"]) {
            return "Vehicle Registration"
        }
        if contains(lower, ["national id", "identity card", "identification card", "id card", "national identity"]) {
            return "ID Card"
        }
        if contains(lower, ["membership", "member id", "loyalty"]) && contains(lower, ["expir", "valid"]) {
            return "Membership Card"
        }
        return nil
    }

    // MARK: - Expiry Date

    private static func detectExpiryDate(in raw: String, lower: String, documentType: String) -> Date? {
        let candidates = dateCandidates(in: raw)
        guard !candidates.isEmpty else { return nil }

        let expiryKeywordRanges = keywordRanges(in: lower, keywords: expiryKeywords)
        let exclusionRanges = keywordRanges(in: lower, keywords: exclusionKeywords)

        var associated: [Date] = []

        for candidate in candidates {
            // Classify by the *nearest preceding* keyword: a date counts as an
            // expiry only when an expiry cue is closer to it than any birth/issue
            // cue. This correctly handles layouts where a DOB and an expiry date
            // sit on adjacent lines (e.g. driver licenses).
            let expiryDistance = nearestPrecedingDistance(candidate.range, keywords: expiryKeywordRanges, within: associationWindow)
            let exclusionDistance = nearestPrecedingDistance(candidate.range, keywords: exclusionRanges, within: associationWindow)

            let hasNearbyExpiryCue: Bool
            if let expiryDistance {
                hasNearbyExpiryCue = !(exclusionDistance.map { $0 < expiryDistance } ?? false)
            } else {
                hasNearbyExpiryCue = false
            }
            let hasLineExpiryCue = isLineAssociatedWithExpiry(
                candidate.range,
                raw: raw,
                expiryKeywordRanges: expiryKeywordRanges,
                exclusionRanges: exclusionRanges
            )

            guard hasNearbyExpiryCue || hasLineExpiryCue else { continue }
            associated.append(candidate.date)
        }

        // Fallback: a payment card with a bare MM/YY and no explicit "expiry" word
        // is still unambiguous — the MM/YY on a card *is* the expiry.
        if associated.isEmpty, documentType == "Payment Card" {
            let mmyy = candidates.filter { $0.isMonthYear }.map(\.date)
            if mmyy.count == 1 {
                associated = mmyy
            }
        }

        guard let chosen = associated.max() else { return nil }
        guard isPlausibleExpiryYear(chosen) else { return nil }
        return Calendar.current.startOfDay(for: chosen)
    }

    // MARK: - Date Candidate Extraction

    private struct DateCandidate {
        let date: Date
        let range: NSRange
        let isMonthYear: Bool
    }

    private static func dateCandidates(in raw: String) -> [DateCandidate] {
        var result: [DateCandidate] = []
        let ns = raw as NSString

        // 1. Full dates via NSDataDetector.
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            detector.enumerateMatches(in: raw, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                if let match, let date = match.date {
                    result.append(DateCandidate(date: date, range: match.range, isMonthYear: false))
                }
            }
        }

        // 2. MM/YY or MM/YYYY (common card / expiry shorthand the detector misses).
        result.append(contentsOf: monthYearCandidates(in: raw, ns: ns))

        return result
    }

    private static func monthYearCandidates(in raw: String, ns: NSString) -> [DateCandidate] {
        let pattern = #"(?<![0-9])(0[1-9]|1[0-2])\s*/\s*([0-9]{4}|[0-9]{2})(?![0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        var out: [DateCandidate] = []
        regex.enumerateMatches(in: raw, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match,
                  let monthRange = Range(match.range(at: 1), in: raw),
                  let yearRange = Range(match.range(at: 2), in: raw),
                  let month = Int(raw[monthRange]) else { return }
            var year = Int(raw[yearRange]) ?? 0
            if year < 100 { year += 2000 }

            // Expiry shorthand means "end of that month".
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            guard let firstOfMonth = calendar.date(from: comps),
                  let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: firstOfMonth) else {
                return
            }
            out.append(DateCandidate(date: endOfMonth, range: match.range, isMonthYear: true))
        }
        return out
    }

    // MARK: - Keyword Range Helpers

    private static func keywordRanges(in lower: String, keywords: [String]) -> [NSRange] {
        let ns = lower as NSString
        var ranges: [NSRange] = []
        for keyword in keywords {
            var searchStart = 0
            while searchStart < ns.length {
                let found = ns.range(
                    of: keyword,
                    options: [],
                    range: NSRange(location: searchStart, length: ns.length - searchStart)
                )
                guard found.location != NSNotFound else { break }
                ranges.append(found)
                searchStart = found.location + max(found.length, 1)
            }
        }
        return ranges
    }

    /// Smallest distance from the end of any keyword that *starts before* the
    /// candidate to the candidate's start, if within `within` chars. Returns
    /// `nil` when no such keyword precedes the candidate in range.
    private static func nearestPrecedingDistance(_ range: NSRange, keywords: [NSRange], within: Int) -> Int? {
        var best: Int?
        for keyword in keywords where keyword.location <= range.location {
            let keywordEnd = keyword.location + keyword.length
            let distance = range.location - keywordEnd
            // Allow a small overlap (date may begin inside/right at the cue).
            guard distance >= -keyword.length, distance <= within else { continue }
            let clamped = max(distance, 0)
            if let current = best {
                best = min(current, clamped)
            } else {
                best = clamped
            }
        }
        return best
    }

    /// OCR for passports often returns a long multilingual label, e.g.
    /// "DATE OF EXPIRY / DATE D'EXPIRATION / FECHA DE VENCIMIENTO", with the
    /// actual date on the next line. That can exceed the short inline association
    /// window, but is still a strong layout relationship.
    private static func isLineAssociatedWithExpiry(
        _ candidateRange: NSRange,
        raw: String,
        expiryKeywordRanges: [NSRange],
        exclusionRanges: [NSRange]
    ) -> Bool {
        let context = previousLineAndCandidatePrefix(for: candidateRange, raw: raw)
        guard context.length > 0 else { return false }

        let expiryRanges = expiryKeywordRanges.filter {
            NSIntersectionRange($0, context).length > 0 && $0.location <= candidateRange.location
        }
        guard let latestExpiry = expiryRanges.max(by: { $0.location < $1.location }) else {
            return false
        }

        let hasLaterExclusion = exclusionRanges.contains {
            NSIntersectionRange($0, context).length > 0
                && $0.location > latestExpiry.location
                && $0.location <= candidateRange.location
        }
        return !hasLaterExclusion
    }

    private static func previousLineAndCandidatePrefix(for range: NSRange, raw: String) -> NSRange {
        let ns = raw as NSString
        let currentLineStart = lineStart(beforeOrAt: range.location, in: ns)
        let contextStart: Int
        if currentLineStart > 0 {
            contextStart = lineStart(beforeOrAt: currentLineStart - 1, in: ns)
        } else {
            contextStart = currentLineStart
        }
        return NSRange(location: contextStart, length: max(0, range.location - contextStart))
    }

    private static func lineStart(beforeOrAt location: Int, in ns: NSString) -> Int {
        var index = min(max(location, 0), ns.length)
        while index > 0 {
            let scalar = ns.character(at: index - 1)
            if scalar == 10 || scalar == 13 {
                break
            }
            index -= 1
        }
        return index
    }

    // MARK: - Validation

    private static func isPlausibleExpiryYear(_ date: Date) -> Bool {
        let year = Calendar.current.component(.year, from: date)
        let currentYear = Calendar.current.component(.year, from: Date())
        // Allow recently-expired docs (worth surfacing) through far-future renewals.
        return year >= (currentYear - 20) && year <= (currentYear + 30)
    }

    private static func contains(_ haystack: String, _ needles: [String]) -> Bool {
        for needle in needles where haystack.contains(needle) {
            return true
        }
        return false
    }
}

// MARK: - Keyword Dictionaries

private let expiryKeywords = [
    "date of expiry", "expiry date", "expiration date", "expires", "expiry",
    "expiration", "valid thru", "valid through", "valid until", "exp.", "exp ",
    "good thru", "good through"
]

private let exclusionKeywords = [
    "date of birth", "birth", "date of issue", "issued", "issue date", "doi", "dob"
]
