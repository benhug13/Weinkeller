import Foundation

/// Ein Wein aus dem mitgelieferten Katalog. Genau die Felder, die ein Etikett hergibt.
struct CatalogWine: Codable, Identifiable, Hashable {
    var id: String { barcode ?? "\(name)|\(producer)|\(vintage)" }

    var barcode: String?
    var name: String
    var producer: String = ""
    var vintage: String = ""
    var type: String = WineType.rot.rawValue
    var region: String = ""
    var grape: String = ""

    var wineType: WineType { WineType(rawValue: type) ?? .rot }
}
