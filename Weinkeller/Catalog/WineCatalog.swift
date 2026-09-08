import Foundation

/// Der mitgelieferte Weinkatalog.
///
/// Er liegt als Datei in der App, damit ein Scan **ohne Netz und ohne Kosten** funktioniert —
/// auch im Keller, wo es keinen Empfang gibt. Gefüllt wird er aus dem offenen Bestand von
/// Open Food Facts (Lizenz ODbL: Quellenangabe nötig, der Datenbestand bleibt offen).
/// Findet der Katalog nichts, trägt der Benutzer den Wein ein — dieser Eintrag geht später
/// an den geteilten Bestand, damit ihn der Nächste geschenkt bekommt.
final class WineCatalog {
    private(set) var wines: [CatalogWine] = []
    private var byBarcode: [String: CatalogWine] = [:]

    static let shared = WineCatalog()

    private init() { load() }

    private func load() {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CatalogWine].self, from: data) else {
            wines = []
            return
        }
        wines = decoded
        byBarcode = Dictionary(decoded.compactMap { w in w.barcode.map { ($0, w) } },
                               uniquingKeysWith: { first, _ in first })
    }

    /// Barcodes sind eindeutig — hier gibt es kein Vielleicht.
    func lookup(barcode: String) -> CatalogWine? {
        byBarcode[barcode]
    }

    /// Bester Treffer für erkannten Etikettentext, oder nil, wenn nichts sicher genug passt.
    func bestMatch(for text: String, minimumScore: Double = 0.5) -> CatalogWine? {
        var best: (wine: CatalogWine, score: Double)?
        for wine in wines {
            let haystack = "\(wine.name) \(wine.producer) \(wine.region)"
            let score = TextMatching.score(query: text, candidate: haystack)
            if score > (best?.score ?? 0) { best = (wine, score) }
        }
        guard let best, best.score >= minimumScore else { return nil }
        return best.wine
    }

    var isEmpty: Bool { wines.isEmpty }
}
