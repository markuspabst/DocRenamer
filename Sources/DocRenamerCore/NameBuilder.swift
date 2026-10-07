import Foundation

public enum NameBuilder {
    public static let unknownPart = "unknown"
    private static let separator = "_"
    private static let replacementForRejected = "-"

    /// Builds `yyyy-mm-dd_sender_type[_article].pdf`. Missing sender/type
    /// become `unknown`; a missing or blank article is omitted.
    public static func fileName(date: DocumentDate, sender: String?, type: String?, article: String? = nil) -> String {
        var parts = [date.formatted, sanitize(sender), sanitize(type)]
        if let article, article.contains(where: \.isLetter) {
            parts.append(sanitize(article))
        }
        return parts.joined(separator: separator) + ".pdf"
    }

    /// Keeps letters, digits and `-`; collapses everything else (spaces,
    /// path separators, `_`) into `-` so a part can never alter the layout
    /// of the name or escape the directory.
    private static func sanitize(_ part: String?) -> String {
        guard let part else { return unknownPart }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        var result = ""
        for scalar in part.unicodeScalars {
            let character = allowed.contains(scalar) ? String(scalar) : replacementForRejected
            if character == replacementForRejected, result.hasSuffix(replacementForRejected) {
                continue
            }
            result += character
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? unknownPart : trimmed
    }
}
