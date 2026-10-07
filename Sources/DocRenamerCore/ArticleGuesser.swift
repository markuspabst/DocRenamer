import Foundation

public enum ArticleGuesser {
    private static let maxLength = 50
    private static let maxLinesAfterHeader = 8
    private static let minLetters = 3

    private static let descriptionHeaders: Set<String> = [
        "beschreibung", "bezeichnung", "artikel", "position", "leistung", "produkt", "description", "item",
    ]
    private static let columnWords: Set<String> = [
        "pos", "menge", "anzahl", "preis", "einzelpreis", "gesamtpreis", "gesamt", "betrag", "eur",
        "mwst", "satz", "summe", "netto", "brutto", "nr", "stk", "price", "qty", "amount", "total",
    ]

    private static let leadingQuantity = try! NSRegularExpression(
        pattern: #"^(?:\d+(?:[.,]\d+)?\s+)+(?:(?:stk|x)\.?\s+)?"#, options: .caseInsensitive)
    private static let trailingPrices = try! NSRegularExpression(
        pattern: #"(?:\s+-?[\d.]+,\d{2}\s*(?:€|eur)?)+$"#, options: .caseInsensitive)

    /// Guesses the article of an invoice: the first line item below the
    /// table header (a line with a description column and other column titles).
    /// Layouts vary, so callers should let the user confirm the result.
    public static func guess(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        guard let header = lines.firstIndex(where: isTableHeader) else { return nil }

        for line in lines.dropFirst(header + 1).prefix(maxLinesAfterHeader) {
            if let article = lineItem(from: line) {
                return truncated(article)
            }
        }
        return nil
    }

    private static func words(in line: String) -> [String] {
        line.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }

    private static func isTableHeader(_ line: String) -> Bool {
        guard !line.contains(":") else { return false }
        let lineWords = words(in: line)
        return lineWords.contains(where: descriptionHeaders.contains)
            && lineWords.contains(where: columnWords.contains)
    }

    private static func lineItem(from line: String) -> String? {
        guard !line.contains(":") else { return nil }

        var item = line.trimmingCharacters(in: .whitespaces)
        item = replacing(leadingQuantity, in: item)
        item = replacing(trailingPrices, in: item)

        guard item.unicodeScalars.filter(CharacterSet.letters.contains).count >= minLetters,
              item.first?.isLetter == true,
              !words(in: item).contains(where: columnWords.contains)
        else { return nil }
        return item
    }

    private static func replacing(_ regex: NSRegularExpression, in text: String) -> String {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > maxLength else { return text }
        let cut = String(text.prefix(maxLength))
        guard let lastSpace = cut.lastIndex(of: " ") else { return cut }
        return String(cut[..<lastSpace])
    }
}
