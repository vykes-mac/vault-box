import Foundation
import Testing
@testable import VaultBox

@Suite("DocumentExpiryParser Tests")
struct DocumentExpiryParserTests {

    private func ymd(_ date: Date) -> (Int, Int, Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func futureYear(_ offset: Int) -> Int {
        Calendar.current.component(.year, from: Date()) + offset
    }

    // MARK: - Positive cases

    @Test("Passport with explicit expiry date")
    func passportExpiry() throws {
        let year = futureYear(3)
        let text = """
        PASSPORT
        Surname: DOE
        Date of birth: 12 JAN 1985
        Date of expiry: 15 JUN \(year)
        """
        let result = try #require(DocumentExpiryParser.parse(text: text))
        #expect(result.documentType == "Passport")
        let (y, m, d) = ymd(result.expiryDate)
        #expect(y == year)
        #expect(m == 6)
        #expect(d == 15)
    }

    @Test("Passport with multilingual expiry label on previous line")
    func passportExpiryFromMultilingualLabelPreviousLine() throws {
        let expiryYear = futureYear(1)
        let text = """
        PASSPORT
        PASSEPORT
        PASAPORTE
        DATE OF BIRTH / DATE DE NAISSANCE / FECHA DE NACIMIENTO
        19 JAN 1987
        DATE OF ISSUE / DATE D'EMISSION / FECHA DE EMISION
        09 NOV 2011
        DATE OF EXPIRY / DATE D'EXPIRATION / FECHA DE VENCIMIENTO
        08 NOV \(expiryYear)
        """
        let result = try #require(DocumentExpiryParser.parse(text: text))
        #expect(result.documentType == "Passport")
        let (y, m, d) = ymd(result.expiryDate)
        #expect(y == expiryYear)
        #expect(m == 11)
        #expect(d == 8)
    }

    @Test("Payment card MM/YY is treated as end of month")
    func paymentCardMonthYear() throws {
        let yy = futureYear(2) % 100
        // 4111 1111 1111 1111 is the canonical Luhn-valid Visa test number.
        let text = "VISA  4111 1111 1111 1111  VALID THRU 08/\(yy)  CARDHOLDER NAME"
        let result = try #require(DocumentExpiryParser.parse(text: text))
        #expect(result.documentType == "Payment Card")
        let (y, m, _) = ymd(result.expiryDate)
        #expect(m == 8)
        #expect(y == futureYear(2))
    }

    @Test("Driver's license expiry detected")
    func driversLicense() throws {
        let year = futureYear(4)
        let text = "DRIVER LICENSE\nDOB 03/04/1990\nEXP 09/21/\(year)"
        let result = try #require(DocumentExpiryParser.parse(text: text))
        #expect(result.documentType == "Driver's License")
        let (y, _, _) = ymd(result.expiryDate)
        #expect(y == year)
    }

    // MARK: - Disambiguation

    @Test("Does not pick date of birth as expiry")
    func ignoresDateOfBirth() {
        // Only a birth date present, no expiry cue → no result.
        let text = "IDENTITY CARD\nName: Jane Doe\nDate of birth: 01 FEB 1992"
        #expect(DocumentExpiryParser.parse(text: text) == nil)
    }

    @Test("Picks expiry over issue date when both present")
    func prefersExpiryOverIssue() throws {
        let expYear = futureYear(5)
        let text = """
        PASSPORT
        Date of issue: 10 MAR 2020
        Date of expiry: 10 MAR \(expYear)
        """
        let result = try #require(DocumentExpiryParser.parse(text: text))
        let (y, _, _) = ymd(result.expiryDate)
        #expect(y == expYear)
    }

    // MARK: - Negative cases

    @Test("Unknown document type returns nil")
    func unknownTypeReturnsNil() {
        let text = "Just a grocery receipt total $12.40 valid thru never"
        #expect(DocumentExpiryParser.parse(text: text) == nil)
    }

    @Test("Empty or nil text returns nil")
    func emptyReturnsNil() {
        #expect(DocumentExpiryParser.parse(text: nil) == nil)
        #expect(DocumentExpiryParser.parse(text: "") == nil)
    }

    @Test("Implausibly old year is rejected")
    func implausibleYearRejected() {
        let text = "PASSPORT\nDate of expiry: 01 JAN 1970"
        #expect(DocumentExpiryParser.parse(text: text) == nil)
    }
}
