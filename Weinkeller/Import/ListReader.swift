import Foundation
import PDFKit
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Ein Eingang für jede Art von Weinliste: Excel, Word, PDF, Text, CSV — und Fotos.
///
/// Wer einen Keller hat, hat seine Liste irgendwo: im Excel, im Word, in einer Notiz, auf Papier.
/// Alles endet hier als `CSV.Table`, damit Spaltenzuordnung und Vorschau für jede Quelle
/// gleich funktionieren. Die Leser raten nur vor — zuordnen und prüfen tut der Besitzer.
enum ListReader {

    enum Source: String {
        case csv, excel, word, pdf, text, photo

        var label: String {
            switch self {
            case .csv:   return "CSV"
            case .excel: return "Excel"
            case .word:  return "Word"
            case .pdf:   return "PDF"
            case .text:  return "Text"
            case .photo: return "Foto"
            }
        }
    }

    struct Loaded {
        var table: CSV.Table
        var source: Source
    }

    /// Dateitypen für den Dateiauswahl-Dialog. Alte Formate sind absichtlich dabei:
    /// Lieber eine klare Anleitung zeigen als die Datei ausgegraut lassen.
    static var importableTypes: [UTType] {
        let byExtension = ["xlsx", "xlsm", "xls", "docx", "doc", "numbers", "pages", "ods", "odt", "tsv"]
            .compactMap { UTType(filenameExtension: $0) }
        return [.commaSeparatedText, .tabSeparatedText, .plainText, .text, .pdf, .rtf, .html,
                .spreadsheet] + byExtension
    }

    // MARK: - Datei

    static func table(from url: URL) throws -> Loaded {
        // Dateien aus der Dateien-App liegen ausserhalb der App — erst Zugriff holen.
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        // Numbers und Pages sind manchmal Ordner („Pakete") — die kann man gar nicht als Datei lesen.
        if ext == "numbers" { throw ListReaderError.numbers }
        if ext == "pages" { throw ListReaderError.pages }

        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ListReaderError.unreadable }
        guard !data.isEmpty else { throw ListReaderError.empty }

        let loaded = try table(from: data, fileExtension: ext)
        guard !loaded.table.rows.isEmpty else { throw ListReaderError.empty }
        return loaded
    }

    /// Entscheidet am Inhalt, nicht nur an der Endung — umbenannte Dateien und
    /// Mail-Anhänge ohne Endung sind häufig.
    static func table(from data: Data, fileExtension ext: String) throws -> Loaded {
        let head = [UInt8](data.prefix(8))

        // ZIP: Excel, Word, Numbers, LibreOffice — erst am Inhalt erkennbar.
        if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            guard let zip = ZipArchive(data: data) else { throw ListReaderError.damaged }
            if zip.contains("xl/workbook.xml") || zip.contains("xl/worksheets/sheet1.xml") {
                guard let rows = try? XLSXReader.rows(from: zip) else { throw ListReaderError.damaged }
                return Loaded(table: ensureHeader(rows), source: .excel)
            }
            if zip.contains("word/document.xml") {
                guard let content = try? DOCXReader.read(from: zip) else { throw ListReaderError.damaged }
                switch content {
                case .table(let rows): return Loaded(table: ensureHeader(rows), source: .word)
                case .lines(let lines): return Loaded(table: table(fromLines: lines), source: .word)
                }
            }
            if zip.names.contains(where: { $0.hasPrefix("Index/") }) {
                throw ext == "pages" ? ListReaderError.pages : ListReaderError.numbers
            }
            if zip.contains("content.xml") { throw ListReaderError.openDocument }
            throw ListReaderError.unsupported
        }

        // Altes Office-Format (vor 2007): xls und doc sehen von aussen gleich aus.
        if head.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) {
            throw ext == "doc" ? ListReaderError.oldWord : ListReaderError.oldExcel
        }
        if head.starts(with: Array("%PDF".utf8)) {
            return Loaded(table: try pdfTable(data), source: .pdf)
        }
        if head.starts(with: Array("{\\rtf".utf8)) || ext == "rtf" {
            return Loaded(table: table(fromLines: FreeTextList.splitLines(try rtfText(data)), allowComma: false),
                          source: .text)
        }

        switch ext {
        case "xls": throw ListReaderError.oldExcel
        case "doc": throw ListReaderError.oldWord
        case "ods", "odt": throw ListReaderError.openDocument
        case "xlsx", "xlsm", "docx": throw ListReaderError.damaged
        default: break
        }

        guard let text = decodeText(data) else { throw ListReaderError.unreadable }
        if ext == "html" || ext == "htm" || looksLikeHTML(text) {
            return Loaded(table: table(fromLines: FreeTextList.splitLines(htmlText(text))), source: .text)
        }
        // Bei .csv ist das Komma ein echtes Trennzeichen, in einer Notiz meist nicht.
        let isCSV = ext == "csv" || ext == "tsv"
        let lines = FreeTextList.splitLines(text)
        if let separator = FreeTextList.delimiter(in: lines, allowComma: isCSV) {
            return Loaded(table: delimitedTable(text, separator: separator), source: isCSV ? .csv : .text)
        }
        return Loaded(table: FreeTextList.table(fromLines: lines), source: isCSV ? .csv : .text)
    }

    // MARK: - Eingefügter Text

    static func table(fromText text: String) -> CSV.Table {
        table(fromLines: FreeTextList.splitLines(text))
    }

    private static func table(fromLines lines: [String], allowComma: Bool = false) -> CSV.Table {
        if let separator = FreeTextList.delimiter(in: lines, allowComma: allowComma) {
            return delimitedTable(lines.joined(separator: "\n"), separator: separator)
        }
        return FreeTextList.table(fromLines: lines)
    }

    private static func delimitedTable(_ text: String, separator: Character) -> CSV.Table {
        let parsed = CSV.parse(text, separator: separator)
        return ensureHeader([parsed.header] + parsed.rows)
    }

    // MARK: - Kopfzeile

    /// Nicht jede Liste hat eine Kopfzeile. Beginnt die Tabelle direkt mit einem Wein, erfinden
    /// wir die Spaltennamen aus dem Inhalt — sonst würde der erste Wein zur Überschrift und
    /// ginge beim Import verloren.
    static func ensureHeader(_ rows: [[String]]) -> CSV.Table {
        var rows = tidy(rows)
        guard !rows.isEmpty else { return CSV.Table(header: [], rows: []) }

        // Kopfzeile unter einem Titel („Weinkeller Inventar 2024") suchen: die erste Zeile
        // unter den obersten zehn, in der mindestens zwei Spaltennamen stehen.
        if let headerIndex = rows.prefix(10).firstIndex(where: { hintCount($0) >= 2 && !$0.contains(where: isNumericCell) }) {
            rows.removeFirst(headerIndex)
            return dropEmptyColumns(CSV.Table(header: rows[0], rows: Array(rows.dropFirst())))
        }
        // Titelzeilen mit nur einer Zelle über einer breiteren Tabelle weglassen.
        while rows.count > 1, filled(rows[0]) == 1, filled(rows[1]) >= 2 { rows.removeFirst() }

        // Eine Zelle, die nur aus einer Zahl besteht („2018", „24.50"), steht in keiner Kopfzeile.
        // Bekannte Wörter allein reichen nicht: „Château Margaux" enthält das Stichwort „château".
        let first = rows[0]
        guard first.contains(where: isNumericCell) else {
            return dropEmptyColumns(CSV.Table(header: first, rows: Array(rows.dropFirst())))
        }
        return dropEmptyColumns(CSV.Table(header: guessHeader(rows), rows: rows))
    }

    private static let hintWords: [String] = WineImport.Field.allCases
        .flatMap(\.hints).map(TextMatching.normalize)

    /// Zellen, die wie ein Spaltenname aussehen: kurz und mit einem bekannten Wort.
    private static func hintCount(_ row: [String]) -> Int {
        row.filter { cell in
            let words = TextMatching.normalize(cell).split(separator: " ").map(String.init)
            guard !words.isEmpty, words.count <= 4, !isNumericCell(cell) else { return false }
            // Kurze Stichwörter („art", „vin") nur als ganzes Wort, sonst trifft „Landwein" auf „land".
            return hintWords.contains { hint in
                words.contains { hint.count >= 5 ? $0.hasPrefix(hint) : $0 == hint }
            }
        }.count
    }

    private static func filled(_ row: [String]) -> Int { row.filter { !$0.isEmpty }.count }

    /// „2018", „3", „24.50", „CHF 24.50", „18.–", „6x"
    static func isNumericCell(_ cell: String) -> Bool {
        let t = cell.trimmingCharacters(in: .whitespaces)
        guard t.contains(where: \.isNumber) else { return false }
        let stripped = t.replacingOccurrences(of: #"(?i)^(chf|fr\.?|sfr\.?|eur|€)\s*|\s*(chf|fr\.?|x|fl\.?|stk\.?)$"#,
                                              with: "", options: .regularExpression)
        return stripped.range(of: #"^[\d'’.,\s]*[\d][\d'’.,\s]*[-–—]*$"#, options: .regularExpression) != nil
    }

    private static func guessHeader(_ rows: [[String]]) -> [String] {
        let width = rows.map(\.count).max() ?? 0
        var header = (0..<width).map { "Spalte \($0 + 1)" }
        var taken = Set<String>()

        func values(_ col: Int) -> [String] {
            rows.compactMap { col < $0.count && !$0[col].isEmpty ? $0[col] : nil }
        }
        func share(_ col: Int, _ test: (String) -> Bool) -> Double {
            let v = values(col)
            return v.isEmpty ? 0 : Double(v.filter(test).count) / Double(v.count)
        }
        func assign(_ col: Int, _ title: String) {
            guard !taken.contains(title), header[col].hasPrefix("Spalte") else { return }
            header[col] = title
            taken.insert(title)
        }
        func number(_ s: String) -> Double? {
            let cleaned = s.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
            return Double(cleaned.hasSuffix(".") ? String(cleaned.dropLast()) : cleaned)
        }

        let columns = Array(0..<width)
        for col in columns where share(col, { $0.trimmingCharacters(in: .whitespaces).range(of: #"^(19[5-9]\d|20[0-4]\d)$"#, options: .regularExpression) != nil }) >= 0.6 {
            assign(col, "Jahrgang")
        }
        for col in columns where share(col, { FreeTextList.wineType(in: $0) != nil && $0.count <= 20 }) >= 0.6 {
            assign(col, "Art")
        }

        // Zahlenspalten: ganze kleine Zahlen sind Flaschen, Kommazahlen oder grosse Beträge Preise.
        // Bei zwei ganzzahligen Spalten ist die mit den kleineren Werten die Anzahl.
        let numeric = columns.filter { header[$0].hasPrefix("Spalte") && share($0, isNumericCell) >= 0.6 }
        func median(_ col: Int) -> Double {
            let v = values(col).compactMap(number).sorted()
            return v.isEmpty ? 0 : v[v.count / 2]
        }
        func isCountLike(_ col: Int) -> Bool {
            share(col, { s in
                guard let n = number(s), n == n.rounded(), !s.contains(where: { ".,-–—".contains($0) }) else { return false }
                return n >= 1 && n <= 60
            }) >= 0.8
        }
        let countCandidates = numeric.filter(isCountLike).sorted { median($0) < median($1) }
        if let col = countCandidates.first, median(col) <= 12 || numeric.count >= 2 { assign(col, "Anzahl") }
        for col in numeric where header[col].hasPrefix("Spalte") { assign(col, "Preis") }

        // Name: die Textspalte mit den längsten Einträgen.
        let text = columns.filter { header[$0].hasPrefix("Spalte") }
        if let col = text.max(by: { avgLength($0, values) < avgLength($1, values) }),
           avgLength(col, values) > 0 {
            assign(col, "Name")
        }
        return header
    }

    private static func avgLength(_ col: Int, _ values: (Int) -> [String]) -> Double {
        let v = values(col).filter { $0.contains(where: \.isLetter) }
        return v.isEmpty ? 0 : Double(v.reduce(0) { $0 + $1.count }) / Double(v.count)
    }

    /// Zellen trimmen, leere Zeilen und Summenzeilen weg, alle Zeilen gleich breit.
    static func tidy(_ rows: [[String]]) -> [[String]] {
        let cleaned = rows
            .map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { row in
                guard let first = row.first(where: { !$0.isEmpty }) else { return false }
                let word = TextMatching.normalize(first).split(separator: " ").first.map(String.init) ?? ""
                return !["total", "summe", "gesamt", "gesamttotal"].contains(word)
            }
        let width = cleaned.map(\.count).max() ?? 0
        return cleaned.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    /// Spalten ohne Titel und ohne Inhalt — Excel-Lücken — sind für die Zuordnung nur Rauschen.
    private static func dropEmptyColumns(_ table: CSV.Table) -> CSV.Table {
        let width = max(table.header.count, table.rows.map(\.count).max() ?? 0)
        let keep = (0..<width).filter { col in
            (col < table.header.count && !table.header[col].isEmpty)
                || table.rows.contains { col < $0.count && !$0[col].isEmpty }
        }
        func pick(_ row: [String]) -> [String] { keep.map { $0 < row.count ? row[$0] : "" } }
        return CSV.Table(header: pick(table.header), rows: table.rows.map(pick))
    }

    // MARK: - Text aus Dateien

    /// UTF-8, UTF-16 mit BOM, dann die Windows-Codepage — ältere Excel-Versionen schreiben die.
    static func decodeText(_ data: Data) -> String? {
        let b = [UInt8](data.prefix(3))
        if b.starts(with: [0xFF, 0xFE]) || b.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func pdfTable(_ data: Data) throws -> CSV.Table {
        guard let document = PDFDocument(data: data) else { throw ListReaderError.unreadable }
        if document.isLocked { throw ListReaderError.pdfLocked }
        let text = document.string ?? ""
        // Ein eingescanntes Blatt hat keinen Text, nur ein Bild.
        guard text.contains(where: \.isLetter) else { throw ListReaderError.pdfWithoutText }
        return table(fromLines: FreeTextList.splitLines(text))
    }

    private static func rtfText(_ data: Data) throws -> String {
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil) else { throw ListReaderError.unreadable }
        return attributed.string
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let start = text.prefix(500).lowercased()
        return start.contains("<html") || start.contains("<!doctype html") || start.contains("<table")
    }

    /// HTML selber vereinfachen statt `NSAttributedString(.html)`: Der HTML-Import braucht
    /// WebKit und darf nur auf dem Hauptthread laufen — mitten im Laden hängt sonst die App.
    /// Tabellenzellen werden zu Tabs, damit die Spalten erhalten bleiben.
    static func htmlText(_ html: String) -> String {
        var t = html
        let steps: [(String, String)] = [
            (#"(?is)<(script|style|head)\b.*?</\1>"#, ""),
            (#"(?i)</t[dh]>\s*"#, "\t"),
            (#"(?i)<br\s*/?>|</(p|div|tr|li|h[1-6])>"#, "\n"),
            (#"(?s)<[^>]*>"#, ""),
            (#"\t+\n"#, "\n")
        ]
        for (pattern, replacement) in steps {
            t = t.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                        "&#39;": "'", "&apos;": "'", "&ndash;": "–", "&mdash;": "—", "&euro;": "€",
                        "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü",
                        "&eacute;": "é", "&egrave;": "è", "&ecirc;": "ê", "&agrave;": "à", "&acirc;": "â",
                        "&ocirc;": "ô", "&icirc;": "î", "&ccedil;": "ç", "&Eacute;": "É"]
        for (entity, char) in entities { t = t.replacingOccurrences(of: entity, with: char) }
        // Numerische Zeichen wie &#233; (é)
        if let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
                guard let whole = Range(m.range, in: t), let hexR = Range(m.range(at: 1), in: t),
                      let numR = Range(m.range(at: 2), in: t),
                      let code = UInt32(t[numR], radix: t[hexR].isEmpty ? 10 : 16),
                      let scalar = Unicode.Scalar(code) else { continue }
                t.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return t
    }
}

// MARK: - Fehler

enum ListReaderError: LocalizedError {
    case unreadable, empty, damaged, unsupported
    case oldExcel, oldWord, numbers, pages, openDocument
    case pdfLocked, pdfWithoutText
    case nothingRecognized

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Die Datei lässt sich nicht öffnen."
        case .empty:
            return "In der Datei steht keine Weinliste, die sich lesen lässt."
        case .damaged:
            return "Die Datei scheint beschädigt zu sein. Öffne sie am Computer und speichere sie neu."
        case .unsupported:
            return "Diese Art Datei kennt die App nicht. Es gehen Excel, Word, PDF, CSV und Text."
        case .oldExcel:
            return "Das ist ein altes Excel-Format (.xls). Öffne die Datei in Excel und speichere sie als „Excel-Arbeitsmappe (.xlsx)“ oder als „CSV UTF-8“."
        case .oldWord:
            return "Das ist ein altes Word-Format (.doc). Öffne die Datei in Word und speichere sie als „Word-Dokument (.docx)“."
        case .numbers:
            return "Numbers-Dateien kann die App nicht direkt lesen. In Numbers: Teilen → Exportieren → Excel, dann die neue Datei wählen."
        case .pages:
            return "Pages-Dateien kann die App nicht direkt lesen. In Pages: Teilen → Exportieren → Word, dann die neue Datei wählen."
        case .openDocument:
            return "LibreOffice-Dateien kann die App nicht direkt lesen. Bitte als Excel (.xlsx) oder Word (.docx) speichern."
        case .pdfLocked:
            return "Die PDF ist mit einem Passwort geschützt. Bitte eine Version ohne Passwort wählen."
        case .pdfWithoutText:
            return "In dieser PDF ist die Liste nur als Bild gespeichert. Mach stattdessen ein Foto der Liste — das kann die App lesen."
        case .nothingRecognized:
            return "Auf dem Foto war keine Schrift zu erkennen. Am besten gerade von oben und bei gutem Licht fotografieren."
        }
    }
}
