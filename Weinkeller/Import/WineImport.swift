import Foundation
import SwiftData

/// Übernimmt eine Excel-Liste (als CSV) in den Keller.
///
/// Kernproblem: **Jede Excel-Liste sieht anders aus.** Darum rät die App die Spalten nur
/// vor — zuordnen muss sie der Besitzer, und er sieht vor dem Übernehmen eine Vorschau.
enum WineImport {

    /// Die Felder, die wir aus einer Tabelle brauchen können.
    enum Field: String, CaseIterable, Identifiable {
        case name, producer, vintage, type, region, area, grape, price, count
        case fridge, shelf, slot, note

        var id: String { rawValue }

        var label: String {
            switch self {
            case .name:     return "Name"
            case .producer: return "Winzer"
            case .vintage:  return "Jahrgang"
            case .type:     return "Art"
            case .region:   return "Region"
            case .area:     return "Gebiet"
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
            case .name:     return ["name", "wein", "bezeichnung", "vin", "wine", "titel", "produkt",
                                    "description", "beschreibung", "designation", "cuvee", "etikett", "label"]
            case .producer: return ["winzer", "produzent", "erzeuger", "domaine", "château", "chateau", "weingut", "producer",
                                    "hersteller", "produttore", "cantina", "bodega", "estate"]
            case .vintage:  return ["jahrgang", "jahr", "vintage", "millesime", "millésime", "year", "annee", "anno"]
            case .type:     return ["art", "typ", "farbe", "kategorie", "type", "couleur"]
            case .region:   return ["region", "herkunft", "land", "origin", "country", "pays"]
            case .area:     return ["gebiet", "appellation", "area", "anbaugebiet", "subregion", "lage"]
            case .grape:    return ["traube", "rebsorte", "sorte", "grape", "cepage", "cépage"]
            case .price:    return ["preis", "chf", "kosten", "price", "wert", "einkauf", "prix", "prezzo"]
            case .count:    return ["anzahl", "menge", "flaschen", "stück", "stk", "count", "quantity", "bestand",
                                    "qty", "qte", "quantite"]
            case .fridge:   return ["kühlschrank", "kuehlschrank", "schrank", "gerät", "geraet", "lager"]
            case .shelf:    return ["regal", "tablar", "reihe", "ebene", "shelf"]
            case .slot:     return ["fach", "platz", "position", "slot"]
            case .note:     return ["notiz", "bemerkung", "kommentar", "note", "remarks", "comment"]
            }
        }

        /// „Drink Year" oder „Trinkreif ab" ist eine Jahreszahl, aber kein Jahrgang.
        func rejects(_ normalizedTitle: String) -> Bool {
            self == .vintage && ["drink", "trink", "boire", "reif", "ready"].contains { normalizedTitle.contains($0) }
        }
    }

    /// Rät für jedes Feld die passende Spalte aus der Kopfzeile.
    static func guessMapping(header: [String]) -> [Field: Int] {
        var mapping: [Field: Int] = [:]
        var used = Set<Int>()
        let titles = header.map(TextMatching.normalize)

        // Erst genaue Treffer, dann Teiltreffer — sonst nimmt „Region" die Spalte „Subregion",
        // obwohl daneben eine Spalte genau „Region" heisst.
        for exact in [true, false] {
            for field in Field.allCases where mapping[field] == nil {
                let hit = titles.indices.first { index in
                    let title = titles[index]
                    guard !used.contains(index), !title.isEmpty, !field.rejects(title) else { return false }
                    return field.hints.contains { hint in
                        let h = TextMatching.normalize(hint)
                        return exact ? title == h : title.contains(h)
                    }
                }
                if let hit {
                    mapping[field] = hit
                    used.insert(hit)
                }
            }
        }
        return mapping
    }

    /// Wie oben, schaut aber auch in die Zeilen. Heisst die Namensspalte ganz anders als
    /// erwartet, ist es die freie Spalte mit den längsten Texten. Ohne Namen fiele sonst
    /// jede Zeile weg, und die ganze Liste sähe leer aus.
    static func guessMapping(table: CSV.Table) -> [Field: Int] {
        var mapping = guessMapping(header: table.header)
        guard mapping[.name] == nil else { return mapping }

        let used = Set(mapping.values)
        let width = max(table.header.count, table.rows.map(\.count).max() ?? 0)
        func averageText(_ col: Int) -> Double {
            let values = table.rows.map { table.value($0, at: col) }.filter { $0.contains(where: \.isLetter) }
            return values.isEmpty ? 0 : Double(values.reduce(0) { $0 + $1.count }) / Double(values.count)
        }
        if let col = (0..<width).filter({ !used.contains($0) }).max(by: { averageText($0) < averageText($1) }),
           averageText(col) > 0 {
            mapping[.name] = col
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
            parts.append(count == 0 ? "keine Flasche mehr" : count == 1 ? "1 Flasche" : "\(count) Flaschen")
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
            // Ohne Spalte für die Art steht sie oft im Namen: „Cos d'Estournel (White)".
            let typeText = mapping[.type] != nil ? table.value(row, at: mapping[.type])
                                                 : FreeTextList.wineType(in: name) ?? ""
            // „Bordeaux, France" statt nur „France" — am Gebiet hängt das Trinkfenster.
            var places: [String] = []
            for text in [table.value(row, at: mapping[.area]), table.value(row, at: mapping[.region])]
                where !text.isEmpty && !places.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) {
                places.append(text)
            }
            return Draft(
                name: name,
                producer: table.value(row, at: mapping[.producer]),
                vintage: vintage(from: table.value(row, at: mapping[.vintage])),
                type: wineType(from: typeText),
                region: places.joined(separator: ", "),
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
        /// Weine, die schon im Keller sind — ihre Flaschen kommen dort dazu.
        var alreadyThere: Int = 0
    }

    static func summary(drafts: [Draft], fridges: [Fridge], cellar: [Wine] = []) -> Summary {
        var wines = 0, bottles = 0, placed = 0, withoutName = 0, alreadyThere = 0
        for draft in drafts {
            guard draft.hasName else { withoutName += 1; continue }
            wines += 1
            bottles += draft.count
            if resolvePlace(draft: draft, fridges: fridges) != nil { placed += 1 }
            if existing(for: draft, in: cellar) != nil { alreadyThere += 1 }
        }
        return Summary(wines: wines, bottles: bottles, placed: placed, withoutName: withoutName,
                       alreadyThere: alreadyThere)
    }

    /// Derselbe Wein, schon im Keller? Gleicher Name und Jahrgang; der Winzer muss nur
    /// passen, wenn beide einen haben. Wer eine ganze Sammlung dazukauft, hat oft Weine
    /// doppelt — die sollen **Flaschen dazubekommen**, nicht ein zweites Mal im Keller stehen.
    static func existing(for draft: Draft, in cellar: [Wine]) -> Wine? {
        let name = TextMatching.normalize(draft.name)
        let producer = TextMatching.normalize(draft.producer)
        guard !name.isEmpty else { return nil }
        return cellar.first { wine in
            guard TextMatching.normalize(wine.name) == name,
                  wine.vintage.trimmingCharacters(in: .whitespaces) == draft.vintage.trimmingCharacters(in: .whitespaces)
            else { return false }
            let other = TextMatching.normalize(wine.producer)
            return producer.isEmpty || other.isEmpty || producer == other
        }
    }

    struct Result {
        var wines: Int
        var bottles: Int
        var unplaced: Int
        /// Davon Weine, die schon im Keller waren und nur Flaschen dazubekommen haben.
        var merged: Int = 0
    }

    /// Schreibt die Vorschläge in den Keller. **Nimmt nie etwas weg** — eine zweite Liste
    /// kommt zum bestehenden Keller dazu. Verglichen wird nur mit dem Keller *vor* dem
    /// Import: Steht ein Wein in der neuen Liste zweimal (z. B. Magnum und 0.75 l), bleiben
    /// es zwei Einträge, genau wie in der Liste.
    static func run(drafts: [Draft], fridges: [Fridge], context: ModelContext) -> Result {
        var wineCount = 0, bottleTotal = 0, unplaced = 0, merged = 0
        let cellar = (try? context.fetch(FetchDescriptor<Wine>())) ?? []

        for draft in drafts {
            guard draft.hasName else { continue }

            let wine: Wine
            if let known = existing(for: draft, in: cellar) {
                // Nur Lücken füllen — was der Besitzer schon eingetragen hat, bleibt.
                if known.producer.isEmpty { known.producer = draft.producer }
                if known.region.isEmpty { known.region = draft.region }
                if known.grape.isEmpty { known.grape = draft.grape }
                if known.price == nil { known.price = draft.price }
                let note = draft.note.trimmingCharacters(in: .whitespaces)
                if !note.isEmpty, !known.note.localizedCaseInsensitiveContains(note) {
                    known.note = known.note.isEmpty ? note : known.note + "\n" + note
                }
                wine = known
                merged += 1
            } else {
                wine = Wine(
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
            }
            wineCount += 1

            let place = resolvePlace(draft: draft, fridges: fridges)

            // 0 Flaschen = schon ausgetrunken. Der Wein kommt trotzdem mit — samt Notiz
            // („nicht mehr kaufen"), genau wie nach „Trinken" in der App.
            for index in 0..<max(0, draft.count) {
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
        return Result(wines: wineCount, bottles: bottleTotal, unplaced: unplaced, merged: merged)
    }

    // MARK: - Umrechnungen

    static func bottleCount(raw: String) -> Int {
        guard !raw.isEmpty, let n = Int(raw.filter(\.isNumber)) else { return 1 }
        return min(n, 200)   // Tippfehler in der Tabelle sollen nicht 9999 Flaschen anlegen
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
