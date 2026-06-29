import Foundation

extension ImageSignalDetectors {
    static func smartDocumentTags(text: String?) -> Set<String> {
        guard let text else { return [] }
        let normalized = text.lowercased()
        guard normalized.contains(where: { !$0.isWhitespace }) else { return [] }

        var tags = Set<String>()
        if SmartAlbumTextClassifier.isReceipt(text: text, normalized: normalized) {
            tags.insert("receipt")
        }
        if SmartAlbumTextClassifier.isContract(normalized: normalized) {
            tags.insert("contract")
        }
        if SmartAlbumTextClassifier.isIDOrCard(text: text, normalized: normalized) {
            tags.insert("idcard")
        }
        return tags
    }
}

private enum SmartAlbumTextClassifier {
    static func isReceipt(text: String, normalized: String) -> Bool {
        var score = 0
        if containsAny(normalized, receiptKeywords) { score += 2 }
        if containsAny(normalized, receiptLineItemKeywords) { score += 1 }
        if containsMoneyAmount(text) { score += 1 }
        if firstMatch(in: text, pattern: #"(?i)\b\d+\s?%\b"#) { score += 1 }
        return score >= 3
    }

    static func isContract(normalized: String) -> Bool {
        var score = 0
        if containsAny(normalized, contractStrongKeywords) { score += 3 }
        if containsAny(normalized, contractSupportKeywords) { score += 1 }
        if containsAny(normalized, ["signature", "signed", "effective date"]) { score += 1 }
        return score >= 3
    }

    static func isIDOrCard(text: String, normalized: String) -> Bool {
        ImageSignalDetectors.containsMachineReadableZone(text) ||
        ImageSignalDetectors.containsLikelyUSSocialSecurityNumber(text) ||
        ImageSignalDetectors.containsLikelyCardNumber(text) ||
        containsAny(normalized, idCardKeywords)
    }

    private static func containsMoneyAmount(_ text: String) -> Bool {
        firstMatch(in: text, pattern: #"(?i)([$£€]\s?\d|\b\d+[\.,]\d{2}\b)"#)
    }

    private static func firstMatch(in text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}

private let receiptKeywords = [
    "receipt", "subtotal", "total", "tax", "tip", "change due", "cash", "debit", "credit"
]

private let receiptLineItemKeywords = [
    "qty", "item", "merchant", "store", "sale", "purchase", "visa", "mastercard"
]

private let contractStrongKeywords = [
    "agreement", "contract", "terms and conditions", "service agreement", "lease agreement",
    "non-disclosure", "nda"
]

private let contractSupportKeywords = [
    "party", "parties", "whereas", "hereby", "obligations", "termination", "clause",
    "governing law", "liability", "consideration"
]

private let idCardKeywords = [
    "passport", "driver license", "driver's license", "driving licence", "driving license",
    "identity card", "identification", "national id", "date of birth", "date of expiry",
    "credit card", "debit card", "card number", "cardholder", "card holder",
    "valid thru", "valid through", "cvv", "cvc"
]
