import Foundation

/// Macht aus losen Zeilen eine Tabelle — für Listen aus Notizen, Mails, Word-Text, PDF oder Foto.
///
/// Solche Listen haben keine Spalten, aber fast immer dieselben Bausteine pro Zeile:
/// `6x Dôle Blanche 2021 Fr. 18.50`. Wir holen die Bausteine in fester Reihenfolge heraus —
/// **Preis, dann Jahrgang, dann Anzahl** —, weil jeder Schritt Zahlen wegnimmt, die der
/// nächste sonst falsch lesen würde („24.50" ist kein Jahrgang, „2015" keine Flaschenzahl).
/// Was übrig bleibt, ist der Name. Traube und Region bleiben bewusst im Namen stehen.
enum FreeTextList {

    struct Line: Equatable {
        var name: String
        var vintage: String = ""
        var count: String = ""
        var price: String = ""
        var type: String = ""
    }

    // MARK: - Tabelle

    static func table(from text: String) -> CSV.Table {
        table(fromLines: splitLines(text))
    }

    static func table(fromLines lines: [String]) -> CSV.Table {
        var parsed: [Line] = []
        var sectionType = ""   // „Weissweine:" gilt für die Zeilen darunter

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if isHeading(line) {
                sectionType = wineType(in: line) ?? (line.hasSuffix(":") ? "" : sectionType)
                continue
            }
            guard var entry = parse(line) else { continue }
            if entry.type.isEmpty { entry.type = sectionType }
            parsed.append(entry)
        }

        // Nur Spalten, die wirklich etwas enthalten — sonst sieht der Besitzer leere Zuordnungen.
        typealias Column = (title: String, value: (Line) -> String)
        let all: [Column] = [
            ("Name", { $0.name }), ("Jahrgang", { $0.vintage }), ("Anzahl", { $0.count }),
            ("Preis", { $0.price }), ("Art", { $0.type })
        ]
        let used = all.enumerated().filter { index, column in
            index == 0 || parsed.contains { !column.value($0).isEmpty }
        }.map(\.element)

        return CSV.Table(header: used.map(\.title),
                         rows: parsed.map { line in used.map { $0.value(line) } })
    }

    static func splitLines(_ text: String) -> [String] {
        // PDF und Fotos liefern „à" oft als „a" + Akzentzeichen — dann greift kein Suchmuster.
        var t = text.precomposedStringWithCanonicalMapping
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        return t.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")   // Zeilentrenner aus Notizen/Word
            .components(separatedBy: "\n")
    }

    // MARK: - Getrennte Spalten erkennen

    /// Tab oder `;`, wenn die Zeilen damit einheitlich in Spalten geteilt sind — etwa aus Excel
    /// in Notizen kopiert. Komma nur auf Wunsch: In Fliesstext ist ein Komma meist nur ein Komma.
    static func delimiter(in lines: [String], allowComma: Bool = false) -> Character? {
        let filled = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !filled.isEmpty else { return nil }
        var candidates: [Character] = ["\t", ";"]
        if allowComma { candidates.append(",") }

        var best: (Character, Double)?
        for c in candidates {
            let counts = filled.map { separatorCount(c, in: $0) }
            let withSeparator = counts.filter { $0 > 0 }
            guard !withSeparator.isEmpty else { continue }
            // Häufigste Anzahl Trennzeichen pro Zeile; mindestens 60 % der Zeilen müssen sie haben.
            let mode = Dictionary(grouping: withSeparator, by: { $0 }).max { $0.value.count < $1.value.count }!.key
            let share = Double(counts.filter { $0 == mode }.count) / Double(filled.count)
            let covered = Double(withSeparator.count) / Double(filled.count)
            let enough = filled.count == 1 ? mode >= 2 : (share >= 0.6 && covered >= 0.8)
            if enough, share > (best?.1 ?? 0) { best = (c, share) }
        }
        return best?.0
    }

    /// Trennzeichen ausserhalb von Anführungszeichen.
    private static func separatorCount(_ separator: Character, in line: String) -> Int {
        var inQuotes = false, count = 0
        for ch in line {
            if ch == "\"" { inQuotes.toggle() }
            else if ch == separator, !inQuotes { count += 1 }
        }
        return count
    }

    // MARK: - Eine Zeile

    static func parse(_ raw: String) -> Line? {
        let trimmed = raw.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = " " + stripBullet(trimmed) + " "
        guard s.contains(where: \.isLetter) else { return nil }

        let type = wineType(in: s) ?? ""
        let price = takePrice(&s)
        let vintage = takeVintage(&s)
        let count = takeCount(&s)

        let name = cleanName(s)
        guard name.contains(where: \.isLetter) else { return nil }
        return Line(name: name, vintage: vintage, count: count, price: price, type: type)
    }

    /// „•", „-", „*", „1.", „1)" am Zeilenanfang.
    static func stripBullet(_ s: String) -> String {
        s.replacingOccurrences(of: #"^(?:[•·‣◦▪▫●○■□►▶✓✔☐☑–—\-*+>]+\s*|\d{1,3}[.)]\s+)"#,
                               with: "", options: .regularExpression)
    }

    // MARK: Preis

    private static let number = #"(\d{1,3}(?:['’ʼ]\d{3})+|\d{1,5})(?:[.,](\d{1,2}))?"#
    private static let currency = #"(?<![\p{L}])(?:CHF|SFr\.?|Fr\.|Fr(?![\p{L}])|Franken|EUR|Euro|€|\$|USD)"#
    /// „à 32.–" — das „à" gehört zum Preis und soll nicht im Namen stehen bleiben.
    private static let unitWord = #"(?:(?<![\p{L}])(?:à|á|@|je|zu)\s*)?"#
    /// „24.-", „24.–", „24-" — und „69. -", wie die Texterkennung es gern liest (nur mit Punkt davor).
    private static let dash = #"(?:[.,]\s?[-–—]{1,2}|[-–—]{1,2})"#
    /// Liter, Zentiliter und Prozent sind Flaschengrösse oder Alkohol, kein Preis.
    private static let notVolume = #"(?!\s*(?:%|cl\b|dl\b|l\b|lt\b|liter|litre|vol))"#

    private static func takePrice(_ s: inout String) -> String {
        let patterns = [
            unitWord + currency + #"\s*"# + number + dash + "?" + notVolume,       // CHF 24.50, Fr. 24.-
            unitWord + #"(?<![\d.,'’])"# + number + dash + "?" + #"\s*"# + currency,                   // 24.50 Fr, 18.- CHF
            unitWord + #"(?<![\d.,'’])"# + number + dash + #"(?![\d])"#,           // 69.-, 32.–
            unitWord + #"(?<![\d.,'’])(\d{1,3}(?:['’]\d{3})*|\d{1,5})[.,](\d{2})(?![\d.,])"# + notVolume  // 24,90
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let m = firstMatch(pattern, in: s) else { continue }
            let whole = group(m, 1, in: s).filter(\.isNumber)
            // „2015-" ist eher ein Jahrgang mit Bindestrich als ein Preis von 2015 Franken.
            let cents = group(m, 2, in: s)
            if index >= 1, cents.isEmpty, let n = Int(whole), (1950...2049).contains(n) { continue }
            guard let value = Double(whole + "." + (cents.isEmpty ? "0" : cents)) else { continue }
            remove(m.range, from: &s)
            return value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
        }
        return ""
    }

    // MARK: Jahrgang

    private static func takeVintage(_ s: inout String) -> String {
        guard let year = TextMatching.vintage(in: s) else { return "" }
        // Das Wort „Jahrgang" oder „Jg." davor verschwindet mit.
        let pattern = #"(?:\b(?:Jahrgang|Jg\.?|Millésime|Vintage)\s*)?(?<!\d)"# + year + #"(?!\d)"#
        if let m = lastMatch(pattern, in: s) { remove(m.range, from: &s) }
        return year
    }

    // MARK: Anzahl

    private static let bottleWord = #"(?:Flaschen|Flasche|Fl\.?|Fls\.?|Stk\.?|Stück|Stueck|Bouteilles?|Btl\.?|Bt\.?|Bottles?|pcs\.?)"#

    private static func takeCount(_ s: inout String) -> String {
        let patterns = [
            #"(?<![\d.,\p{L}])(\d{1,3})\s*[x×](?![\p{L}\d])"#,               // 3x, 3 x
            #"(?<![\p{L}\d])[x×]\s*(\d{1,3})(?![\d.,\p{L}])"#,               // x3
            #"(?<![\d.,])(\d{1,3})\s*"# + bottleWord + #"(?![\p{L}])"#,       // 3 Fl., 3 Flaschen, 3 Stk
            #"\(\s*(\d{1,3})\s*\)"#,                                          // (3)
            #"(?:à|á)\s*(\d{1,2})(?![\d.,'’\-–—])(?!\s*(?:cl|dl|l)\b)"#,    // à 3
            #"^\s*(\d{1,2})\s+(?=\p{L})"#                                     // 12 Chasselas …
        ]
        for pattern in patterns {
            guard let m = firstMatch(pattern, in: s),
                  let n = Int(group(m, 1, in: s)), (1...999).contains(n) else { continue }
            remove(m.range, from: &s)
            return String(n)
        }
        return ""
    }

    // MARK: Weinart

    /// Weinart aus Stichwörtern — nur ganze Wörter, damit „Dôle Blanche" nicht zu Weisswein wird.
    /// Die Rückgabe ist so geschrieben, wie `WineImport` sie wieder versteht.
    static func wineType(in text: String) -> String? {
        let words = Set(TextMatching.normalize(text).split(separator: " ").map(String.init))
        guard !words.isEmpty else { return nil }
        // Reihenfolge = Vorrang: „Champagne Rosé" ist zuerst ein Schaumwein.
        let groups: [(String, Set<String>)] = [
            ("Schaumwein", ["champagner", "champagne", "prosecco", "sekt", "schaumwein", "schaumweine",
                            "cremant", "cava", "spumante", "franciacorta", "mousseux", "sparkling"]),
            ("Süsswein", ["suss", "susswein", "sussweine", "suesswein", "dessertwein", "dessertweine",
                          "sauternes", "eiswein", "tokaji", "doux", "liquoreux", "dessert"]),
            ("Rosé", ["rose", "rosewein", "roseweine", "rosato", "rosado"]),
            ("Weiss", ["weiss", "weisswein", "weissweine", "blanc", "bianco", "blanco", "white"]),
            ("Rot", ["rot", "rotwein", "rotweine", "rouge", "rosso", "tinto", "red"])
        ]
        return groups.first { !$0.1.isDisjoint(with: words) }?.0
    }

    // MARK: Überschriften

    /// Wörter, die in Überschriften stehen, aber nie allein einen Wein bezeichnen.
    private static let headingWords: Set<String> = [
        "weinkeller", "keller", "weinliste", "liste", "stand", "inventar", "inventur", "bestand",
        "ubersicht", "uebersicht", "meine", "mein", "unsere", "unser", "weine", "wein", "vom", "per", "am",
        "seite", "page", "und", "der", "die", "das", "im", "von",
        "rotweine", "rotwein", "weissweine", "weisswein", "roseweine", "rosewein", "schaumweine",
        "schaumwein", "dessertweine", "dessertwein", "sussweine", "susswein", "rot", "weiss", "rose",
        "name", "jahrgang", "anzahl", "preis", "art", "menge", "flaschen", "chf", "region", "winzer",
        "januar", "februar", "marz", "april", "mai", "juni", "juli", "august", "september",
        "oktober", "november", "dezember",
        "hallo", "hoi", "gruezi", "liebe", "lieber", "gruss", "grusse", "gruesse", "freundliche",
        "herzliche", "beste", "viele", "danke", "lg", "mfg"
    ]

    static func isHeading(_ line: String) -> Bool {
        let text = stripBullet(line).trimmingCharacters(in: .whitespaces)
        guard text.contains(where: \.isLetter) else { return true }
        // „Rotweine:" oder „Hallo, hier die Liste:" — ein Doppelpunkt am Ende kündigt etwas an.
        if text.hasSuffix(":") { return true }

        let words = TextMatching.normalize(text).split(separator: " ").map(String.init)
        let letterWords = words.filter { $0.contains(where: \.isLetter) }
        if let first = letterWords.first, ["total", "summe", "gesamt", "gesamtwert", "gesamttotal"].contains(first) {
            return true
        }
        var probe = " " + text + " "
        let hasData = !takePrice(&probe).isEmpty || !takeCount(&probe).isEmpty
        if !letterWords.isEmpty, !hasData, letterWords.allSatisfy(headingWords.contains) { return true }

        // Ganze Sätze ohne jede Zahl sind Text drumherum, keine Weine.
        let hasVintage = TextMatching.vintage(in: text) != nil
        if !hasData, !hasVintage {
            if letterWords.count >= 8 { return true }
            if letterWords.count >= 4, let last = text.last, ".!?".contains(last) { return true }
        }
        return false
    }

    // MARK: - Hilfen

    private static func cleanName(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: #"\(\s*\)|\[\s*\]"#, with: " ", options: .regularExpression)
        // Zurückgebliebene Trenner-Ketten wie „ , , " auf einen zusammenziehen.
        t = t.replacingOccurrences(of: #"\s*([,;|/])(?:\s*[,;|/–—-])+\s*"#, with: "$1 ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([–—-])(?:\s*[,;|/–—-])+\s+"#, with: " $1 ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([,;])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let edges = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—,;|:/·•*+"))
        return t.trimmingCharacters(in: edges)
    }

    private static func firstMatch(_ pattern: String, in s: String) -> NSTextCheckingResult? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    }

    private static func lastMatch(_ pattern: String, in s: String) -> NSTextCheckingResult? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).last
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String {
        guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: s) else { return "" }
        return String(s[r])
    }

    /// Ersetzt durch ein Leerzeichen, damit „Barolo2012" nicht zu „Barolo" ohne Abstand verklebt.
    private static func remove(_ range: NSRange, from s: inout String) {
        guard let r = Range(range, in: s) else { return }
        s.replaceSubrange(r, with: " ")
    }
}
