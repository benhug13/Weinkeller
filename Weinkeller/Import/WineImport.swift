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

    /// Ein **Vorschlag**, noch kein Wein im Keller.
    ///
    /// ⭐ Warum es diesen Zwischenschritt gibt: Aus einer Liste — und erst recht aus einem Foto —
    /// kommt nie alles richtig heraus. Der Besitzer soll jede Zeile **sehen, ändern und
    /// wegwerfen** können, bevor irgendetwas im Keller landet. Erst „Übernehmen" schreibt.
    struct Draft: Identifiable, Equatable {
        var id = UUID()
        var name = ""
        var producer = ""
        var vintage = ""
        var type: WineType = .rot
        var region = ""
        var grape = ""
        var price: Double?
        var note = ""
        var count = 1
        /// Die Platzangaben, wie sie in der Liste standen. Gesucht wird der Platz erst beim
        /// Übernehmen — der Keller kann sich bis dahin noch ändern.
        var fridgeText = ""
        var shelfText = ""
        var slotText = ""
        /// Zeilennummer in der Liste, damit man eine Zeile im Zweifel wiederfindet.
        var sourceLine: Int?

        var hasName: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

        /// Kurze Zeile unter dem Namen: „2019 · 3 Flaschen · CHF 24.50"
        var summaryLine: String {
            var parts: [String] = []
            if !vintage.isEmpty { parts.append(vintage) }
            parts.append(count == 1 ? "1 Flasche" : "\(count) Flaschen")
            if let price { parts.append("CHF " + String(format: price == price.rounded() ? "%.0f" : "%.2f", price)) }
            if !region.isEmpty { parts.append(region) }
            return parts.joined(separator: " · ")
        }
    }

    /// Tabelle + Spaltenzuordnung → Vorschläge. Zeilen ohne Namen fallen weg.
    static func drafts(table: CSV.Table, mapping: [Field: Int]) -> [Draft] {
        table.rows.enumerated().compactMap { index, row in
            let name = table.value(row, at: mapping[.name]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return Draft(
                name: name,
                producer: table.value(row, at: mapping[.producer]),
                vintage: vintage(from: table.value(row, at: mapping[.vintage])),
                type: wineType(from: table.value(row, at: mapping[.type])),
                region: table.value(row, at: mapping[.region]),
                grape: table.value(row, at: mapping[.grape]),
                price: price(from: table.value(row, at: mapping[.price])),
                note: table.value(row, at: mapping[.note]),
                count: bottleCount(raw: table.value(row, at: mapping[.count])),
                fridgeText: table.value(row, at: mapping[.fridge]),
                shelfText: table.value(row, at: mapping[.shelf]),
                slotText: table.value(row, at: mapping[.slot]),
                sourceLine: index + 1
            )
        }
    }

    /// Ein gelesenes Etikett (eine einzelne Flasche) als Vorschlag.
    static func draft(fromLabel label: VinelloAPI.LabelResult) -> Draft {
        Draft(name: label.name, producer: label.producer, vintage: label.vintage,
              type: label.wineType, region: label.region, grape: label.grape)
    }

    struct Summary {
        var wines: Int
        var bottles: Int
        var placed: Int
        var withoutName: Int
    }

    static func summary(drafts: [Draft], fridges: [Fridge]) -> Summary {
        var wines = 0, bottles = 0, placed = 0, withoutName = 0
        for draft in drafts {
            guard draft.hasName else { withoutName += 1; continue }
            wines += 1
            bottles += draft.count
            if resolvePlace(draft: draft, fridges: fridges) != nil { placed += 1 }
        }
        return Summary(wines: wines, bottles: bottles, placed: placed, withoutName: withoutName)
    }

    struct Result {
        var wines: Int
        var bottles: Int
        var unplaced: Int
    }

    static func run(drafts: [Draft], fridges: [Fridge], context: ModelContext) -> Result {
        var wineCount = 0, bottleTotal = 0, unplaced = 0

        for draft in drafts {
            guard draft.hasName else { continue }

            let wine = Wine(
                name: draft.name.trimmingCharacters(in: .whitespaces),
                producer: draft.producer,
                vintage: draft.vintage,
                type: draft.type,
                region: draft.region,
                grape: draft.grape,
                price: draft.price,
                note: draft.note
            )
            context.insert(wine)
            wineCount += 1

            let place = resolvePlace(draft: draft, fridges: fridges)

            for index in 0..<max(1, draft.count) {
                let bottle = Bottle(wine: wine, shelf: nil, slot: 0)
                // Nur die erste Flasche bekommt den Platz aus der Liste — in einem Fach
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

    static func bottleCount(raw: String) -> Int {
        guard !raw.isEmpty, let n = Int(raw.filter(\.isNumber)) else { return 1 }
        return max(1, min(n, 200))   // Tippfehler in der Tabelle sollen nicht 9999 Flaschen anlegen
    }

    /// Vierstellige Jahreszahl aus einem Feld wie „2018" oder „Jahrgang 2018".
    private static func vintage(from raw: String) -> String {
        TextMatching.vintage(in: raw) ?? raw.filter(\.isNumber).prefix(4).description
    }

    /// „24.50", „24,50", „CHF 24.50" → 24.5
    static func price(from raw: String) -> Double? {
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
    private static func resolvePlace(draft: Draft,
                                     fridges: [Fridge]) -> (shelf: Shelf, slot: Int)? {
        let (fridgeText, shelfText, slotText) = (draft.fridgeText, draft.shelfText, draft.slotText)
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
