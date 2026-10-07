import Foundation
import FoundationModels

/// Raw, unvalidated fields suggested by the on-device language model.
struct LLMSuggestion {
    let sender: String?
    let type: String?
    let date: String?
}

/// Suggests sender, type and date with Apple's on-device model. Output is
/// untrusted: callers validate it before use. Text never leaves the machine.
enum LLMExtractor {
    // The on-device context window is small; letterhead and header data sit at the top.
    private static let maxTextCharacters = 6000

    private static let instructions = """
        You extract metadata from the text of a scanned document (German or English). \
        Answer only from the text. Leave a field empty if it is not clearly stated.
        """

    /// Returns nil when the model is unavailable or fails; the reason goes to stderr.
    static func extract(from text: String, allowedTypes: [String]) -> LLMSuggestion? {
        guard #available(macOS 26.0, *) else { return nil }
        guard SystemLanguageModel.default.isAvailable else {
            warn("On-device model unavailable: \(SystemLanguageModel.default.availability)")
            return nil
        }

        let result = ResultBox()
        let done = DispatchSemaphore(value: 0)
        Task {
            do {
                result.value = try await respond(to: text, allowedTypes: allowedTypes)
            } catch {
                warn("On-device extraction failed: \(error)")
            }
            done.signal()
        }
        done.wait()
        return result.value
    }

    @available(macOS 26.0, *)
    private static func respond(to text: String, allowedTypes: [String]) async throws -> LLMSuggestion {
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
            Allowed document types: \(allowedTypes.joined(separator: ", ")).

            Document text:
            \(text.prefix(maxTextCharacters))
            """
        let fields = try await session.respond(to: prompt, generating: ExtractedFields.self).content
        return LLMSuggestion(sender: fields.sender, type: fields.type, date: fields.date)
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}

private final class ResultBox: @unchecked Sendable {
    // Written once by the task before the semaphore is signalled, read after.
    var value: LLMSuggestion?
}

@available(macOS 26.0, *)
@Generable
struct ExtractedFields {
    @Guide(description: "Short name of the company or person that sent the document, without legal form")
    let sender: String?

    @Guide(description: "The best matching allowed document type, exactly as written; empty if none fits")
    let type: String?

    @Guide(description: "Date the document was issued as yyyy-mm-dd; not a due, service or period date")
    let date: String?
}
