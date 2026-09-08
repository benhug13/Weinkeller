import Foundation

/// Wann ist ein Wein trinkreif?
///
/// Das ist **keine künstliche Intelligenz und keine Abfrage im Internet**, sondern eine
/// Regeltabelle: Rebsorte, Region und Art ergeben eine typische Reifespanne, die auf den
/// Jahrgang addiert wird. Die Tabelle ist einmal geschrieben und bleibt jahrzehntelang gültig.
///
/// ⚠️ Das sind **Richtwerte**, keine Wahrheit. Jede Flasche altert anders, und der Besitzer
/// kann die Spanne für jeden Wein von Hand überschreiben.
enum DrinkWindow {

    struct Rule {
        let keywords: [String]
        let from: Int
        let to: Int
    }

    /// Reifespannen in Jahren ab Jahrgang. Zuerst wird die Rebsorte geprüft, dann die Region.
    private static let grapeRules: [Rule] = [
        Rule(keywords: ["nebbiolo", "barolo", "barbaresco"],        from: 8, to: 25),
        Rule(keywords: ["sangiovese", "brunello", "chianti"],       from: 4, to: 20),
        Rule(keywords: ["corvina", "amarone"],                      from: 5, to: 20),
        Rule(keywords: ["cabernet", "merlot", "bordeaux"],          from: 5, to: 15),
        Rule(keywords: ["syrah", "shiraz", "tempranillo", "rioja"], from: 4, to: 15),
        Rule(keywords: ["pinot noir", "spätburgunder", "blauburgunder"], from: 3, to: 12),
        Rule(keywords: ["grenache", "gamay", "beaujolais", "merlot du valais"], from: 1, to: 5),
        Rule(keywords: ["riesling"],                                from: 2, to: 12),
        Rule(keywords: ["chardonnay", "meursault", "chablis"],      from: 2, to: 10),
        Rule(keywords: ["sémillon", "semillon", "sauternes"],       from: 5, to: 30),
        Rule(keywords: ["chasselas", "fendant", "gutedel"],         from: 1, to: 4),
        Rule(keywords: ["sauvignon", "müller-thurgau", "pinot gris", "pinot grigio"], from: 1, to: 4),
    ]

    private static let regionRules: [Rule] = [
        Rule(keywords: ["bordeaux", "saint-émilion", "médoc", "pauillac"], from: 5, to: 15),
        Rule(keywords: ["burgund", "bourgogne", "côte de"],  from: 3, to: 14),
        Rule(keywords: ["piemont", "piemonte"],              from: 6, to: 20),
        Rule(keywords: ["toskana", "toscana"],               from: 4, to: 18),
        Rule(keywords: ["champagne"],                        from: 1, to: 10),
        Rule(keywords: ["wallis", "waadt", "lavaux", "graubünden"], from: 1, to: 8),
        Rule(keywords: ["mosel", "rheingau"],                from: 2, to: 12),
    ]

    /// Grundspanne, wenn weder Traube noch Region etwas hergeben.
    private static func fallback(for type: WineType) -> (from: Int, to: Int) {
        switch type {
        case .rot:    return (2, 10)
        case .weiss:  return (1, 5)
        case .rose:   return (1, 3)
        case .schaum: return (1, 6)
        case .suess:  return (3, 25)
        }
    }

    /// Von-bis als Jahreszahlen, oder nil, wenn kein Jahrgang bekannt ist.
    static func years(for wine: Wine) -> ClosedRange<Int>? {
        if let from = wine.drinkFromOverride, let to = wine.drinkToOverride, from <= to {
            return from...to
        }
        guard let vintage = Int(wine.vintage), vintage > 1900 else { return nil }

        let haystack = "\(wine.grape) \(wine.name)".lowercased()
        let regionHay = "\(wine.region) \(wine.name)".lowercased()

        let span: (from: Int, to: Int) =
            grapeRules.first { $0.keywords.contains(where: haystack.contains) }.map { ($0.from, $0.to) }
            ?? regionRules.first { $0.keywords.contains(where: regionHay.contains) }.map { ($0.from, $0.to) }
            ?? fallback(for: wine.type)

        return (vintage + span.from)...(vintage + span.to)
    }

    enum Status {
        case unknown        // kein Jahrgang hinterlegt
        case tooYoung(Int)  // noch so viele Jahre warten
        case ready          // trinkreif
        case lastCall       // letztes Jahr im Fenster
        case past(Int)      // so viele Jahre darüber

        var label: String {
            switch self {
            case .unknown:          return "Jahrgang fehlt"
            case .tooYoung(let y):  return y == 1 ? "noch 1 Jahr warten" : "noch \(y) Jahre warten"
            case .ready:            return "trinkreif"
            case .lastCall:         return "jetzt trinken"
            case .past(let y):      return y == 1 ? "1 Jahr über der Zeit" : "\(y) Jahre über der Zeit"
            }
        }
    }

    static func status(for wine: Wine, in year: Int = Calendar.current.component(.year, from: Date())) -> Status {
        guard let window = years(for: wine) else { return .unknown }
        if year < window.lowerBound { return .tooYoung(window.lowerBound - year) }
        if year > window.upperBound { return .past(year - window.upperBound) }
        if year == window.upperBound { return .lastCall }
        return .ready
    }
}
