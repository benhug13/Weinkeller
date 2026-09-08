import Foundation

/// Einlesen einer CSV-Datei, wie Excel sie ausgibt.
///
/// Fallen, die hier bewusst behandelt werden — jede davon macht sonst aus 500 Flaschen Müll:
/// - **Trennzeichen:** Schweizer/deutsches Excel schreibt `;`, englisches `,`. Wird geraten.
/// - **Anführungszeichen:** `"Château "Grand", 2018"` — Kommas und Semikolons innerhalb
///   von Anführungszeichen trennen **nicht**, doppelte `""` sind ein echtes Zeichen.
/// - **BOM:** Excel setzt gern `\u{FEFF}` an den Anfang, sonst heisst die erste Spalte „﻿Name".
/// - **Zeilenenden:** Windows `\r\n`, alter Mac `\r`, Rest `\n`.
enum CSV {

    struct Table {
        var header: [String]
        var rows: [[String]]

        func value(_ row: [String], at index: Int?) -> String {
            guard let index, index >= 0, index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func parse(_ raw: String) -> Table {
        var text = raw
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
                   .replacingOccurrences(of: "\r", with: "\n")

        let separator = guessSeparator(in: text)
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        while let ch = pending ?? iterator.next() {
            pending = nil

            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") }   // "" ist ein echtes Anführungszeichen
                        else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
                continue
            }

            switch ch {
            case "\"":
                inQuotes = true
            case separator:
                row.append(field); field = ""
            case "\n":
                row.append(field); field = ""
                rows.append(row); row = []
            default:
                field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        // Leerzeilen fliegen raus — Excel hängt gern welche an.
        rows = rows.filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let header = rows.first else { return Table(header: [], rows: []) }

        return Table(
            header: header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            rows: Array(rows.dropFirst())
        )
    }

    /// Das Trennzeichen, das in der Kopfzeile am häufigsten vorkommt.
    private static func guessSeparator(in text: String) -> Character {
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let candidates: [Character] = [";", ",", "\t"]
        let counted = candidates.map { c in (c, firstLine.filter { $0 == c }.count) }
        return counted.max { $0.1 < $1.1 }?.0 ?? ";"
    }
}
