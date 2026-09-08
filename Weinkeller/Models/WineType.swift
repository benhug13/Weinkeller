import SwiftUI

/// Die Weinart. Sie ist die einzige Stelle, an der Farbe in der App etwas bedeutet.
enum WineType: String, Codable, CaseIterable, Identifiable {
    case rot, weiss, rose, schaum, suess

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rot:    return "Rot"
        case .weiss:  return "Weiss"
        case .rose:   return "Rosé"
        case .schaum: return "Schaumwein"
        case .suess:  return "Süsswein"
        }
    }

    var color: Color {
        switch self {
        case .rot:    return Theme.typeRot
        case .weiss:  return Theme.typeWeiss
        case .rose:   return Theme.typeRose
        case .schaum: return Theme.typeSchaum
        case .suess:  return Theme.typeSuess
        }
    }
}
