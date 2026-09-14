import SwiftUI

/// Das Design der App — in den Einstellungen unter „Design" wählbar.
///
/// Voreinstellung ist **Schwarz**: reines Schwarz als Grund, dunkelgraue Karten. Auf dem
/// OLED-Display des iPhones ist Schwarz wirklich aus — ruhiger geht es nicht.
/// „Keller" ist das frühere kalte Blaugrau, „Hell" das Etikettenpapier.
enum Appearance: String, CaseIterable, Identifiable {
    case schwarz, keller, hell, system

    var id: String { rawValue }

    /// Unbekannte oder alte Werte (früher hiess Schwarz' Vorgänger „dunkel") landen bei Schwarz.
    static var current: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .schwarz
    }

    var label: String {
        switch self {
        case .schwarz: return "Schwarz"
        case .keller:  return "Keller"
        case .hell:    return "Hell"
        case .system:  return "Automatisch"
        }
    }

    var caption: String {
        switch self {
        case .schwarz: return "Reines Schwarz"
        case .keller:  return "Kaltes Blaugrau"
        case .hell:    return "Etikettenpapier"
        case .system:  return "Wie das iPhone"
        }
    }

    /// `nil` heisst: nichts erzwingen, das System entscheidet.
    var scheme: ColorScheme? {
        switch self {
        case .schwarz, .keller: return .dark
        case .hell:             return .light
        case .system:           return nil
        }
    }

    /// Welche Farben gelten, wenn das iPhone dunkel ist. „Automatisch" nimmt nachts Schwarz.
    var darkPalette: Palette { self == .keller ? .keller : .schwarz }
}
