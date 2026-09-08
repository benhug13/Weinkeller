import Foundation

/// Vergleichshilfen für Etikettentext.
///
/// Der Trick, auf dem die ganze Suche steht: Texterkennung ist schlecht darin, eine Flasche
/// aus Millionen zu bestimmen — aber sehr gut darin, gegen ein paar hundert Weine im eigenen
/// Keller zu treffen. Ein verlesenes `CHAT_AU MRGAUX` muss nur 199 Alternativen schlagen,
/// nicht eine Million. Darum reicht ein Wortabgleich; ein exakter Vergleich wäre zu streng.
enum TextMatching {

    /// Kleinbuchstaben, ohne Akzente, ohne Satzzeichen.
    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "de_CH"))
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Wörter ab drei Zeichen. Kurze Füllwörter wie „de" oder „du" tragen nichts bei.
    static func tokens(_ s: String) -> Set<String> {
        Set(normalize(s).split(separator: " ").map(String.init).filter { $0.count >= 3 })
    }

    /// 0 = nichts gemeinsam, 1 = der gesuchte Text steckt vollständig im Kandidaten.
    /// Gemessen wird am kürzeren der beiden — sonst verlieren lange Winzernamen immer.
    static func score(query: String, candidate: String) -> Double {
        let a = tokens(query), b = tokens(candidate)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let shared = a.intersection(b).count
        return Double(shared) / Double(min(a.count, b.count))
    }

    /// Vierstellige Jahreszahl aus dem Etikettentext, sofern sie als Jahrgang taugt.
    static func vintage(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let re = try? NSRegularExpression(pattern: "\\b(19[5-9]\\d|20[0-4]\\d)\\b") else { return nil }
        let matches = re.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
        // Bei mehreren Zahlen die jüngste nehmen — Etiketten tragen oft auch Gründungsjahre.
        return matches.max()
    }
}
