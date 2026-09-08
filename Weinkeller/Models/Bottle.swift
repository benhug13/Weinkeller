import Foundation
import SwiftData

@Model
final class Bottle {
    var slot: Int = 0
    var addedAt: Date = Date()
    var drunkAt: Date?
    var wine: Wine?
    var shelf: Shelf?

    /// `shelf` darf leer sein: beim Übernehmen aus Excel ist der Platz oft nicht bekannt.
    /// Solche Flaschen landen in „noch einräumen".
    init(wine: Wine, shelf: Shelf?, slot: Int) {
        self.wine = wine
        self.shelf = shelf
        self.slot = slot
        self.addedAt = Date()
    }

    var isDrunk: Bool { drunkAt != nil }

    var hasPlace: Bool { shelf != nil }

    var fridge: Fridge? { shelf?.fridge }

    /// „Kühlschrank 1 · Regal 2 · Fach 5"
    var placeLabel: String {
        guard let shelf, let fridge = shelf.fridge else { return "Platz unbekannt" }
        return "\(fridge.name) · \(shelf.name) · Fach \(slot + 1)"
    }
}
