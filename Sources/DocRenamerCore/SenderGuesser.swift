import Foundation

public enum SenderGuesser {
    private static let maxWords = 3
    private static let maxNameLength = 60
    private static let legalForms = ["GmbH", "mbH", "AG", "KG", "UG", "SE", "GbR", "e\\.V\\.", "Ltd", "Inc"]
    private static let legalFormAlternatives = legalForms.joined(separator: "|")

    // Up to `maxWords` words directly before a legal form, on a single line.
    private static let companyBeforeLegalForm = try! NSRegularExpression(
        pattern: "((?:[\\p{L}\\p{N}&.-]+[ \\t]+){0,\(maxWords - 1)}[\\p{L}\\p{N}&.-]+)"
            + "[ \\t]+(?:\(legalFormAlternatives))(?=[\\s,.;]|$)")

    private static let trailingLegalForm = try! NSRegularExpression(
        pattern: "\\s+(?:\(legalFormAlternatives))\\.?$")

    // German Absenderzeile: "Name - Street 1 - 12345 City" or "Name, Street 1, 12345 City".
    private static let postcodeWithCity = try! NSRegularExpression(pattern: "\\b\\d{5}\\s+\\p{Lu}\\p{L}+")
    private static let postcode = try! NSRegularExpression(pattern: "\\b\\d{5}\\b")
    private static let separator = try! NSRegularExpression(pattern: "\\s[-–]\\s|,\\s")

    /// Guesses the sender for documents without a matching rule: first the
    /// return-address line above the recipient, then the company name in
    /// front of the first legal form (GmbH, AG, …).
    public static func guess(from text: String) -> String? {
        returnAddressSender(in: text) ?? companyBeforeLegalForm(in: text)
    }

    /// The recipient block also contains a company in business letters, so the
    /// return-address line is more reliable than the first legal form.
    private static func returnAddressSender(in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            guard postcodeWithCity.firstMatch(in: line, range: range) != nil,
                  let split = separator.firstMatch(in: line, range: range)
            else { continue }

            let name = nsLine.substring(to: split.range.location).trimmingCharacters(in: .whitespaces)
            let stripped = trailingLegalForm.stringByReplacingMatches(
                in: name, range: NSRange(location: 0, length: (name as NSString).length), withTemplate: "")
            // A name containing a postcode is the recipient's "12345 City, Region" line.
            let strippedRange = NSRange(location: 0, length: (stripped as NSString).length)
            if (1...maxNameLength).contains(stripped.count),
               postcode.firstMatch(in: stripped, range: strippedRange) == nil {
                return stripped
            }
        }
        return nil
    }

    private static func companyBeforeLegalForm(in text: String) -> String? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = companyBeforeLegalForm.firstMatch(in: text, range: range) else { return nil }
        return nsText.substring(with: match.range(at: 1))
    }
}
