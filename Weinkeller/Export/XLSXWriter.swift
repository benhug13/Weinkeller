import Foundation

/// Schreibt eine echte Excel-Datei (`.xlsx`) — ohne Fremdbibliothek, alles auf dem Gerät.
///
/// Das Gegenstück zu `XLSXReader`: Eine `.xlsx` ist ein ZIP mit ein paar XML-Dateien.
/// Texte stehen direkt in der Zelle (`inlineStr`), so braucht es keine Textliste daneben.
/// Die erste Zeile ist fett, bleibt beim Scrollen stehen und hat einen Filter — so, wie man
/// eine Liste am Computer haben will.
enum XLSXWriter {

    enum Cell {
        case text(String)
        case number(Double)
        /// Zahl mit zwei Nachkommastellen und Tausendertrennzeichen: 1'250.00
        case money(Double)
        case empty
    }

    struct Sheet {
        var name: String
        var rows: [[Cell]]
        /// Spaltenbreiten in Zeichen. Fehlt eine, rechnet Excel selber.
        var widths: [Double] = []
    }

    static func data(sheets: [Sheet]) -> Data {
        var files: [(String, Data)] = [
            ("[Content_Types].xml", contentTypes(sheetCount: sheets.count)),
            ("_rels/.rels", Data(rootRels.utf8)),
            ("xl/workbook.xml", workbook(sheets)),
            ("xl/_rels/workbook.xml.rels", workbookRels(sheetCount: sheets.count)),
            ("xl/styles.xml", Data(styles.utf8)),
        ]
        for (index, sheet) in sheets.enumerated() {
            files.append(("xl/worksheets/sheet\(index + 1).xml", worksheet(sheet)))
        }
        return ZipWriter.store(files)
    }

    // MARK: - Teile

    private static let mainNS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    private static let relNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#

    private static func contentTypes(sheetCount: Int) -> Data {
        let sheets = (1...max(1, sheetCount)).map {
            #"<Override PartName="/xl/worksheets/sheet\#($0).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }.joined()
        return Data((header + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
            + #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
            + #"<Default Extension="xml" ContentType="application/xml"/>"#
            + #"<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>"#
            + #"<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#
            + sheets + "</Types>").utf8)
    }

    private static let rootRels = header
        + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        + #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>"#
        + "</Relationships>"

    private static func workbook(_ sheets: [Sheet]) -> Data {
        var used = Set<String>()
        let entries = sheets.enumerated().map { index, sheet -> String in
            // Excel verbietet : \ / ? * [ ] im Blattnamen, max. 31 Zeichen, keine Doppelten.
            var name = String(sheet.name.filter { !":\\/?*[]".contains($0) }.prefix(31))
            if name.isEmpty || used.contains(name) { name = "Blatt \(index + 1)" }
            used.insert(name)
            return #"<sheet name="\#(escape(name))" sheetId="\#(index + 1)" r:id="rId\#(index + 1)"/>"#
        }.joined()
        return Data((header + #"<workbook xmlns="\#(mainNS)" xmlns:r="\#(relNS)"><sheets>"#
            + entries + "</sheets></workbook>").utf8)
    }

    private static func workbookRels(sheetCount: Int) -> Data {
        let base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        var rels = (1...max(1, sheetCount)).map {
            #"<Relationship Id="rId\#($0)" Type="\#(base)/worksheet" Target="worksheets/sheet\#($0).xml"/>"#
        }
        rels.append(#"<Relationship Id="rId\#(sheetCount + 1)" Type="\#(base)/styles" Target="styles.xml"/>"#)
        return Data((header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
            + rels.joined() + "</Relationships>").utf8)
    }

    /// Stil 0 = normal, 1 = fett (Kopfzeile), 2 = Betrag mit zwei Nachkommastellen.
    private static let styles = header + #"<styleSheet xmlns="\#(mainNS)">"#
        + #"<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>"#
        + #"<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>"#
        + #"<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"#
        + #"<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>"#
        + #"<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>"#
        + #"<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>"#
        + #"<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>"#
        + #"<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>"#
        + "</styleSheet>"

    private static func worksheet(_ sheet: Sheet) -> Data {
        var xml = header + #"<worksheet xmlns="\#(mainNS)" xmlns:r="\#(relNS)">"#
        // Kopfzeile fixieren: beim Scrollen durch 200 Weine bleibt sichtbar, welche Spalte was ist.
        xml += #"<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>"#
        if !sheet.widths.isEmpty {
            xml += "<cols>" + sheet.widths.enumerated().map {
                #"<col min="\#($0.offset + 1)" max="\#($0.offset + 1)" width="\#($0.element)" customWidth="1"/>"#
            }.joined() + "</cols>"
        }
        xml += "<sheetData>"
        for (r, row) in sheet.rows.enumerated() {
            xml += #"<row r="\#(r + 1)">"#
            for (c, cell) in row.enumerated() {
                let ref = column(c) + String(r + 1)
                let bold = r == 0 ? #" s="1""# : ""
                switch cell {
                case .empty:
                    continue
                case .text(let text):
                    let clean = escape(text)
                    guard !clean.isEmpty else { continue }
                    let space = text != text.trimmingCharacters(in: .whitespaces) ? #" xml:space="preserve""# : ""
                    xml += #"<c r="\#(ref)" t="inlineStr"\#(bold)><is><t\#(space)>\#(clean)</t></is></c>"#
                case .number(let value):
                    guard value.isFinite else { continue }
                    xml += #"<c r="\#(ref)"\#(bold)><v>\#(number(value))</v></c>"#
                case .money(let value):
                    guard value.isFinite else { continue }
                    xml += #"<c r="\#(ref)" s="2"><v>\#(number(value))</v></c>"#
                }
            }
            xml += "</row>"
        }
        xml += "</sheetData>"
        let width = sheet.rows.map(\.count).max() ?? 0
        if sheet.rows.count > 1, width > 0 {
            xml += #"<autoFilter ref="A1:\#(column(width - 1))\#(sheet.rows.count)"/>"#
        }
        xml += "</worksheet>"
        return Data(xml.utf8)
    }

    // MARK: - Hilfen

    /// 0 → A, 25 → Z, 26 → AA
    static func column(_ index: Int) -> String {
        var n = index + 1
        var letters = ""
        while n > 0 {
            let rest = (n - 1) % 26
            letters = String(UnicodeScalar(UInt8(65 + rest))) + letters
            n = (n - 1) / 26
        }
        return letters
    }

    /// Ganze Zahlen ohne „.0", sonst die kurze genaue Form (24.5, nicht 24.499999).
    private static func number(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(value)
    }

    /// XML-Sonderzeichen ersetzen und Steuerzeichen entfernen — ein einziges verirrtes
    /// Zeichen aus einer eingefügten Notiz würde sonst die ganze Datei unlesbar machen.
    static func escape(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\t", "\n", "\r": out.unicodeScalars.append(scalar)
            default:
                if scalar.value >= 0x20, !(0xFFFE...0xFFFF).contains(scalar.value) {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}

/// Packt Dateien in ein ZIP — ohne Komprimierung („stored"). Für eine Weinliste von ein paar
/// hundert Zeilen spielt die Grösse keine Rolle, und Excel, Numbers und Google liest das alles.
enum ZipWriter {

    static func store(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        let (time, date) = dosTimestamp(Date())

        for file in files {
            let name = Data(file.name.utf8)
            let crc = CRC32.checksum(file.data)
            let offset = UInt32(out.count)

            out.append(le32(0x0403_4B50))
            out.append(le16(20))             // benötigte Version
            out.append(le16(0x0800))         // Dateinamen in UTF-8
            out.append(le16(0))              // keine Komprimierung
            out.append(le16(time)); out.append(le16(date))
            out.append(le32(crc))
            out.append(le32(UInt32(file.data.count))); out.append(le32(UInt32(file.data.count)))
            out.append(le16(UInt16(name.count))); out.append(le16(0))
            out.append(name)
            out.append(file.data)

            central.append(le32(0x0201_4B50))
            central.append(le16(20)); central.append(le16(20))
            central.append(le16(0x0800)); central.append(le16(0))
            central.append(le16(time)); central.append(le16(date))
            central.append(le32(crc))
            central.append(le32(UInt32(file.data.count))); central.append(le32(UInt32(file.data.count)))
            central.append(le16(UInt16(name.count)))
            central.append(le16(0)); central.append(le16(0))   // Extra, Kommentar
            central.append(le16(0)); central.append(le16(0))   // Disk, interne Attribute
            central.append(le32(0))                             // externe Attribute
            central.append(le32(offset))
            central.append(name)
        }

        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x0605_4B50))
        out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(files.count))); out.append(le16(UInt16(files.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(centralOffset))
        out.append(le16(0))
        return out
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    private static func dosTimestamp(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let day = UInt16(max(0, (c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, day)
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}
