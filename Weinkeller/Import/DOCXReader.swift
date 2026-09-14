import Foundation

/// Liest ein Word-Dokument (`.docx`).
///
/// Weinlisten in Word gibt es in zwei Formen: als **Tabelle** — dann nehmen wir die grösste,
/// Deckblatt- oder Adresstabellen sind kleiner — oder als **einfache Zeilen** untereinander.
/// Die Zeilen gehen an `FreeTextList`, das Jahrgang, Anzahl und Preis selber heraussucht.
enum DOCXReader {

    enum Content {
        case table([[String]])
        case lines([String])
    }

    enum Failure: Error { case notDOCX }

    static func read(from data: Data) throws -> Content {
        guard let zip = ZipArchive(data: data) else { throw Failure.notDOCX }
        return try read(from: zip)
    }

    static func read(from zip: ZipArchive) throws -> Content {
        guard let xml = zip.entry("word/document.xml") else { throw Failure.notDOCX }
        let delegate = DocumentParser()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        parser.parse()

        // Nur echte Tabellen zählen: Eine 1×1-Tabelle ist in Word meist bloss ein Rahmen um Text.
        let tables = delegate.tables
            .map(tidy)
            .filter { $0.count >= 2 && ($0.first?.count ?? 0) >= 2 }
        // Die grösste Tabelle: zuerst nach Zeilen, bei Gleichstand nach gefüllten Zellen.
        if let biggest = tables.max(by: { size($0) < size($1) }) {
            return .table(biggest)
        }
        return .lines(delegate.lines)
    }

    private static func size(_ rows: [[String]]) -> (Int, Int) {
        (rows.count, rows.reduce(0) { $0 + $1.filter { !$0.isEmpty }.count })
    }

    private static func tidy(_ rows: [[String]]) -> [[String]] {
        let filled = rows
            .map { $0.map { $0.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
                              .trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { $0.contains { !$0.isEmpty } }
        let width = filled.map(\.count).max() ?? 0
        return filled.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    // MARK: - Parser

    private final class DocumentParser: NSObject, XMLParserDelegate {
        private(set) var tables: [[[String]]] = []
        private(set) var lines: [String] = []

        /// Offene Tabellen — Word erlaubt Tabellen in Tabellenzellen.
        private var stack: [TableState] = []
        private var paragraph = ""
        private var inText = false
        private var fallbackDepth = 0   // `mc:Fallback` wiederholt Textfelder ein zweites Mal

        private struct TableState {
            var rows: [[String]] = []
            var row: [String] = []
            var cell: [String] = []     // Absätze der aktuellen Zelle
            var inCell = false
            var pendingSpan = 0
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let local = XMLScan.local(name)
            if local == "Fallback" { fallbackDepth += 1; return }
            guard fallbackDepth == 0 else { return }

            switch local {
            case "tbl":
                stack.append(TableState())
            case "tr":
                if !stack.isEmpty { stack[stack.count - 1].row = [] }
            case "tc":
                if !stack.isEmpty { stack[stack.count - 1].cell = []; stack[stack.count - 1].inCell = true }
            case "gridSpan":
                // Verbundene Zellen: leere Platzhalter einfügen, damit die Spalten danach stimmen.
                if let span = attributes.first(where: { XMLScan.local($0.key) == "val" }).flatMap({ Int($0.value) }),
                   span > 1, span < 100, !stack.isEmpty {
                    stack[stack.count - 1].pendingSpan = span - 1
                }
            case "p":
                paragraph = ""
            case "t":
                inText = true
            case "tab":
                // In Zellen reicht ein Leerzeichen; in Fliesstext trennt der Tab oft Spalten.
                paragraph += inCell ? " " : "\t"
            case "br", "cr":
                paragraph += inCell ? " " : "\n"
            case "noBreakHyphen":
                paragraph += "-"
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            let local = XMLScan.local(name)
            if local == "Fallback" { fallbackDepth -= 1; return }
            guard fallbackDepth == 0 else { return }

            switch local {
            case "t":
                inText = false
            case "p":
                if inCell { stack[stack.count - 1].cell.append(paragraph) }
                // Auch Zellen-Absätze als Zeilen merken — falls es keine brauchbare Tabelle gibt.
                lines.append(contentsOf: paragraph.components(separatedBy: "\n"))
                paragraph = ""
            case "tc":
                guard !stack.isEmpty else { break }
                var top = stack[stack.count - 1]
                let text = top.cell.map { $0.trimmingCharacters(in: .whitespaces) }
                                   .filter { !$0.isEmpty }
                                   .joined(separator: " ")
                top.row.append(text)
                top.row.append(contentsOf: Array(repeating: "", count: top.pendingSpan))
                top.pendingSpan = 0
                top.cell = []
                top.inCell = false
                stack[stack.count - 1] = top
            case "tr":
                guard !stack.isEmpty else { break }
                stack[stack.count - 1].rows.append(stack[stack.count - 1].row)
                stack[stack.count - 1].row = []
            case "tbl":
                guard let finished = stack.popLast() else { break }
                tables.append(finished.rows)
                // Innere Tabelle: ihr Text gehört auch in die umgebende Zelle.
                if !stack.isEmpty, stack[stack.count - 1].inCell {
                    let flat = finished.rows.flatMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                    stack[stack.count - 1].cell.append(flat)
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText, fallbackDepth == 0 { paragraph += string }
        }

        private var inCell: Bool { stack.last?.inCell ?? false }
    }
}
