import XCTest
@testable import DocRenamerCore

final class DateExtractorTests: XCTestCase {
    func testGermanNumericDate() {
        XCTAssertEqual(DateExtractor.extract(from: "Berlin, 3.2.2024"),
                       DocumentDate(year: 2024, month: 2, day: 3))
    }

    func testDayFirstDateWithHyphens() {
        XCTAssertEqual(DateExtractor.extract(from: "Rechnungsdatum: 24-08-2026"),
                       DocumentDate(year: 2026, month: 8, day: 24))
    }

    func testIsoDate() {
        XCTAssertEqual(DateExtractor.extract(from: "Issued 2023-11-30"),
                       DocumentDate(year: 2023, month: 11, day: 30))
    }

    func testGermanMonthName() {
        XCTAssertEqual(DateExtractor.extract(from: "München, 12. März 2024"),
                       DocumentDate(year: 2024, month: 3, day: 12))
    }

    func testEnglishMonthName() {
        XCTAssertEqual(DateExtractor.extract(from: "5 Sept 2022"),
                       DocumentDate(year: 2022, month: 9, day: 5))
    }

    func testPrefersLabelledLine() {
        let text = "Zahlbar bis 14.04.2024\nRechnungsdatum: 01.04.2024"
        XCTAssertEqual(DateExtractor.extract(from: text),
                       DocumentDate(year: 2024, month: 4, day: 1))
    }

    func testPrefersInvoiceDateOverOtherLabelledDates() {
        let text = "Leistungsdatum: 21.09.2026\nKaufdatum: 20.11.2023\nRechnungsdatum: 25.09.2026"
        XCTAssertEqual(DateExtractor.extract(from: text),
                       DocumentDate(year: 2026, month: 9, day: 25))
    }

    func testFallsBackToFirstDate() {
        let text = "Brief vom 01.04.2024\nAntwort bis 14.04.2024"
        XCTAssertEqual(DateExtractor.extract(from: text),
                       DocumentDate(year: 2024, month: 4, day: 1))
    }

    func testRejectsInvalidDate() {
        XCTAssertNil(DateExtractor.extract(from: "31.02.2024"))
        XCTAssertNil(DateExtractor.extract(from: "01.13.2024"))
    }

    func testNoDate() {
        XCTAssertNil(DateExtractor.extract(from: "no date here"))
    }
}

final class RuleMatcherTests: XCTestCase {
    private let rules = [
        Rule(name: "Telekom", keywords: ["telekom"]),
        Rule(name: "Allianz", keywords: ["allianz", "versicherung"]),
    ]

    func testMatchesCaseInsensitive() {
        XCTAssertEqual(RuleMatcher.firstMatch(rules, in: "DEUTSCHE TELEKOM AG"), "Telekom")
    }

    func testEarliestMatchWins() {
        XCTAssertEqual(RuleMatcher.firstMatch(rules, in: "Allianz ... Telekom"), "Allianz")
    }

    func testIgnoresPunctuationAndCase() {
        let rules = [Rule(name: "ZCD", keywords: ["Zukunft Coburg Digital"])]
        XCTAssertEqual(RuleMatcher.firstMatch(rules, in: "Zukunft.Coburg.Digital GmbH"), "ZCD")
        XCTAssertTrue(RuleMatcher.contains("Zukunft.Coburg.Digital GmbH", keyword: "zukunft coburg digital"))
    }

    func testNoMatch() {
        XCTAssertNil(RuleMatcher.firstMatch(rules, in: "nothing"))
    }
}

final class NameBuilderTests: XCTestCase {
    private let date = DocumentDate(year: 2024, month: 3, day: 12)

    func testBuildsScheme() {
        XCTAssertEqual(NameBuilder.fileName(date: date, sender: "Telekom", type: "Rechnung"),
                       "2024-03-12_Telekom_Rechnung.pdf")
    }

    func testMissingPartsBecomeUnknown() {
        XCTAssertEqual(NameBuilder.fileName(date: date, sender: nil, type: nil),
                       "2024-03-12_unknown_unknown.pdf")
    }

    func testSanitizesSeparatorsAndPaths() {
        XCTAssertEqual(NameBuilder.fileName(date: date, sender: "../Evil/Co_Ltd", type: "a b"),
                       "2024-03-12_Evil-Co-Ltd_a-b.pdf")
    }
}

final class RulesTests: XCTestCase {
    private let rules = Rules(
        senders: [Rule(name: "Telekom", keywords: ["telekom"])],
        types: [])

    func testAddsNewSender() {
        let updated = rules.addingSender("Stadtwerke", keyword: "stadtwerke")
        XCTAssertEqual(updated.senders.last, Rule(name: "Stadtwerke", keywords: ["stadtwerke"]))
        XCTAssertEqual(updated.senders.count, 2)
    }

    func testExtendsExistingSenderCaseInsensitive() {
        let updated = rules.addingSender("TELEKOM", keyword: "t-systems")
        XCTAssertEqual(updated.senders, [Rule(name: "Telekom", keywords: ["telekom", "t-systems"])])
    }

    func testDoesNotDuplicateKeyword() {
        XCTAssertEqual(rules.addingSender("Telekom", keyword: "Telekom"), rules)
    }

    func testKnownTypeNameIsCanonicalized() {
        let typed = Rules(senders: [], types: [Rule(name: "Rechnung", keywords: ["rechnung"])])
        XCTAssertEqual(typed.knownTypeName("  rechnung "), "Rechnung")
    }

    func testUnknownTypeNameIsRejected() {
        let typed = Rules(senders: [], types: [Rule(name: "Rechnung", keywords: ["rechnung"])])
        XCTAssertNil(typed.knownTypeName("Mahnung"))
        XCTAssertNil(typed.knownTypeName(nil))
    }
}

final class SenderGuesserTests: XCTestCase {
    func testCompanyBeforeLegalForm() {
        let text = "manitu GmbH, Welvertstraße 2, 66606 St. Wendel\nHerrn\nMarkus Pabst"
        XCTAssertEqual(SenderGuesser.guess(from: text), "manitu")
    }

    func testMultiWordCompany() {
        XCTAssertEqual(SenderGuesser.guess(from: "Deutsche Telekom AG\nRechnung"), "Deutsche Telekom")
    }

    func testKeepsAtMostThreeWords() {
        XCTAssertEqual(SenderGuesser.guess(from: "Ihre Bestellung bei BSH Hausgeräte Service GmbH"),
                       "BSH Hausgeräte Service")
    }

    func testEarliestLegalFormWins() {
        XCTAssertEqual(SenderGuesser.guess(from: "Alpha GmbH\nBeta AG"), "Alpha")
    }

    func testReturnAddressLineBeatsRecipientCompany() {
        let text = "GLOBALINN\nHotel Global inn - Kleiststraße 46 - 38440 Wolfsburg\nCARIAD SE\nMajor-Hirst-Straße 7\n38442 Wolfsburg"
        XCTAssertEqual(SenderGuesser.guess(from: text), "Hotel Global inn")
    }

    func testReturnAddressStripsLegalForm() {
        XCTAssertEqual(SenderGuesser.guess(from: "Foo Bar GmbH, Weg 1, 12345 Berlin\nHerrn"), "Foo Bar")
    }

    func testHyphenInsideNameIsNotSeparator() {
        XCTAssertEqual(SenderGuesser.guess(from: "T-Systems, Weg 1, 12345 Berlin"), "T-Systems")
    }

    func testRecipientPostcodeLineIsNotASender() {
        let text = "Zukunft.Coburg.Digital GmbH\nMarkus Pabst\nKastanienallee 30\n96482 Ahorn, Bayern"
        XCTAssertEqual(SenderGuesser.guess(from: text), "Zukunft.Coburg.Digital")
    }

    func testNoLegalForm() {
        XCTAssertNil(SenderGuesser.guess(from: "Herr Markus Pabst, Kastanienallee 30"))
    }
}

final class ArticleGuesserTests: XCTestCase {
    func testLineItemAfterHeader() {
        let text = "Rechnung Nr. 1\nPos. Menge Beschreibung MwSt.-Satz Einzelpreis Gesamtpreis\n1 6 Paket Webhosting M (markuspabst.de)\nSumme netto"
        XCTAssertEqual(ArticleGuesser.guess(from: text), "Paket Webhosting M (markuspabst.de)")
    }

    func testSkipsColumnHeadersAndLabelLines() {
        let text = "Bezeichnung Menge\nEinzelpreis EUR\nGast: Pabst, Markus\nFrühstück Getränke\n1\n6,27"
        XCTAssertEqual(ArticleGuesser.guess(from: text), "Frühstück Getränke")
    }

    func testStripsQuantityAndPrice() {
        let text = "Beschreibung Menge Preis\n2 Laptop Pro 1.299,00 EUR"
        XCTAssertEqual(ArticleGuesser.guess(from: text), "Laptop Pro")
    }

    func testTruncatesAtWordBoundary() {
        let text = "Beschreibung Menge\n" + String(repeating: "Wort ", count: 30)
        XCTAssertLessThanOrEqual(ArticleGuesser.guess(from: text)?.count ?? 0, 50)
        XCTAssertEqual(ArticleGuesser.guess(from: text)?.hasSuffix("Wort"), true)
    }

    func testNoHeader() {
        XCTAssertNil(ArticleGuesser.guess(from: "Hallo\nWelt"))
    }
}

final class NameBuilderArticleTests: XCTestCase {
    func testAppendsArticle() {
        let date = DocumentDate(year: 2026, month: 1, day: 2)
        XCTAssertEqual(
            NameBuilder.fileName(date: date, sender: "manitu", type: "Rechnung", article: "Paket Webhosting M (x.de)"),
            "2026-01-02_manitu_Rechnung_Paket-Webhosting-M-x-de.pdf")
    }

    func testEmptyArticleIsOmitted() {
        let date = DocumentDate(year: 2026, month: 1, day: 2)
        XCTAssertEqual(NameBuilder.fileName(date: date, sender: "a", type: "b", article: "  "),
                       "2026-01-02_a_b.pdf")
    }
}
