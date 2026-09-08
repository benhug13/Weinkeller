import SwiftUI

/// Die Farben kommen aus dem Gegenstand selbst: kaltes Glas und Metall vom Kühlschrank,
/// Papier vom Etikett, und die Farben, die der Wein im Glas hat.
enum Theme {
    static let bg       = Color(hex: 0x14181F)   // Kellerdunkel, kühles Blaugrau
    static let panel    = Color(hex: 0x1D232D)   // Gerätefront
    static let panel2   = Color(hex: 0x232B37)
    static let frost    = Color(hex: 0x2A323F)   // kaltes Metall, Schienen und Kanten
    static let cream    = Color(hex: 0xEDE6DA)   // Etikettenpapier
    static let muted    = Color(hex: 0x8B94A3)
    static let mutedDim = Color(hex: 0x5C6472)
    static let wine     = Color(hex: 0x8E1F3A)
    static let wineLit  = Color(hex: 0xC2415F)
    static let chill    = Color(hex: 0x2E4C6B)   // kühler Schein für den Hintergrund

    /// Eigenfarbe der Glasflächen — so wenig, dass es nur wärmt, nicht färbt.
    static let glassTint = Color(hex: 0x9FB2C8).opacity(0.06)

    /// Dichteres Glas für die schwebende Leiste: sie muss sich vom Inhalt darunter
    /// deutlich abheben, sonst matscht beides ineinander.
    static let glassSolid = Color(hex: 0x121821).opacity(0.55)

    static let typeRot    = Color(hex: 0xA32544)
    static let typeWeiss  = Color(hex: 0xD8C77A)
    static let typeRose   = Color(hex: 0xD98A8A)
    static let typeSchaum = Color(hex: 0xA8B8C4)
    static let typeSuess  = Color(hex: 0xB5762E)

    /// Weinnamen stehen in einer Serifenschrift — so wie auf dem Etikett selbst.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Alles, was zur Bedienung gehört, bleibt in der Systemschrift.
    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Kleines Etikett über einem Abschnitt: gesperrt, in Grossbuchstaben.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.label(11))
            .tracking(1.8)
            .foregroundStyle(Theme.muted)
    }
}
