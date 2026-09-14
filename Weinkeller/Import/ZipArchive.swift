import Foundation
import Compression

/// Liest ZIP-Archive — nur lesen, nur das Nötigste.
///
/// Warum selber: `.xlsx` und `.docx` sind in Wahrheit ZIP-Dateien voller XML, und iOS hat
/// keinen öffentlichen Entpacker. Fremdbibliotheken wollen wir nicht. Das Format ist zum
/// Glück einfach: am Ende steht ein Inhaltsverzeichnis, jede Datei ist entweder gar nicht
/// („stored") oder mit DEFLATE gepackt — und genau das kann das `Compression`-Framework.
///
/// Bewusst nicht unterstützt: ZIP64 (Dateien über 4 GB), Verschlüsselung, andere Packverfahren.
/// Solche Archive liefern `nil` statt Absturz.
struct ZipArchive {

    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
        let encrypted: Bool
    }

    /// Obergrenze pro Datei. Schützt vor „ZIP-Bomben", die beim Entpacken den Speicher sprengen.
    private static let maxEntrySize = 200 * 1024 * 1024

    private let bytes: [UInt8]
    private let entries: [String: Entry]

    /// Alle Pfade im Archiv, in der Reihenfolge des Inhaltsverzeichnisses.
    let names: [String]

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        self.init(data: data)
    }

    init?(data: Data) {
        let bytes = [UInt8](data)
        guard let directory = Self.readDirectory(bytes) else { return nil }
        self.bytes = bytes
        var map: [String: Entry] = [:]
        for entry in directory where map[entry.name] == nil { map[entry.name] = entry }
        self.entries = map
        self.names = directory.map(\.name)
    }

    /// Entpackter Inhalt einer Datei im Archiv, z.B. `xl/workbook.xml`.
    /// Gross-/Kleinschreibung wird notfalls ignoriert — manche Programme schreiben `XL/…`.
    func entry(_ path: String) -> Data? {
        let key = Self.clean(path)
        guard let entry = entries[key]
                ?? entries.first(where: { $0.key.lowercased() == key.lowercased() })?.value else {
            return nil
        }
        return extract(entry)
    }

    func contains(_ path: String) -> Bool {
        let key = Self.clean(path).lowercased()
        return entries.keys.contains { $0.lowercased() == key }
    }

    // MARK: - Inhaltsverzeichnis

    private static func readDirectory(_ b: [UInt8]) -> [Entry]? {
        // „End of Central Directory" steht ganz hinten, gefolgt von höchstens 65535 Bytes Kommentar.
        let minEnd = 22
        guard b.count >= minEnd else { return nil }
        let lowest = max(0, b.count - minEnd - 65_535)
        var eocd: Int?
        var i = b.count - minEnd
        while i >= lowest {
            if u32(b, i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard let end = eocd else { return nil }

        let count = Int(u16(b, end + 10))
        let size = Int(u32(b, end + 12))
        let offset = Int(u32(b, end + 16))
        // 0xFFFF / 0xFFFFFFFF heisst ZIP64 — für Weinlisten nie nötig, also sauber aufgeben.
        guard count != 0xFFFF, size != 0xFFFF_FFFF, offset != 0xFFFF_FFFF,
              offset + size <= b.count else { return nil }

        var result: [Entry] = []
        var p = offset
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(b, p) == 0x0201_4b50 else { return nil }
            let flags = u16(b, p + 8)
            let method = u16(b, p + 10)
            // Grössen aus dem Inhaltsverzeichnis nehmen, nicht aus dem lokalen Kopf:
            // Bei „Data Descriptor" (Flag-Bit 3) stehen dort nur Nullen.
            let compressed = Int(u32(b, p + 20))
            let uncompressed = Int(u32(b, p + 24))
            let nameLength = Int(u16(b, p + 28))
            let extraLength = Int(u16(b, p + 30))
            let commentLength = Int(u16(b, p + 32))
            let local = Int(u32(b, p + 42))
            guard p + 46 + nameLength <= b.count else { return nil }

            let nameBytes = Array(b[(p + 46)..<(p + 46 + nameLength)])
            // Bit 11 = UTF-8. Ohne das ist es offiziell CP437; Latin-1 ist nah genug und scheitert nie.
            let name = (flags & 0x0800 != 0 ? String(bytes: nameBytes, encoding: .utf8) : nil)
                ?? String(bytes: nameBytes, encoding: .utf8)
                ?? String(bytes: nameBytes, encoding: .isoLatin1) ?? ""

            result.append(Entry(name: clean(name), method: method,
                                compressedSize: compressed, uncompressedSize: uncompressed,
                                localHeaderOffset: local, encrypted: flags & 0x0001 != 0))
            p += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    // MARK: - Entpacken

    private func extract(_ entry: Entry) -> Data? {
        guard !entry.encrypted, entry.uncompressedSize <= Self.maxEntrySize else { return nil }
        let h = entry.localHeaderOffset
        guard h + 30 <= bytes.count, Self.u32(bytes, h) == 0x0403_4b50 else { return nil }
        // Der lokale Kopf kann ein anderes „Extra"-Feld haben als das Verzeichnis — seine eigenen Längen zählen.
        let start = h + 30 + Int(Self.u16(bytes, h + 26)) + Int(Self.u16(bytes, h + 28))
        let end = start + entry.compressedSize
        guard start <= end, end <= bytes.count else { return nil }

        switch entry.method {
        case 0:
            return Data(bytes[start..<end])
        case 8:
            return inflate(start: start, end: end, expected: entry.uncompressedSize)
        default:
            return nil
        }
    }

    /// `COMPRESSION_ZLIB` ist bei Apple rohes DEFLATE ohne zlib-Kopf — genau das Format im ZIP.
    private func inflate(start: Int, end: Int, expected: Int) -> Data? {
        if expected == 0 { return Data() }
        // Ein Byte Reserve: So merken wir, falls die Angabe im Verzeichnis zu klein war.
        var output = [UInt8](repeating: 0, count: expected + 1)
        let written = bytes.withUnsafeBufferPointer { src -> Int in
            output.withUnsafeMutableBufferPointer { dst -> Int in
                compression_decode_buffer(dst.baseAddress!, dst.count,
                                          src.baseAddress! + start, end - start,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expected else { return nil }
        return Data(output[0..<written])
    }

    // MARK: - Hilfen

    private static func clean(_ path: String) -> String {
        var p = path.replacingOccurrences(of: "\\", with: "/")
        while p.hasPrefix("/") { p.removeFirst() }
        return p
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        guard i + 2 <= b.count else { return 0 }
        return UInt16(b[i]) | UInt16(b[i + 1]) << 8
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        guard i + 4 <= b.count else { return 0 }
        return UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}
