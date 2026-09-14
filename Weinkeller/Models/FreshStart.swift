import Foundation
import SwiftData

/// Der Zustand eines frisch installierten Geräts — an einer Stelle, damit
/// „Von vorne beginnen" wirklich dasselbe herstellt wie der allererste Start.
enum FreshStart {

    /// Zwei Kühlschränke mit je fünf Regalen à acht Fächern. Regale und Fächer
    /// passt der Besitzer danach in den Einstellungen an sein Gerät an.
    static func makeDefaultFridges(in context: ModelContext) {
        for (i, name) in ["Kühlschrank 1", "Kühlschrank 2"].enumerated() {
            let fridge = Fridge(name: name, order: i)
            context.insert(fridge)
            for s in 0..<5 {
                let shelf = Shelf(name: "Regal \(s + 1)", slots: 8, order: s)
                shelf.fridge = fridge
                context.insert(shelf)
            }
        }
    }

    /// Löscht alles und legt den Auslieferungszustand wieder an.
    ///
    /// Reihenfolge zählt: erst die Flaschen, dann die Weine, dann die Möbel — sonst
    /// räumen die Kaskaden hinter uns her, während wir noch löschen.
    static func wipe(_ context: ModelContext) {
        try? context.delete(model: Bottle.self)
        try? context.delete(model: Wine.self)
        try? context.delete(model: Shelf.self)
        try? context.delete(model: Fridge.self)
        makeDefaultFridges(in: context)
        try? context.save()
    }
}
