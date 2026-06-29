import Foundation
import Vision
import CoreGraphics
import ImageIO

// MARK: - ImageSignalDetectors

/// Shared, on-device image signal primitives used by both `VisionAnalysisService`
/// (smart-tagging imported vault items) and `SensitiveContentScanService`
/// (flagging sensitive photos still in the camera roll).
///
/// All members are `nonisolated static` pure functions so they can run off any
/// actor. Nothing here performs network access — detection is 100% local.
enum ImageSignalDetectors {

    // MARK: - OCR

    /// Recognizes text in an image. Returns `nil` when nothing is found.
    static func recognizeText(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        level: VNRequestTextRecognitionLevel
    ) -> String? {
        recognizeTextDetails(on: cgImage, orientation: orientation, level: level)?.text
    }

    static func recognizeTextDetails(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        level: VNRequestTextRecognitionLevel
    ) -> RecognizedImageText? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = (level == .accurate)

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            let strings = observations.compactMap { $0.topCandidates(1).first?.string }
            let joined = strings.joined(separator: " ")
            let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : RecognizedImageText(text: trimmed, lineCount: strings.count)
        } catch {
            return nil
        }
    }

    // MARK: - Barcode / QR

    /// Returns `true` if the image contains at least one barcode or QR code.
    static func detectBarcodes(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> Bool {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
            return !(request.results ?? []).isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Screenshot

    /// Detects whether a given pixel size matches the device's native screen
    /// resolution (in either orientation), which strongly indicates a screenshot.
    static func isScreenshot(
        pixelWidth: Int?,
        pixelHeight: Int?,
        screenBounds: CGSize
    ) -> Bool {
        guard let width = pixelWidth, let height = pixelHeight else { return false }
        let screenW = Int(screenBounds.width.rounded())
        let screenH = Int(screenBounds.height.rounded())
        return (width == screenW && height == screenH) ||
               (width == screenH && height == screenW)
    }

    // MARK: - Sensitive Content Classification

    /// A reason a photo was flagged as sensitive. Raw values are stable
    /// identifiers; `displayLabel` is the user-facing chip text.
    enum SensitiveReason: String, Sendable, CaseIterable {
        case identityDocument
        case paymentCard
        case financial
        case credentials
        case barcode
        case screenshotWithText

        var displayLabel: String {
            switch self {
            case .identityDocument: "Looks like an ID"
            case .paymentCard: "Possible card number"
            case .financial: "Financial info"
            case .credentials: "Passwords / login"
            case .barcode: "Code / pass"
            case .screenshotWithText: "Screenshot with text"
            }
        }
    }

    /// Classifies the sensitivity of a photo from cheap, already-computed signals.
    /// - Parameters:
    ///   - text: OCR text from the image (may be `nil`).
    ///   - isScreenshot: whether the image matches the screen resolution.
    ///   - hasBarcode: whether a barcode/QR was detected.
    /// - Returns: the set of reasons the photo looks sensitive (empty if none).
    static func sensitiveReasons(
        text: String?,
        isScreenshot: Bool,
        hasBarcode: Bool,
        layout: SensitiveImageLayout = .empty
    ) -> Set<SensitiveReason> {
        var reasons = Set<SensitiveReason>()
        let normalized = (text ?? "").lowercased()
        let hasText = normalized.contains { !$0.isWhitespace }

        if !normalized.isEmpty {
            if identityScore(text: text ?? "", normalized: normalized, hasBarcode: hasBarcode, layout: layout) >= 3 {
                reasons.insert(.identityDocument)
            }
            if paymentScore(text: text ?? "", normalized: normalized, layout: layout) >= 3 {
                reasons.insert(.paymentCard)
            }
            if financialScore(text: text ?? "", normalized: normalized, isScreenshot: isScreenshot) >= 3 {
                reasons.insert(.financial)
            }
            if credentialScore(text: text ?? "", normalized: normalized, isScreenshot: isScreenshot) >= 3 {
                reasons.insert(.credentials)
            }
        }

        // A bare barcode/QR on its own is weakly sensitive (boarding pass, ticket,
        // membership). Only flag it when it isn't already covered by a stronger reason.
        if hasBarcode, reasons.isEmpty {
            reasons.insert(.barcode)
        }

        // A screenshot containing text is a common vector for leaked credentials,
        // OTPs, and account details — but only flag it if no stronger reason applies,
        // to avoid drowning the user in low-signal hits.
        if isScreenshot, hasText, reasons.isEmpty {
            reasons.insert(.screenshotWithText)
        }

        return reasons
    }

    static func shouldRetryAccurateOCR(
        text: String?,
        isScreenshot: Bool,
        hasBarcode: Bool,
        layout: SensitiveImageLayout,
        reasons: Set<SensitiveReason>
    ) -> Bool {
        if reasons.contains(.identityDocument) ||
           reasons.contains(.paymentCard) ||
           reasons.contains(.financial) ||
           reasons.contains(.credentials) {
            return false
        }

        let normalized = (text ?? "").lowercased()
        return isScreenshot ||
               hasBarcode ||
               layout.hasDocumentRectangle ||
               layout.hasCardAspectRectangle ||
               containsWeakClassificationSignal(normalized)
    }

    // MARK: - Card Number Detection (Luhn)

    /// Returns `true` if the text contains a digit run of 13–19 digits that
    /// passes the Luhn checksum (the standard credit/debit card validation).
    static func containsLikelyCardNumber(_ text: String) -> Bool {
        var currentDigits: [Int] = []
        currentDigits.reserveCapacity(19)

        func flushPasses() -> Bool {
            defer { currentDigits.removeAll(keepingCapacity: true) }
            let count = currentDigits.count
            guard count >= 13, count <= 19 else { return false }
            return luhnValid(currentDigits)
        }

        for scalar in text.unicodeScalars {
            if scalar.value >= 48, scalar.value <= 57 { // ASCII 0-9
                currentDigits.append(Int(scalar.value - 48))
                if currentDigits.count > 19 {
                    currentDigits.removeFirst()
                }
            } else if scalar == " " || scalar == "-" {
                // Separators commonly appear inside grouped card numbers; keep scanning.
                continue
            } else {
                if flushPasses() { return true }
            }
        }
        return flushPasses()
    }

    private static func luhnValid(_ digits: [Int]) -> Bool {
        var sum = 0
        var double = false
        for digit in digits.reversed() {
            var value = digit
            if double {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
            double.toggle()
        }
        return sum % 10 == 0
    }

    // MARK: - Identity / Document Formats

    /// Detects passport and ID-card MRZ lines such as `P<...` or `I<...`.
    static func containsMachineReadableZone(_ text: String) -> Bool {
        let upper = text.uppercased()
        return firstMatch(in: upper, pattern: #"\b[PIAVC]<[A-Z0-9<]{20,}"#)
    }

    /// Detects valid-looking US SSNs while rejecting impossible area/group/serial values.
    static func containsLikelyUSSocialSecurityNumber(_ text: String) -> Bool {
        firstMatch(
            in: text,
            pattern: #"\b(?!000|666|9\d{2})\d{3}[- ]?(?!00)\d{2}[- ]?(?!0000)\d{4}\b"#
        )
    }

    // MARK: - Financial Formats

    static func containsLikelyIBAN(_ text: String) -> Bool {
        let tokens = text
            .uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for start in tokens.indices {
            var candidate = ""
            for token in tokens[start...] {
                candidate += token
                guard candidate.count <= 34 else { break }
                if candidate.count >= 15, ibanChecksumValid(candidate) {
                    return true
                }
            }
        }
        return false
    }

    static func containsLikelyRoutingNumber(_ text: String, normalized: String) -> Bool {
        guard containsAny(normalized, ["routing", "aba number", "routing number"]) else { return false }
        return digitRuns(in: text, allowedSeparators: [" ", "-"]).contains { digits in
            guard digits.count == 9, digits.contains(where: { $0 != 0 }) else { return false }
            let checksum = 3 * (digits[0] + digits[3] + digits[6]) +
                           7 * (digits[1] + digits[4] + digits[7]) +
                           digits[2] + digits[5] + digits[8]
            return checksum % 10 == 0
        }
    }

    private static func identityScore(
        text: String,
        normalized: String,
        hasBarcode: Bool,
        layout: SensitiveImageLayout
    ) -> Int {
        var score = 0
        if containsMachineReadableZone(text) { score += 5 }
        if containsLikelyUSSocialSecurityNumber(text) { score += 4 }
        if containsAny(normalized, identityKeywords) { score += 3 }
        if layout.hasDocumentRectangle { score += 1 }
        if layout.hasCardAspectRectangle { score += 1 }
        if hasBarcode { score += 1 }
        if layout.textLineCount >= 4 { score += 1 }
        return score
    }

    private static func paymentScore(
        text: String,
        normalized: String,
        layout: SensitiveImageLayout
    ) -> Int {
        var score = 0
        if containsLikelyCardNumber(text) { score += 5 }
        if containsAny(normalized, paymentKeywords) { score += 3 }
        if layout.hasCardAspectRectangle { score += 1 }
        if layout.textLineCount >= 3 { score += 1 }
        return score
    }

    private static func financialScore(
        text: String,
        normalized: String,
        isScreenshot: Bool
    ) -> Int {
        if containsStrongFinancialSignal(text, normalized: normalized) { return 3 }

        var score = 0
        if containsAny(normalized, weakFinancialKeywords) { score += 1 }
        if containsMoneyAmount(text) { score += 2 }
        if containsLongDigitRun(text, minimumDigits: 6) { score += 1 }
        if isScreenshot { score += 1 }
        return score
    }

    private static func credentialScore(
        text: String,
        normalized: String,
        isScreenshot: Bool
    ) -> Int {
        var score = 0
        if containsAny(normalized, credentialKeywords) { score += 3 }
        if containsCredentialToken(text) { score += 5 }
        if containsOneTimeCodeContext(text, normalized: normalized) { score += 4 }
        if isScreenshot, containsAny(normalized, ["login", "sign in", "account"]) { score += 1 }
        return score
    }

    private static func containsStrongFinancialSignal(_ text: String, normalized: String) -> Bool {
        if containsAny(normalized, strongFinancialKeywords) ||
           containsLikelyIBAN(text) ||
           containsLikelyRoutingNumber(text, normalized: normalized) {
            return true
        }

        if containsAny(normalized, weakFinancialKeywords) {
            return containsMoneyAmount(text) || containsLongDigitRun(text, minimumDigits: 6)
        }
        return false
    }

    private static func containsWeakClassificationSignal(_ normalized: String) -> Bool {
        containsAny(normalized, weakFinancialKeywords) ||
        containsAny(normalized, ["login", "sign in", "account", "verify", "verification"])
    }

    private static func ibanChecksumValid(_ value: String) -> Bool {
        guard value.count >= 15, value.count <= 34 else { return false }
        let scalars = Array(value.unicodeScalars)
        guard scalars[0].value >= 65, scalars[0].value <= 90,
              scalars[1].value >= 65, scalars[1].value <= 90,
              scalars[2].value >= 48, scalars[2].value <= 57,
              scalars[3].value >= 48, scalars[3].value <= 57 else {
            return false
        }

        var remainder = 0
        for scalar in scalars.dropFirst(4) + scalars.prefix(4) {
            switch scalar.value {
            case 48...57:
                remainder = (remainder * 10 + Int(scalar.value - 48)) % 97
            case 65...90:
                let number = Int(scalar.value - 55)
                remainder = (remainder * 100 + number) % 97
            default:
                return false
            }
        }
        return remainder == 1
    }

    // MARK: - Credential Formats

    private static func containsStrongCredentialSignal(_ text: String, normalized: String) -> Bool {
        containsAny(normalized, credentialKeywords) ||
        containsCredentialToken(text) ||
        containsOneTimeCodeContext(text, normalized: normalized)
    }

    static func containsCredentialToken(_ text: String) -> Bool {
        let patterns = [
            #"AKIA[0-9A-Z]{16}"#, // AWS access key id
            #"gh[pousr]_[A-Za-z0-9_]{20,}"#, // GitHub tokens
            #"xox[baprs]-[A-Za-z0-9-]{20,}"#, // Slack tokens
            #"sk-[A-Za-z0-9_-]{20,}"#, // OpenAI-style secret keys
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#
        ]
        return patterns.contains { firstMatch(in: text, pattern: $0) }
    }

    static func containsOneTimeCodeContext(_ text: String, normalized: String) -> Bool {
        guard containsAny(normalized, oneTimeCodeKeywords) else { return false }
        return firstMatch(in: text, pattern: #"\b\d{4,8}\b"#)
    }

    // MARK: - Numeric / Regex Helpers

    private static func containsMoneyAmount(_ text: String) -> Bool {
        firstMatch(in: text, pattern: #"(?i)([$£€]\s?\d|\b\d+[\.,]\d{2}\b)"#)
    }

    private static func containsLongDigitRun(_ text: String, minimumDigits: Int) -> Bool {
        digitRuns(in: text, allowedSeparators: [" ", "-"]).contains { $0.count >= minimumDigits }
    }

    private static func digitRuns(in text: String, allowedSeparators: Set<Character>) -> [[Int]] {
        var runs: [[Int]] = []
        var current: [Int] = []

        func flush() {
            if !current.isEmpty { runs.append(current) }
            current.removeAll(keepingCapacity: true)
        }

        for character in text {
            if let digit = character.wholeNumberValue {
                current.append(digit)
            } else if allowedSeparators.contains(character), !current.isEmpty {
                continue
            } else {
                flush()
            }
        }
        flush()
        return runs
    }

    private static func firstMatch(in text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    // MARK: - Keyword Helpers

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        for needle in needles where haystack.contains(needle) {
            return true
        }
        return false
    }
}

// MARK: - Keyword Dictionaries

private let identityKeywords = [
    "passport", "driver license", "driver's license", "driving licence", "driving license",
    "identity card", "identification", "national id", "date of birth", "date of expiry",
    "social security", "permanent resident", "residence permit", "visa",
    "place of birth", "nationality"
]

private let paymentKeywords = [
    "credit card", "debit card", "card number", "cardholder", "card holder",
    "valid thru", "valid through", "cvv", "cvc", "security code", "expiry date",
    "mastercard", "visa debit", "visa credit", "american express"
]

private let strongFinancialKeywords = [
    "account number", "routing number", "iban", "swift", "sort code",
    "bank statement", "available balance", "account balance",
    "tax return", "social insurance", "wire transfer", "beneficiary"
]

private let weakFinancialKeywords = [
    "invoice", "receipt", "statement"
]

private let credentialKeywords = [
    "password", "passphrase", "username", "two-factor", "2fa",
    "verification code", "one-time code", "recovery code", "backup code",
    "seed phrase", "recovery phrase", "private key", "api key", "login credentials",
    "pin code", "otp", "authenticator"
]

private let oneTimeCodeKeywords = [
    "verification", "one-time", "one time", "two-factor", "2fa",
    "authenticator", "login code", "security code", "otp"
]
