import Foundation
import SwiftData

/// Übernimmt eine Excel-Liste (als CSV) in den Keller.
///
/// Kernproblem: **Jede Excel-Liste sieht anders aus.** Darum rät die App die Spalten nur
/// vor — zuordnen muss sie der Besitzer, und er sieht vor dem Übernehmen eine Vorschau.
enum WineImport {

    /// Die Felder, die wir aus einer Tabelle brauchen können.
    enum Field: String, CaseIterable, Identifiable {
        case name, producer, vintage, type, region, grape, price, count
        case fridge, shelf, slot, note

        var id: String { rawValue }

        var label: String {
            switch self {
            case .name:     return "Name"
            case .producer: return "Winzer"
            case .vintage:  return "Jahrgang"
            case .type:     return "Art"
            case .region:   return "Region"
            case .grape:    return "Traube"
            case .price:    return "Preis"
            case .count:    return "Anzahl Flaschen"
            case .fridge:   return "Kühlschrank"
            case .shelf:    return "Regal"
            case .slot:     return "Fach"
            case .note:     return "Notiz"
            }
        }

        var isRequired: Bool { self == .name }

        /// Wörter, an denen die Spalte erkannt wird. Bewusst grosszügig — deutsche,
        /// englische und französische Kopfzeilen kommen alle vor.
        var hints: [String] {
            switch self {
            case .name:     return ["name", "wein", "bezeichnung", "vin", "wine", "titel", "produkt"]
            case .producer: return ["winzer", "produzent", "erzeuger", "domaine", "château", "chateau", "weingut", "producer"]
            case .vintage:  return ["jahrgang", "jahr", "vintage", "millesime", "millésime"]
            case .type:     return ["art", "typ", "farbe", "kategorie", "type", "couleur"]
            case .region:   return ["region", "gebiet", "herkunft", "land", "appellation", "origin"]
            case .grape:    return ["traube", "rebsorte", "sorte", "grape", "cepage", "cépage"]
            case .price:    return ["preis", "chf", "kosten", "price", "wert", "einkauf"]
            case .count:    return ["anzahl", "menge", "flaschen", "stück", "stk", "count", "quantity", "bestand"]
            case .fridge:   return ["kühlschrank", "kuehlschrank", "schrank", "gerät", "geraet", "lager"]
            case .shelf:    return ["regal", "tablar", "reihe", "ebene", "shelf"]
            case .slot:     return ["fach", "platz", "position", "slot"]
            case .note:     return ["notiz", "bemerkung", "kommentar", "note", "remarks"]
            }
        }
    }

    /// Rät für jedes Feld die passende Spalte aus der Kopfzeile.
    static func guessMapping(header: [String]) -> [Field: Int] {
        var mapping: [Field: Int] = [:]
        var used = Set<Int>()

        for field in Field.allCases {
            let hit = header.enumerated().first { index, title in
                guard !used.contains(index) else { return false }
                let normalized = TextMatching.normalize(title)
                guard !normalized.isEmpty else { return false }
                return field.hints.contains { normalized.contains(TextMatching.normalize($0)) }
            }
            if let hit {
                mapping[field] = hit.offset
                used.insert(hit.offset)
            }
        }
        return mapping
    }

    struct Preview {
        var importable: Int      // Zeilen mit Namen
        var skipped: Int         // Zeilen ohne Namen
        var bottles: Int         // Flaschen insgesamt (Anzahl-Spalte berücksichtigt)
        var placed: Int          // davon mit erkanntem Platz
        var samples: [String]    // die ersten Namen, zur Kontrolle
    }

    static func preview(table: CSV.Table, mapping: [Field: Int], fridges: [Fridge]) -> Preview {
        var importable = 0, skipped = 0, bottles = 0, placed = 0
        var samples: [String] = []

        for row in table.rows {
            let name = table.value(row, at: mapping[.name])
            guard !name.isEmpty else { skipped += 1; continue }
            importable += 1
            if samples.count < 4 { samples.append(name) }

            let count = bottleCount(table: table, row: row, mapping: mapping)
            bottles += count
            if resolvePlace(table: table, row: row, mapping: mapping, fridges: fridges) != nil {
                placed += count
            }
        }
        return Preview(importable: importable, skipped: skipped, bottles: bottles,
                       placed: placed, samples: samples)
    }

    struct Result {
        var wines: Int
        var bottles: Int
        var unplaced: Int
    }

    static func run(table: CSV.Table,
                    mapping: [Field: Int],
                    fridges: [Fridge],
                    context: ModelContext) -> Result {
        var wineCount = 0, bottleTotal = 0, unplaced = 0

        for row in table.rows {
            let name = table.value(row, at: mapping[.name])
            guard !name.isEmpty else { continue }

            let wine = Wine(
                name: name,
                producer: table.value(row, at: mapping[.producer]),
                vintage: vintage(from: table.value(row, at: mapping[.vintage])),
                type: wineType(from: table.value(row, at: mapping[.type])),
                region: table.value(row, at: mapping[.region]),
                grape: table.value(row, at: mapping[.grape]),
                price: price(from: table.value(row, at: mapping[.price])),
                note: table.value(row, at: mapping[.note])
            )
            context.insert(wine)
            wineCount += 1

            let count = bottleCount(table: table, row: row, mapping: mapping)
            let place = resolvePlace(table: table, row: row, mapping: mapping, fridges: fridges)

            for index in 0..<count {
                let bottle = Bottle(wine: wine, shelf: nil, slot: 0)
                // Nur die erste Flasche bekommt den Platz aus der Tabelle — in einem Fach
                // steht eine Flasche. Die weiteren wandern in „noch einräumen".
                if index == 0, let place {
                    bottle.shelf = place.shelf
                    bottle.slot = place.slot
                } else {
                    unplaced += 1
                }
                context.insert(bottle)
                bottleTotal += 1
            }
        }
        try? context.save()
        return Result(wines: wineCount, bottles: bottleTotal, unplaced: unplaced)
    }

    // MARK: - Umrechnungen

    private static func bottleCount(table: CSV.Table, row: [String], mapping: [Field: Int]) -> Int {
        let raw = table.value(row, at: mapping[.count])
        guard !raw.isEmpty, let n = Int(raw.filter(\.isNumber)) else { return 1 }
        return max(1, min(n, 200))   // Tippfehler in der Tabelle sollen nicht 9999 Flaschen anlegen
    }

    /// Vierstellige Jahreszahl aus einem Feld wie „2018" oder „Jahrgang 2018".
    private static func vintage(from raw: String) -> String {
        TextMatching.vintage(in: raw) ?? raw.filter(\.isNumber).prefix(4).description
    }

    /// „24.50", „24,50", „CHF 24.50" → 24.5
    private static func price(from raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private static func wineType(from raw: String) -> WineType {
        let n = TextMatching.normalize(raw)
        if n.isEmpty { return .rot }
        if n.contains("weis") || n.contains("blanc") || n.contains("white") { return .weiss }
        if n.contains("rose") || n.contains("rosé") { return .rose }
        if n.contains("schaum") || n.contains("sekt") || n.contains("champ") || n.contains("prosecco")
            || n.contains("cremant") || n.contains("spumante") { return .schaum }
        if n.contains("suss") || n.contains("dessert") || n.contains("doux") || n.contains("sauternes") { return .suess }
        return .rot
    }

    /// Sucht Kühlschrank, Regal und Fach aus der Tabelle im eingerichteten Keller.
    /// Findet es nichts Passendes, kommt die Flasche in „noch einräumen" — lieber ohne
    /// Platz als am falschen.
    private static func resolvePlace(table: CSV.Table,
                                     row: [String],
                                     mapping: [Field: Int],
                                     fridges: [Fridge]) -> (shelf: Shelf, slot: Int)? {
        let fridgeText = table.value(row, at: mapping[.fridge])
        let shelfText  = table.value(row, at: mapping[.shelf])
        let slotText   = table.value(row, at: mapping[.slot])
        guard !shelfText.isEmpty || !slotText.isEmpty else { return nil }

        let fridge = match(fridgeText, in: fridges.map { ($0.name, $0) }) ?? fridges.first
        guard let fridge else { return nil }

        let shelves = fridge.sortedShelves
        guard let shelf = match(shelfText, in: shelves.map { ($0.name, $0) })
                ?? numbered(shelfText, in: shelves) else { return nil }

        guard let number = Int(slotText.filter(\.isNumber)), number >= 1, number <= shelf.slots else {
            return nil
        }
        let index = number - 1
        guard shelf.bottle(inSlot: index) == nil else { return nil }   // Fach schon belegt
        return (shelf, index)
    }

    private static func match<T>(_ text: String, in items: [(String, T)]) -> T? {
        guard !text.isEmpty else { return nil }
        let n = TextMatching.normalize(text)
        return items.first { TextMatching.normalize($0.0) == n }?.1
            ?? items.first { TextMatching.normalize($0.0).contains(n) }?.1
    }

    /// „3" oder „Regal 3" → das dritte Regal.
    private static func numbered(_ text: String, in shelves: [Shelf]) -> Shelf? {
        guard let n = Int(text.filter(\.isNumber)), n >= 1, n <= shelves.count else { return nil }
        return shelves[n - 1]
    }
}
