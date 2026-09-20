import Foundation
import SwiftData

/// „Welchen Wein heute?" — die Frage, die man vor dem offenen Kühlschrank stellt.
///
/// **Warum nicht einfach der trinkreifste Wein?** Weil ein Dienstagabend allein und
/// ein Essen mit Leuten, die man beeindrucken will, zwei verschiedene Flaschen
/// verlangen. Die App weiss das nur, wenn sie danach fragt — und es sind zwei
/// Fragen, keine zehn.
///
/// **Warum keine Frankenbeträge?** 190.– ist in dem einen Keller die teuerste
/// Flasche und im nächsten Durchschnitt. „Teuer" heisst darum hier immer:
/// **teuer verglichen mit dem eigenen Keller**.
enum Occasion {

    /// Wer trinkt mit. Fremde Gäste sind der eigentliche Grund für diese Frage:
    /// Für Leute, die den Unterschied nicht kennen, macht man keine 190er auf.
    enum Company: String, CaseIterable, Identifiable {
        case alone          // ich allein
        case twoOfUs        // zu zweit
        case friends        // Gäste, die ich gut kenne
        case strangers      // Gäste, die ich kaum kenne

        var id: String { rawValue }

        var label: String {
            switch self {
            case .alone:     return "Allein"
            case .twoOfUs:   return "Zu zweit"
            case .friends:   return "Gute Freunde"
            case .strangers: return "Kenne ich kaum"
            }
        }

        var symbol: String {
            switch self {
            case .alone:     return "person"
            case .twoOfUs:   return "person.2"
            case .friends:   return "person.3"
            case .strangers: return "person.fill.questionmark"
            }
        }
    }

    /// Was einem der Abend wert ist.
    enum Effort: String, CaseIterable, Identifiable {
        case everyday       // einfach ein Glas Wein
        case good           // etwas Schönes
        case special        // heute darf es etwas kosten

        var id: String { rawValue }

        var label: String {
            switch self {
            case .everyday: return "Einfach ein Glas"
            case .good:     return "Etwas Schönes"
            case .special:  return "Heute darf's was kosten"
            }
        }

        /// Wo im eigenen Preisgefüge gesucht wird — als Anteil, nicht in Franken.
        var band: ClosedRange<Double> {
            switch self {
            case .everyday: return 0.00...0.45
            case .good:     return 0.35...0.80
            case .special:  return 0.70...1.00
            }
        }
    }

    /// Fremde Gäste deckeln den Aufwand. Bens Satz dazu: „dann willst du doch nicht
    /// direkt einen Wein für 200 Franken trinken."
    static func effective(_ effort: Effort, with company: Company) -> Effort {
        guard company == .strangers else { return effort }
        return effort == .special ? .good : effort
    }

    /// Ein Vorschlag samt Begründung — ohne Begründung ist eine Empfehlung nur ein Befehl.
    struct Pick {
        let bottle: Bottle
        let reason: String
    }

    /// Sucht passende Flaschen: erst was ins Preisband passt, dann was am ehesten
    /// getrunken werden sollte.
    ///
    /// - Parameter bottles: alle Flaschen, die noch im Keller stehen.
    static func suggest(from bottles: [Bottle],
                        company: Company,
                        effort rawEffort: Effort,
                        limit: Int = 3) -> [Pick] {
        let effort = effective(rawEffort, with: company)
        let candidates = bottles.filter { $0.wine != nil }
        guard !candidates.isEmpty else { return [] }

        // Das Preisgefüge des eigenen Kellers. Flaschen ohne Preis bleiben hier
        // aussen vor — sie kommen später als Auffüllung dazu, statt als „gratis"
        // zu gelten und jede Alltagsempfehlung anzuführen.
        let prices = candidates.compactMap { $0.wine?.price }.filter { $0 > 0 }.sorted()

        func rank(_ price: Double) -> Double {
            guard prices.count > 1 else { return 0.5 }
            let below = prices.filter { $0 < price }.count
            return Double(below) / Double(prices.count - 1)
        }

        let band = effort.band
        let mid = (band.lowerBound + band.upperBound) / 2

        /// Was jetzt getrunken werden sollte, kommt zuerst — eine Flasche im
        /// letzten Jahr ihres Fensters ist der bessere Vorschlag als eine,
        /// die noch zehn Jahre Zeit hat.
        func urgency(_ wine: Wine) -> Int {
            switch wine.drinkStatus {
            case .lastCall:  return 0
            case .past:      return 1
            case .ready:     return 2
            case .tooYoung:  return 4
            case .unknown:   return 3
            }
        }

        let inBand = candidates.filter { bottle in
            guard let price = bottle.wine?.price, price > 0 else { return false }
            return band.contains(rank(price))
        }

        // Passt nichts ins Band, ist der Keller schmal bestückt: dann lieber die
        // nächstgelegene Flasche vorschlagen als eine leere Seite zeigen.
        let pool = inBand.isEmpty ? candidates : inBand

        let sorted = pool.sorted { a, b in
            guard let wa = a.wine, let wb = b.wine else { return false }
            let ua = urgency(wa), ub = urgency(wb)
            if ua != ub { return ua < ub }
            let da = abs(rank(wa.price ?? 0) - mid)
            let db = abs(rank(wb.price ?? 0) - mid)
            return da < db
        }

        // Pro Wein nur eine Flasche. „Oder: derselbe Wein, anderes Fach" ist keine
        // Alternative — wer sich gegen den Bordeaux entscheidet, will einen anderen
        // Wein sehen, nicht dieselbe Flasche nochmal.
        var seen = Set<PersistentIdentifier>()
        var result: [Pick] = []
        for bottle in sorted {
            guard let wine = bottle.wine else { continue }
            guard seen.insert(wine.persistentModelID).inserted else { continue }
            result.append(Pick(bottle: bottle, reason: reason(for: bottle, rank: rank, effort: effort)))
            if result.count == limit { break }
        }
        return result
    }

    private static func reason(for bottle: Bottle,
                               rank: (Double) -> Double,
                               effort: Effort) -> String {
        guard let wine = bottle.wine else { return "" }
        var parts: [String] = []

        switch wine.drinkStatus {
        case .lastCall:      parts.append("letztes Jahr im Trinkfenster")
        case .past(let y):   parts.append(y == 1 ? "ein Jahr über der Zeit" : "\(y) Jahre über der Zeit")
        case .ready:         parts.append("trinkreif")
        case .tooYoung(let y): parts.append(y == 1 ? "braucht eigentlich noch ein Jahr" : "braucht eigentlich noch \(y) Jahre")
        case .unknown:       parts.append("Trinkfenster unbekannt")
        }

        if let price = wine.price, price > 0 {
            let r = rank(price)
            if r <= 0.33      { parts.append("aus deiner günstigeren Hälfte") }
            else if r >= 0.75 { parts.append("eine deiner teureren Flaschen") }
            else              { parts.append("preislich im Mittelfeld") }
        }

        return parts.joined(separator: " · ")
    }
}
