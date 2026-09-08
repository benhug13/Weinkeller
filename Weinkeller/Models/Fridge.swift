import Foundation
import SwiftData

@Model
final class Fridge {
    var name: String = "Kühlschrank"
    var order: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Shelf.fridge)
    var shelves: [Shelf]? = []

    init(name: String, order: Int) {
        self.name = name
        self.order = order
        self.shelves = []
    }

    /// Regale immer in der Reihenfolge, wie sie im Gerät übereinander liegen.
    var sortedShelves: [Shelf] {
        (shelves ?? []).sorted { $0.order < $1.order }
    }

    var bottleCount: Int {
        sortedShelves.reduce(0) { $0 + $1.bottlesInCellar.count }
    }
}

@Model
final class Shelf {
    var name: String = "Regal"
    var slots: Int = 8
    var order: Int = 0
    var fridge: Fridge?

    @Relationship(deleteRule: .nullify, inverse: \Bottle.shelf)
    var bottles: [Bottle]? = []

    init(name: String, slots: Int, order: Int) {
        self.name = name
        self.slots = slots
        self.order = order
        self.bottles = []
    }

    var bottlesInCellar: [Bottle] {
        (bottles ?? []).filter { !$0.isDrunk }
    }

    func bottle(inSlot index: Int) -> Bottle? {
        bottlesInCellar.first { $0.slot == index }
    }

    var freeSlots: [Int] {
        let taken = Set(bottlesInCellar.map(\.slot))
        return (0..<slots).filter { !taken.contains($0) }
    }
}
