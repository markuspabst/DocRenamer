import Foundation
import PDFKit
import Vision
import DocRenamerCore

private let rulesRelativePath = ".config/docrenamer/rules.json"
private let ocrPageLimit = 2
private let pdfPointsPerInch: CGFloat = 72
private let ocrDpi: CGFloat = 300
private let invoiceTypeName = "Rechnung"  // Only this type gets an article in the name.
private let ocrLanguages = ["de-DE", "en-US"]

private enum RenamerError: LocalizedError {
    case notPDF(String)
    case unreadable(String)
    case rulesMissing(String)
    case rulesInvalid(String, Error)
    case ocrFailed(String, Error)
    case rulesNotSaved(String, Error)

    var errorDescription: String? {
        switch self {
        case .notPDF(let path): return "\(path): not a PDF"
        case .unreadable(let path): return "\(path): cannot open PDF"
        case .rulesMissing(let path): return "Rules file not found: \(path)"
        case .rulesInvalid(let path, let cause): return "Invalid rules file \(path): \(cause)"
        case .ocrFailed(let path, let cause): return "\(path): OCR failed: \(cause)"
        case .rulesNotSaved(let path, let cause): return "Could not save rules to \(path): \(cause)"
        }
    }
}

private let senderPromptScript = [
    "on run argv",
    "try",
    "set answer to display dialog (item 1 of argv) default answer (item 2 of argv) buttons {\"Überspringen\", \"OK\"} "
        + "default button \"OK\" cancel button \"Überspringen\" with title \"DocRenamer\"",
    "return text returned of answer",
    "on error",
    "return \"\"",
    "end try",
    "end run",
]

private func rulesURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(rulesRelativePath)
}

private func saveRules(_ rules: Rules) throws {
    let url = rulesURL()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
        try encoder.encode(rules).write(to: url, options: .atomic)
    } catch {
        throw RenamerError.rulesNotSaved(url.path, error)
    }
}

/// Asks the user via a macOS dialog, prefilled with `suggestion`.
/// Returns nil on cancel, empty input or dialog failure.
private func prompt(_ message: String, suggestion: String?) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = senderPromptScript.flatMap { ["-e", $0] } + [message, suggestion ?? ""]

    let pipe = Pipe()
    process.standardOutput = pipe
    do {
        try process.run()
    } catch {
        FileHandle.standardError.write(Data("Cannot show dialog: \(error)\n".utf8))
        return nil
    }

    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let answer = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return answer.isEmpty ? nil : answer
}

private func loadRules() throws -> Rules {
    let url = rulesURL()
    guard let data = FileManager.default.contents(atPath: url.path) else {
        throw RenamerError.rulesMissing(url.path)
    }
    do {
        return try JSONDecoder().decode(Rules.self, from: data)
    } catch {
        throw RenamerError.rulesInvalid(url.path, error)
    }
}

private func ocrText(of page: PDFPage) throws -> String {
    let scale = ocrDpi / pdfPointsPerInch
    let bounds = page.bounds(for: .mediaBox)
    let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

    let image = page.thumbnail(of: size, for: .mediaBox)
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return ""
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ocrLanguages
    request.usesLanguageCorrection = true

    try VNImageRequestHandler(cgImage: cgImage).perform([request])

    let observations = request.results ?? []
    return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}

/// OCR text of the first pages followed by the embedded text layer. OCR always
/// runs: scans may carry a poor text layer, and letterheads/logos are often
/// images only. OCR text comes first so the letterhead wins "earliest match".
private func extractText(from document: PDFDocument, path: String) throws -> String {
    var parts: [String] = []
    for index in 0..<min(document.pageCount, ocrPageLimit) {
        guard let page = document.page(at: index) else { continue }
        do {
            parts.append(try ocrText(of: page))
        } catch {
            throw RenamerError.ocrFailed(path, error)
        }
    }
    parts.append(document.string ?? "")
    return parts.joined(separator: "\n")
}

private func creationDate(of url: URL) -> DocumentDate {
    let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return DocumentDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
}

/// Never overwrites: appends `-2`, `-3`, … before the extension on collision.
private func uniqueDestination(for name: String, in directory: URL, source: URL) -> URL {
    let fileManager = FileManager.default
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension

    var candidate = directory.appendingPathComponent(name)
    var counter = 2
    while fileManager.fileExists(atPath: candidate.path), candidate != source {
        candidate = directory.appendingPathComponent("\(base)-\(counter).\(ext)")
        counter += 1
    }
    return candidate
}

/// Resolves the sender via rules. Otherwise guesses it from the text and lets
/// the user confirm or change it in a dialog; the result is stored as a rule
/// (keywords: guess and answer, as far as they occur in the text) so later
/// documents of that sender match. Cancel falls back to the unconfirmed guess.
/// The guess is the model's suggestion if present, else the heuristic one.
private func resolveSender(in text: String, fileName: String, suggestion: String?, rules: inout Rules) -> String? {
    if let sender = RuleMatcher.firstMatch(rules.senders, in: text) {
        return sender
    }

    let guess = suggestion ?? SenderGuesser.guess(from: text)
    guard let answer = prompt("Absender für \(fileName) bestätigen oder ändern:", suggestion: guess) else { return guess }

    let keywords = [guess, answer].compactMap { $0 }.filter { RuleMatcher.contains(text, keyword: $0) }
    guard !keywords.isEmpty else {
        print("Rule not saved: neither \"\(answer)\" nor the guess occurs in the document text. Add a keyword to rules.json.")
        return answer
    }

    for keyword in keywords {
        rules = rules.addingSender(answer, keyword: keyword)
    }
    do {
        try saveRules(rules)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    }
    return answer
}

/// Invoices get the article in the name. Cancel or empty input omits it.
private func resolveArticle(in text: String, fileName: String) -> String? {
    prompt("Artikel für \(fileName) bestätigen oder ändern (leer = weglassen):",
           suggestion: ArticleGuesser.guess(from: text))
}

private func rename(path: String, rules: inout Rules) throws -> String {
    let source = URL(fileURLWithPath: path)
    guard source.pathExtension.lowercased() == "pdf" else { throw RenamerError.notPDF(path) }
    guard let document = PDFDocument(url: source) else { throw RenamerError.unreadable(path) }

    let text = try extractText(from: document, path: path)
    let ruleType = RuleMatcher.firstMatch(rules.types, in: text)
    let textDate = DateExtractor.extract(from: text)
    let hasSenderRule = RuleMatcher.firstMatch(rules.senders, in: text) != nil

    // Rules and text heuristics win; the model only fills what they leave open.
    let needsModel = ruleType == nil || textDate == nil || !hasSenderRule
    let suggestion = needsModel
        ? LLMExtractor.extract(from: text, allowedTypes: rules.types.map(\.name))
        : nil

    let sender = resolveSender(
        in: text, fileName: source.lastPathComponent, suggestion: suggestion?.sender, rules: &rules)
    let type = ruleType ?? rules.knownTypeName(suggestion?.type)
    let isInvoice = type?.lowercased() == invoiceTypeName.lowercased()

    let modelDate = suggestion?.date.flatMap(DateExtractor.extract(from:))
    let name = NameBuilder.fileName(
        date: textDate ?? modelDate ?? creationDate(of: source),
        sender: sender,
        type: type,
        article: isInvoice ? resolveArticle(in: text, fileName: source.lastPathComponent) : nil
    )

    let destination = uniqueDestination(
        for: name, in: source.deletingLastPathComponent(), source: source)
    if destination != source {
        try FileManager.default.moveItem(at: source, to: destination)
    }
    return destination.lastPathComponent
}

private func run(arguments: [String]) -> Int32 {
    var rules: Rules
    do {
        rules = try loadRules()
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        return 1
    }

    var failed = false
    for path in arguments {
        do {
            let newName = try rename(path: path, rules: &rules)
            print("\((path as NSString).lastPathComponent) -> \(newName)")
        } catch {
            failed = true
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        }
    }
    return failed ? 1 : 0
}

exit(run(arguments: Array(CommandLine.arguments.dropFirst())))
