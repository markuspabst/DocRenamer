import Foundation
import DocRenamerCore

/// Append-only JSON Lines file of confirmed results, one `Example` per line.
/// Holds excerpts of document text (may contain PII): kept in the user's
/// config directory with owner-only permissions.
enum ExampleLog {
    private static let relativePath = ".config/docrenamer/examples.jsonl"
    private static let ownerOnly: Int16 = 0o600

    private static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath)
    }

    /// Unreadable lines are skipped with a warning so one bad line cannot disable learning.
    static func load() -> [Example] {
        guard let data = FileManager.default.contents(atPath: url.path) else { return [] }

        let decoder = JSONDecoder()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return lines.compactMap { line in
            do {
                return try decoder.decode(Example.self, from: Data(line.utf8))
            } catch {
                FileHandle.standardError.write(Data("Skipping invalid line in \(url.path): \(error)\n".utf8))
                return nil
            }
        }
    }

    static func append(_ example: Example) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let line = try encoder.encode(example) + Data("\n".utf8)

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(
                atPath: url.path, contents: nil, attributes: [.posixPermissions: ownerOnly])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}
