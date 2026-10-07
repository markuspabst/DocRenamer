import Foundation

/// A past, user-confirmed result. `excerpt` is the start of the document text.
public struct Example: Codable, Equatable {
    public let excerpt: String
    public let sender: String?
    public let type: String?
    public let date: String?

    public init(excerpt: String, sender: String?, type: String?, date: String?) {
        self.excerpt = excerpt
        self.sender = sender
        self.type = type
        self.date = date
    }

    private static let excerptLength = 400

    /// The start of `text` with whitespace runs collapsed, as stored in examples.
    public static func excerpt(of text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(words.prefix(excerptLength))
    }
}

public enum ExampleSelector {
    private static let minTokenLength = 3

    /// Returns up to `limit` examples ordered by token overlap (Jaccard) with
    /// `text`, best first. Examples sharing no token are dropped.
    public static func mostSimilar(to text: String, in examples: [Example], limit: Int) -> [Example] {
        let target = tokens(of: text)

        let scored: [(example: Example, score: Double)] = examples.map { example in
            let other = tokens(of: example.excerpt)
            let union = target.union(other).count
            let score = union == 0 ? 0 : Double(target.intersection(other).count) / Double(union)
            return (example, score)
        }

        return scored
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.example)
    }

    private static func tokens(of text: String) -> Set<String> {
        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(words.filter { $0.count >= minTokenLength })
    }
}
