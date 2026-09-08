#if DEBUG
import Foundation
import SwiftData

/// Füllt den Keller mit Beispielweinen, damit man die Ansichten beurteilen kann.
/// Läuft nur im Debug-Build und nur mit dem Startargument `-demo`.
enum DebugSeed {
    /// `simctl launch` schluckt Argumente mit Bindestrich, darum zusätzlich über die Umgebung:
    /// `SIMCTL_CHILD_WEINKELLER_DEMO=1 xcrun simctl launch booted ch.weinkeller.app`
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo")
            || ProcessInfo.processInfo.environment["WEINKELLER_DEMO"] == "1"
    }

    static func fill(_ context: ModelContext, fridges: [Fridge]) {
        let samples: [(String, String, String, WineType, String, String, Double)] = [
            ("Château Croix de Labrie", "Saint-Émilion", "2018", .rot,    "Bordeaux",   "Merlot",      68),
            ("Barolo Cannubi",          "G. Rinaldi",    "2016", .rot,    "Piemont",    "Nebbiolo",    95),
            ("Dézaley Médinette",       "Louis Bovard",  "2021", .weiss,  "Lavaux",     "Chasselas",   32),
            ("Pinot Noir Réserve",      "Gantenbein",    "2019", .rot,    "Graubünden", "Pinot Noir", 120),
            ("Meursault Charmes",       "Domaine Roulot","2020", .weiss,  "Burgund",    "Chardonnay",210),
            ("Cuvée Rosé Brut",         "Laurent-Perrier","",    .schaum, "Champagne",  "Pinot Noir",  89),
            ("Amarone Classico",        "Tommasi",       "2017", .rot,    "Venetien",   "Corvina",     54),
            ("Riesling Kabinett",       "Dr. Loosen",    "2022", .weiss,  "Mosel",      "Riesling",  19.5),
            ("Sauternes",               "Doisy-Daëne",   "2015", .suess,  "Bordeaux",   "Sémillon",    45),
            ("Tavel Rosé",              "Domaine Maby",  "2023", .rose,   "Rhône",      "Grenache",    22),
            ("Fendant du Valais",       "Provins",       "2022", .weiss,  "Wallis",     "Chasselas",   16),
        ]

        let wines = samples.map { s -> Wine in
            let wine = Wine(name: s.0, producer: s.1, vintage: s.2, type: s.3,
                            region: s.4, grape: s.5, price: s.6)
            context.insert(wine)
            return wine
        }

        var n = 0
        let plan: [(Int, [Int])] = [(0, [0, 1, 4]), (1, [2, 3]), (2, [0, 1, 2, 5, 6]), (3, [0, 3])]
        for fridge in fridges.prefix(1) {
            let shelves = fridge.sortedShelves
            for (shelfIndex, slots) in plan where shelfIndex < shelves.count {
                for slot in slots {
                    context.insert(Bottle(wine: wines[n % wines.count],
                                          shelf: shelves[shelfIndex], slot: slot))
                    n += 1
                }
            }
        }
        try? context.save()
    }
}
#endif
