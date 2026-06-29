import Foundation
import Testing
@testable import VaultBox

@Suite("ImageSignalDetectors Tests")
struct ImageSignalDetectorsTests {

    // MARK: - Luhn / card numbers

    @Test("Detects a Luhn-valid card number with spaces")
    func detectsValidCard() {
        #expect(ImageSignalDetectors.containsLikelyCardNumber("Card 4111 1111 1111 1111 exp"))
    }

    @Test("Detects a Luhn-valid card number with dashes")
    func detectsValidCardDashes() {
        #expect(ImageSignalDetectors.containsLikelyCardNumber("5500-0000-0000-0004"))
    }

    @Test("Rejects a non-Luhn 16-digit run")
    func rejectsInvalidCard() {
        #expect(!ImageSignalDetectors.containsLikelyCardNumber("1234 5678 9012 3456"))
    }

    @Test("Rejects short digit runs like phone numbers")
    func rejectsShortRuns() {
        #expect(!ImageSignalDetectors.containsLikelyCardNumber("call 555 0142"))
    }

    // MARK: - Screenshot detection

    @Test("Matches screen resolution in portrait and landscape")
    func screenshotMatch() {
        let bounds = CGSize(width: 1170, height: 2532)
        #expect(ImageSignalDetectors.isScreenshot(pixelWidth: 1170, pixelHeight: 2532, screenBounds: bounds))
        #expect(ImageSignalDetectors.isScreenshot(pixelWidth: 2532, pixelHeight: 1170, screenBounds: bounds))
        #expect(!ImageSignalDetectors.isScreenshot(pixelWidth: 4032, pixelHeight: 3024, screenBounds: bounds))
        #expect(!ImageSignalDetectors.isScreenshot(pixelWidth: nil, pixelHeight: nil, screenBounds: bounds))
    }

    // MARK: - Sensitive classification

    @Test("Flags identity documents")
    func flagsIdentity() {
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: "PASSPORT date of birth nationality",
            isScreenshot: false,
            hasBarcode: false
        )
        #expect(reasons.contains(.identityDocument))
    }

    @Test("Flags payment card via Luhn number")
    func flagsCard() {
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: "4111 1111 1111 1111",
            isScreenshot: false,
            hasBarcode: false
        )
        #expect(reasons.contains(.paymentCard))
    }

    @Test("Flags credential screenshots")
    func flagsCredentials() {
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: "username: bob password: hunter2",
            isScreenshot: true,
            hasBarcode: false
        )
        #expect(reasons.contains(.credentials))
    }

    @Test("Flags identity documents from machine readable zones")
    func flagsMachineReadableZone() {
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
            isScreenshot: false,
            hasBarcode: false
        )
        #expect(reasons.contains(.identityDocument))
    }

    @Test("Flags identity documents from SSN-like values")
    func flagsSocialSecurityNumber() {
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: "SSN 123-45-6789",
            isScreenshot: false,
            hasBarcode: false
        )
        #expect(reasons.contains(.identityDocument))
    }

    @Test("Flags financial details from IBAN checksum")
    func flagsIBAN() {
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: "IBAN GB82 WEST 1234 5698 7654 32",
            isScreenshot: false,
            hasBarcode: false
        )
        #expect(reasons.contains(.financial))
    }

    @Test("Flags financial details from routing checksum with context")
    func flagsRoutingNumber() {
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: "Routing number 021000021",
            isScreenshot: false,
            hasBarcode: false
        )
        #expect(reasons.contains(.financial))
    }

    @Test("Flags credentials from one-time code context")
    func flagsOneTimeCode() {
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: "Your verification code is 847221",
            isScreenshot: true,
            hasBarcode: false
        )
        #expect(reasons.contains(.credentials))
    }

    @Test("Flags credentials from local secret token patterns")
    func flagsSecretToken() {
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: "OPENAI_API_KEY=sk-1234567890abcdefghijklmnop",
            isScreenshot: true,
            hasBarcode: false
        )
        #expect(reasons.contains(.credentials))
    }

    @Test("Plain scenery is not flagged")
    func ignoresScenery() {
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: "sunset over the beach",
            isScreenshot: false,
            hasBarcode: false
        )
        #expect(reasons.isEmpty)
    }

    @Test("Weak financial words need supporting evidence")
    func weakFinancialNeedsEvidence() {
        let plainInvoice = ImageSignalDetectors.sensitiveReasons(
            text: "invoice template",
            isScreenshot: false,
            hasBarcode: false
        )
        #expect(plainInvoice.isEmpty)

        let paidReceipt = ImageSignalDetectors.sensitiveReasons(
            text: "receipt total $24.95",
            isScreenshot: false,
            hasBarcode: false
        )
        #expect(paidReceipt.contains(.financial))
    }

    // MARK: - Smart album text classification

    @Test("Classifies receipts for smart albums")
    func classifiesReceiptSmartAlbumTag() {
        let tags = ImageSignalDetectors.smartDocumentTags(
            text: "Receipt subtotal $19.95 tax 8% total $21.55"
        )

        #expect(tags.contains("receipt"))
    }

    @Test("Classifies contracts for smart albums")
    func classifiesContractSmartAlbumTag() {
        let tags = ImageSignalDetectors.smartDocumentTags(
            text: "Service Agreement effective date June 1. Signature of both parties required."
        )

        #expect(tags.contains("contract"))
    }

    @Test("Classifies IDs and cards for smart albums")
    func classifiesIDCardSmartAlbumTag() {
        let idTags = ImageSignalDetectors.smartDocumentTags(
            text: "Driver License date of birth expiry date"
        )
        let cardTags = ImageSignalDetectors.smartDocumentTags(
            text: "Card 4111 1111 1111 1111 valid thru"
        )

        #expect(idTags.contains("idcard"))
        #expect(cardTags.contains("idcard"))
    }

    @Test("Layout evidence can combine with barcode and text density")
    func layoutEvidenceCombinesWithOtherSignals() {
        let layout = SensitiveImageLayout(
            textLineCount: 5,
            hasDocumentRectangle: true,
            hasCardAspectRectangle: true
        )
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: "DOE JOHN 1990 2028",
            isScreenshot: false,
            hasBarcode: true,
            layout: layout
        )
        #expect(reasons.contains(.identityDocument))
    }

    @Test("Weak layout evidence alone does not flag payment cards")
    func weakLayoutAloneDoesNotFlagPaymentCard() {
        let layout = SensitiveImageLayout(textLineCount: 1, hasCardAspectRectangle: true)
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: "member since 2024",
            isScreenshot: false,
            hasBarcode: false,
            layout: layout
        )
        #expect(!reasons.contains(.paymentCard))
    }

    @Test("Accurate OCR retry is reserved for ambiguous signals")
    func accurateOCRRetryGate() {
        let weakLayout = SensitiveImageLayout(textLineCount: 2, hasDocumentRectangle: true)
        #expect(ImageSignalDetectors.shouldRetryAccurateOCR(
            text: "invoice",
            isScreenshot: false,
            hasBarcode: false,
            layout: .empty,
            reasons: []
        ))
        #expect(ImageSignalDetectors.shouldRetryAccurateOCR(
            text: nil,
            isScreenshot: false,
            hasBarcode: false,
            layout: weakLayout,
            reasons: []
        ))
        #expect(!ImageSignalDetectors.shouldRetryAccurateOCR(
            text: "password secret",
            isScreenshot: true,
            hasBarcode: false,
            layout: .empty,
            reasons: [.credentials]
        ))
    }

    @Test("Bare barcode flagged only when no stronger reason")
    func bareBarcode() {
        let reasons = ImageSignalDetectors.sensitiveReasons(
            text: nil,
            isScreenshot: false,
            hasBarcode: true
        )
        #expect(reasons == [.barcode])
    }
}
