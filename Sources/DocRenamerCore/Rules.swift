import Foundation

/// Maps a display name to the keywords that identify it in document text.
public struct Rule: Codable, Equatable {
    public let name: String
    public let keywords: [String]

    public init(name: String, keywords: [String]) {
        self.name = name
        self.keywords = keywords
    }
}

public struct Rules: Codable, Equatable {
    public let senders: [Rule]
    public let types: [Rule]

    public init(senders: [Rule], types: [Rule]) {
        self.senders = senders
        self.types = types
    }

    /// Returns a copy with `keyword` registered for the sender `name`.
    /// Extends an existing sender (matched case-insensitively by name)
    /// instead of creating a duplicate.
    public func addingSender(_ name: String, keyword: String) -> Rules {
        guard let index = senders.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) else {
            return Rules(senders: senders + [Rule(name: name, keywords: [keyword])], types: types)
        }

        let existing = senders[index]
        guard !existing.keywords.contains(where: { $0.lowercased() == keyword.lowercased() }) else {
            return self
        }

        var updated = senders
        updated[index] = Rule(name: existing.name, keywords: existing.keywords + [keyword])
        return Rules(senders: updated, types: types)
    }

    /// Returns the configured type name equal to `name` (ignoring case and
    /// surrounding whitespace), or nil. Guards against invented types.
    public func knownTypeName(_ name: String?) -> String? {
        guard let name else { return nil }

        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return types.first { $0.name.lowercased() == wanted }?.name
    }
}

public enum RuleMatcher {
    /// Returns the name of the rule whose keyword appears earliest in `text`.
    /// Letterheads and titles sit at the top of a document, so the earliest
    /// hit is the best guess. Case and punctuation are ignored.
    public static func firstMatch(_ rules: [Rule], in text: String) -> String? {
        let haystack = normalized(text)
        var best: (name: String, offset: Int)?

        for rule in rules {
            for keyword in rule.keywords {
                let needle = normalized(keyword)
                guard !needle.isEmpty, let range = haystack.range(of: needle) else { continue }
                let offset = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
                if best == nil || offset < best!.offset {
                    best = (rule.name, offset)
                }
            }
        }
        return best?.name
    }

    /// Whether `keyword` would match `text` in `firstMatch`.
    public static func contains(_ text: String, keyword: String) -> Bool {
        let needle = normalized(keyword)
        return !needle.isEmpty && normalized(text).contains(needle)
    }

    /// Lowercases and turns every run of non-alphanumeric characters into one
    /// space, so "Zukunft.Coburg.Digital" equals "zukunft coburg digital".
    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
