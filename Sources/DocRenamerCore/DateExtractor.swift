import Foundation

public struct DocumentDate: Equatable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var formatted: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

public enum DateExtractor {
    private static let minYear = 1900
    private static let maxYear = 2100

    // Dates on lines with one of these labels are preferred over other dates,
    // e.g. to skip due or service dates on an invoice. Earlier tiers win.
    private static let labelTiers = [
        ["rechnungsdatum", "belegdatum", "invoice date", "ausstellungsdatum"],
        ["datum", "date"],
    ]

    private static let monthNumbers: [String: Int] = [
        "januar": 1, "jan": 1, "january": 1,
        "februar": 2, "feb": 2, "february": 2,
        "märz": 3, "maerz": 3, "mär": 3, "mrz": 3, "march": 3, "mar": 3,
        "april": 4, "apr": 4,
        "mai": 5, "may": 5,
        "juni": 6, "jun": 6, "june": 6,
        "juli": 7, "jul": 7, "july": 7,
        "august": 8, "aug": 8,
        "september": 9, "sep": 9, "sept": 9,
        "oktober": 10, "okt": 10, "october": 10, "oct": 10,
        "november": 11, "nov": 11,
        "dezember": 12, "dez": 12, "december": 12, "dec": 12,
    ]

    private static let numericDayFirst = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})[.-]\s?(\d{1,2})[.-]\s?(\d{4})\b"#)
    private static let isoDate = try! NSRegularExpression(
        pattern: #"\b(\d{4})-(\d{2})-(\d{2})\b"#)
    private static let namedMonth = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})\.?\s*([A-Za-zäöüÄÖÜ]{3,9})\.?\s+(\d{4})\b"#)

    /// Returns the document date: the first date on a line with the
    /// best-ranked label (see `labelTiers`), otherwise the first date in the text.
    public static func extract(from text: String) -> DocumentDate? {
        var firstByTier: [DocumentDate?] = Array(repeating: nil, count: labelTiers.count)
        var firstOverall: DocumentDate?

        for line in text.components(separatedBy: .newlines) {
            guard let date = firstDate(in: line) else { continue }

            let lowered = line.lowercased()
            if let tier = labelTiers.firstIndex(where: { $0.contains(where: lowered.contains) }),
               firstByTier[tier] == nil {
                firstByTier[tier] = date
            }
            if firstOverall == nil {
                firstOverall = date
            }
        }
        return firstByTier.compactMap { $0 }.first ?? firstOverall
    }

    private static func firstDate(in line: String) -> DocumentDate? {
        let candidates: [(offset: Int, date: DocumentDate)] = [
            match(numericDayFirst, in: line) { DocumentDate(year: $0[2], month: $0[1], day: $0[0]) },
            match(isoDate, in: line) { DocumentDate(year: $0[0], month: $0[1], day: $0[2]) },
            matchNamedMonth(in: line),
        ].compactMap { $0 }

        return candidates.min { $0.offset < $1.offset }?.date
    }

    private static func match(
        _ regex: NSRegularExpression,
        in line: String,
        build: ([Int]) -> DocumentDate
    ) -> (offset: Int, date: DocumentDate)? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)

        for result in regex.matches(in: line, range: range) {
            let numbers = (1..<result.numberOfRanges).compactMap {
                Int(nsLine.substring(with: result.range(at: $0)))
            }
            let date = build(numbers)
            if isValid(date) {
                return (result.range.location, date)
            }
        }
        return nil
    }

    private static func matchNamedMonth(in line: String) -> (offset: Int, date: DocumentDate)? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)

        for result in namedMonth.matches(in: line, range: range) {
            let monthWord = nsLine.substring(with: result.range(at: 2)).lowercased()
            guard
                let month = monthNumbers[monthWord],
                let day = Int(nsLine.substring(with: result.range(at: 1))),
                let year = Int(nsLine.substring(with: result.range(at: 3)))
            else { continue }

            let date = DocumentDate(year: year, month: month, day: day)
            if isValid(date) {
                return (result.range.location, date)
            }
        }
        return nil
    }

    private static func isValid(_ date: DocumentDate) -> Bool {
        guard (minYear...maxYear).contains(date.year) else { return false }
        guard (1...12).contains(date.month) else { return false }

        var components = DateComponents(year: date.year, month: date.month)
        components.calendar = Calendar(identifier: .gregorian)
        guard let monthStart = components.date,
              let days = components.calendar?.range(of: .day, in: .month, for: monthStart)
        else { return false }

        return days.contains(date.day)
    }
}
