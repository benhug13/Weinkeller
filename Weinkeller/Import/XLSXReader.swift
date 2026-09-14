import Foundation

/// Liest eine Excel-Datei (`.xlsx`) direkt — ohne Umweg über „Als CSV speichern".
///
/// Eine `.xlsx` ist ein ZIP mit XML-Dateien. Für eine Weinliste reichen drei davon:
/// - `xl/workbook.xml` + `xl/_rels/workbook.xml.rels` — welche Datei das erste Blatt ist,
/// - `xl/sharedStrings.xml` — Excel speichert jeden Text nur einmal und verweist per Nummer,
/// - das Blatt selbst mit den Zellen.
///
/// Fallen: Leere Zellen fehlen im XML komplett. Darum zählt die Adresse `r="C5"`, nie die
/// Reihenfolge — sonst rutscht der Preis in die Jahrgang-Spalte.
enum XLSXReader {

    enum Failure: Error { case notXLSX, noSheet }

    /// Alle nicht-leeren Zeilen des ersten Blatts mit Inhalt, gleich breit aufgefüllt.
    static func rows(from data: Data) throws -> [[String]] {
        guard let zip = ZipArchive(data: data) else { throw Failure.notXLSX }
        return try rows(from: zip)
    }

    static func rows(from zip: ZipArchive) throws -> [[String]] {
        guard zip.contains("xl/workbook.xml") || zip.contains("xl/worksheets/sheet1.xml") else {
            throw Failure.notXLSX
        }
        let shared = zip.entry("xl/sharedStrings.xml").map(parseSharedStrings) ?? []

        var paths = sheetPaths(in: zip)
        if paths.isEmpty { paths = ["xl/worksheets/sheet1.xml"] }

        // Das erste Blatt mit Inhalt — oft ist Blatt 1 leer oder ein Deckblatt ohne Tabelle.
        var sawSheet = false
        for path in paths {
            guard let xml = zip.entry(path) else { continue }
            sawSheet = true
            let rows = parseSheet(xml, shared: shared)
            if !rows.isEmpty { return rows }
        }
        if sawSheet { return [] }
        throw Failure.noSheet
    }

    // MARK: - Welche Datei ist welches Blatt?

    private static func sheetPaths(in zip: ZipArchive) -> [String] {
        guard let workbook = zip.entry("xl/workbook.xml"),
              let rels = zip.entry("xl/_rels/workbook.xml.rels") else { return [] }

        let sheets = XMLScan.elements(named: "sheet", in: workbook)
        var targets: [String: String] = [:]
        for rel in XMLScan.elements(named: "Relationship", in: rels) {
            if let id = rel["Id"], let target = rel["Target"] { targets[id] = target }
        }

        // Ausgeblendete Blätter hinten anstellen — sie sind selten die eigentliche Liste.
        let ordered = sheets.filter { ($0["state"] ?? "visible") == "visible" }
                    + sheets.filter { ($0["state"] ?? "visible") != "visible" }
        return ordered.compactMap { sheet -> String? in
            // Das Attribut heisst `r:id`, das Präfix kann aber anders lauten.
            guard let id = sheet.first(where: { $0.key == "id" || $0.key.hasSuffix(":id") })?.value,
                  let target = targets[id] else { return nil }
            if target.hasPrefix("/") { return String(target.dropFirst()) }
            return "xl/" + target
        }
    }

    // MARK: - Texte

    private static func parseSharedStrings(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    private final class SharedStringsParser: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var current = ""
        private var inItem = false
        private var inText = false
        private var phoneticDepth = 0   // `rPh` = japanische Lesehilfe, gehört nicht zum Text

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch XMLScan.local(name) {
            case "si": inItem = true; current = ""
            case "rPh": phoneticDepth += 1
            case "t": inText = inItem && phoneticDepth == 0
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            switch XMLScan.local(name) {
            case "si": strings.append(current); inItem = false
            case "rPh": phoneticDepth -= 1
            case "t": inText = false
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { current += string }
        }
    }

    // MARK: - Blatt

    private static func parseSheet(_ data: Data, shared: [String]) -> [[String]] {
        let delegate = SheetParser(shared: shared)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        let sorted = delegate.rows.sorted { $0.key < $1.key }.map(\.value)
        var rows: [[String]] = sorted.map { cells in
            guard let last = cells.keys.max() else { return [] }
            var row = Array(repeating: "", count: last + 1)
            for (col, value) in cells { row[col] = value }
            return row
        }
        rows = rows.filter { $0.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        let width = rows.map(\.count).max() ?? 0
        return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    private final class SheetParser: NSObject, XMLParserDelegate {
        let shared: [String]
        /// Zeilennummer → (Spalte → Wert). Lückenhaft, genau wie im XML.
        var rows: [Int: [Int: String]] = [:]

        private var rowIndex = -1
        private var colIndex = -1
        private var cellType = ""
        private var value = ""
        private var inlineText = ""
        private var capture: Capture = .none
        private enum Capture { case none, value, inline }

        init(shared: [String]) { self.shared = shared }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch XMLScan.local(name) {
            case "row":
                rowIndex = attributes["r"].flatMap(Int.init).map { $0 - 1 } ?? rowIndex + 1
                colIndex = -1
            case "c":
                // Ohne Adresse (kommt bei selbstgebauten Dateien vor) einfach die nächste Spalte.
                if let ref = attributes["r"], let parsed = XLSXReader.cellReference(ref) {
                    colIndex = parsed.col
                    if let r = parsed.row { rowIndex = r }
                } else {
                    colIndex += 1
                }
                cellType = attributes["t"] ?? "n"
                value = ""; inlineText = ""
            case "v": capture = .value
            case "t": if cellType == "inlineStr" { capture = .inline }
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            switch XMLScan.local(name) {
            case "v", "t":
                capture = .none
            case "c":
                let text = resolve().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, rowIndex >= 0, colIndex >= 0, colIndex < 16_384 {
                    rows[rowIndex, default: [:]][colIndex] = text
                }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            switch capture {
            case .value: value += string
            case .inline: inlineText += string
            case .none: break
            }
        }

        private func resolve() -> String {
            switch cellType {
            case "s":
                guard let i = Int(value.trimmingCharacters(in: .whitespaces)), i >= 0, i < shared.count else { return "" }
                return shared[i]
            case "inlineStr": return inlineText
            case "b": return value.trimmingCharacters(in: .whitespaces) == "1" ? "Ja" : "Nein"
            case "e": return ""          // #DIV/0! und Co. sind keine Weindaten
            case "str", "d": return value
            default: return XLSXReader.formatNumber(value)
            }
        }
    }

    // MARK: - Hilfen

    /// „C5" → Spalte 2, Zeile 4 (beides ab 0).
    static func cellReference(_ ref: String) -> (col: Int, row: Int?)? {
        var col = 0
        var digits = ""
        for ch in ref.uppercased() {
            if let a = ch.asciiValue, a >= 65, a <= 90, digits.isEmpty {
                col = col * 26 + Int(a - 64)
            } else if ch.isNumber {
                digits.append(ch)
            } else if ch != "$" {
                return nil
            }
        }
        guard col > 0 else { return nil }
        return (col - 1, Int(digits).map { $0 - 1 })
    }

    /// Excel speichert 2018 als `2018` und manchmal als `2018.0` oder `2.018E3`.
    /// Ganze Zahlen ohne Komma, sonst die kürzeste genaue Schreibweise (24.5, nicht 24.499999).
    static func formatNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let d = Double(trimmed), d.isFinite else { return trimmed }
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        return String(d)
    }
}

/// Kleine gemeinsame XML-Hilfen für die Office-Leser.
enum XMLScan {

    /// `w:p` → `p`. Präfixe unterscheiden sich je nach Programm, der Name dahinter nicht.
    static func local(_ name: String) -> String {
        guard let colon = name.lastIndex(of: ":") else { return name }
        return String(name[name.index(after: colon)...])
    }

    /// Attribute aller Elemente mit diesem Namen — reicht für Verzeichnisdateien wie `workbook.xml`.
    static func elements(named element: String, in data: Data) -> [[String: String]] {
        let delegate = Collector(element: element)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.found
    }

    private final class Collector: NSObject, XMLParserDelegate {
        let element: String
        var found: [[String: String]] = []
        init(element: String) { self.element = element }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            if XMLScan.local(name) == element { found.append(attributes) }
        }
    }
}
