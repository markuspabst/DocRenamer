# DocRenamer

Finder Quick Action that renames a PDF to `yyyy-mm-dd_sender_type.pdf`; invoices (type `Rechnung`) become `yyyy-mm-dd_sender_Rechnung_article.pdf`.

- Text: OCR (Apple Vision, German + English, first 2 pages, always) plus the PDF text layer.
- Date: first date on a "Rechnungsdatum"/"Belegdatum"/"Invoice date" line, else on a "Datum"/"Date" line, else the first date in the text, else the file creation date.
- Sender: the rule from `rules.json` whose keyword appears earliest in the text. Otherwise guessed from the return-address line ("Name - Street - 12345 City") or the company before the first legal form (GmbH, AG, KG, …).
- Unknown type gives `unknown`. Without a rule match, a dialog shows the guessed sender; confirm or edit it. The result is saved as a sender rule (keywords: guess and entered name, as far as they occur in the document text). Cancel or empty input uses the unconfirmed guess (or `unknown`). Saving rewrites `rules.json` with normalized formatting.
- Article (type `Rechnung` only): a dialog shows the first line item below the table header ("Beschreibung"/"Bezeichnung"/…); confirm, edit, or clear it to omit the article. Cancel or empty input omits it.
- On-device model (Apple Foundation Models, macOS 26+, Apple Intelligence enabled): fills what rules and text heuristics leave open. It proposes the sender (dialog default), the type (only names from `rules.json` are accepted) and the date (only if no date is found in the text). Rules always win. Without the model, behavior is unchanged; text never leaves the machine.
- Type and date confirmation: when no type rule matches, a dialog shows the model's type (or nothing); confirm, edit, or clear it (empty/cancel keeps the suggestion, or `unknown` if none). A new name is saved as a type, with a keyword if it occurs in the text. When no date is found in the text, a dialog shows the model's date or the file creation date (`tt.mm.jjjj` or `jjjj-mm-tt`).
- Learning: every run appends the first 400 characters of the text and the final sender, type and date to `~/.config/docrenamer/examples.jsonl` (mode 0600; contains document text, keep private). The three most similar past entries are given to the model as examples. Delete the file to reset.
- Existing files are never overwritten; a `-2`, `-3`, … suffix is added.

## Install

```sh
scripts/install.sh
```

Installs `~/.local/bin/docrenamer`, `~/.local/bin/docrenamer-action`, `~/Library/Services/Rename PDF.workflow` and, if absent, `~/.config/docrenamer/rules.json`.

Use: right-click a PDF in Finder → Quick Actions → Rename PDF. If it is not listed, enable it in System Settings → Keyboard → Keyboard Shortcuts → Services/Quick Actions. Files in Desktop/Documents may trigger a macOS permission prompt on first use.

## Rules

Edit `~/.config/docrenamer/rules.json` (see `rules.example.json`). Keywords are case-insensitive substrings.

## Develop

```sh
swift build
swift test
.build/debug/docrenamer file.pdf
```
