import Foundation
import SwiftData

/// Wein liegt nicht überall im Kühlschrank. Viele haben ein Holzregal im Keller
/// oder stapeln Kisten. Die Art ändert nur **Wort und Symbol** — der Aufbau
/// (Ebenen mit Fächern) ist bei allen derselbe, darum bleibt `Fridge` das Modell.
enum StorageKind: String, CaseIterable, Identifiable, Codable {
    case fridge, rack, box

    var id: String { rawValue }

    /// Wie das Ding heisst, wenn man davorsteht.
    var label: String {
        switch self {
        case .fridge: return "Weinkühlschrank"
        case .rack:   return "Regal"
        case .box:    return "Kiste"
        }
    }

    var symbol: String {
        switch self {
        case .fridge: return "snowflake"
        case .rack:   return "square.grid.3x2"
        case .box:    return "shippingbox"
        }
    }

    var defaultName: String {
        switch self {
        case .fridge: return "Kühlschrank"
        case .rack:   return "Regal"
        case .box:    return "Kiste"
        }
    }

    /// Eine Ebene heisst im Regal nicht auch „Regal" — sonst steht später
    /// „Regal 1 · Regal 2 · Fach 5" auf der Flasche.
    var levelWord: String {
        switch self {
        case .fridge: return "Regal"
        case .rack:   return "Boden"
        case .box:    return "Lage"
        }
    }

    var levelWordPlural: String {
        switch self {
        case .fridge: return "Regale"
        case .rack:   return "Böden"
        case .box:    return "Lagen"
        }
    }
}

@Model
final class Fridge {
    var name: String = "Kühlschrank"
    var order: Int = 0

    /// Als Text abgelegt, damit ein alter Keller ohne dieses Feld weiterläuft:
    /// was vor dieser Version angelegt wurde, war immer ein Kühlschrank.
    var kindRaw: String = StorageKind.fridge.rawValue

    @Relationship(deleteRule: .cascade, inverse: \Shelf.fridge)
    var shelves: [Shelf]? = []

    init(name: String, order: Int, kind: StorageKind = .fridge) {
        self.name = name
        self.order = order
        self.kindRaw = kind.rawValue
        self.shelves = []
    }

    var kind: StorageKind {
        get { StorageKind(rawValue: kindRaw) ?? .fridge }
        set { kindRaw = newValue.rawValue }
    }

    /// Ebenen immer in der Reihenfolge, wie sie übereinander liegen.
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

extension Fridge {

    /// Art wechseln und die Wörter mitnehmen: aus „Kühlschrank 2" wird „Regal 2"
    /// und aus „Regal 1" darin „Boden 1". Ein selbst vergebener Name
    /// („Keller links") bleibt stehen — den hat jemand mit Absicht getippt.
    func changeKind(to new: StorageKind) {
        let old = kind
        guard old != new else { return }

        if let suffix = Self.suffix(of: name, afterDefaultNameOf: old) {
            name = suffix.isEmpty ? new.defaultName : "\(new.defaultName) \(suffix)"
        }
        for (index, shelf) in sortedShelves.enumerated()
        where shelf.name == "\(old.levelWord) \(index + 1)" {
            shelf.name = "\(new.levelWord) \(index + 1)"
        }
        kind = new
    }

    /// `"Kühlschrank 2"` → `"2"`, `"Kühlschrank"` → `""`, `"Keller links"` → `nil`.
    private static func suffix(of name: String, afterDefaultNameOf kind: StorageKind) -> String? {
        let base = kind.defaultName
        if name == base { return "" }
        guard name.hasPrefix(base + " ") else { return nil }
        let rest = String(name.dropFirst(base.count + 1))
        return rest.allSatisfy(\.isNumber) && !rest.isEmpty ? rest : nil
    }
}
