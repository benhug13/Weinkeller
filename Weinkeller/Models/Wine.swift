import Foundation
import SwiftData

@Model
final class Wine {
    var name: String = ""
    var producer: String = ""
    var vintage: String = ""
    var typeRaw: String = WineType.rot.rawValue
    var region: String = ""
    var grape: String = ""
    var price: Double?
    var barcode: String?
    var note: String = ""
    /// Von Hand gesetztes Trinkfenster. Schlägt die Regeltabelle in [[DrinkWindow]].
    var drinkFromOverride: Int?
    var drinkToOverride: Int?
    @Attribute(.externalStorage) var photo: Data?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Bottle.wine)
    var bottles: [Bottle]? = []

    init(name: String,
         producer: String = "",
         vintage: String = "",
         type: WineType = .rot,
         region: String = "",
         grape: String = "",
         price: Double? = nil,
         barcode: String? = nil,
         note: String = "") {
        self.name = name
        self.producer = producer
        self.vintage = vintage
        self.typeRaw = type.rawValue
        self.region = region
        self.grape = grape
        self.price = price
        self.barcode = barcode
        self.note = note
        self.createdAt = Date()
        self.bottles = []
    }

    var type: WineType {
        get { WineType(rawValue: typeRaw) ?? .rot }
        set { typeRaw = newValue.rawValue }
    }

    var bottlesInCellar: [Bottle] {
        (bottles ?? []).filter { !$0.isDrunk }
    }

    var drinkWindow: ClosedRange<Int>? { DrinkWindow.years(for: self) }
    var drinkStatus: DrinkWindow.Status { DrinkWindow.status(for: self) }

    /// Alles, wonach in der Weinliste gesucht werden kann.
    var searchText: String {
        [name, producer, vintage, region, grape].joined(separator: " ").lowercased()
    }
}
