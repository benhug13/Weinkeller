import SwiftUI
import UIKit

/// Ein vollständiger Farbsatz. Drei davon gibt es: Schwarz, Keller, Hell.
///
/// Die Farben kommen aus dem Gegenstand selbst: kaltes Glas und Metall vom Kühlschrank,
/// Papier vom Etikett, und die Farben, die der Wein im Glas hat.
struct Palette: Equatable {
    var bg: UInt32
    var panel: UInt32
    var panel2: UInt32
    var frost: UInt32
    var cream: UInt32
    var muted: UInt32
    var mutedDim: UInt32
    var wine: UInt32
    var wineLit: UInt32
    var chill: UInt32
    var glassTint: UInt32, glassTintAlpha: Double
    var glassSolid: UInt32, glassSolidAlpha: Double
    var typeRot: UInt32, typeWeiss: UInt32, typeRose: UInt32, typeSchaum: UInt32, typeSuess: UInt32
    var gradientTop: UInt32, gradientBottom: UInt32
    var isDark: Bool

    /// Reines Schwarz. Die Karten sind reines Milchglas wie bei EwigesWissen — ohne
    /// Eigenfarbe, sonst werden sie grau und matt.
    static let schwarz = Palette(
        bg: 0x000000, panel: 0x141416, panel2: 0x1C1C1F, frost: 0x2A2A2E,
        cream: 0xF2EEE8, muted: 0x8E8E93, mutedDim: 0x5C5C61,
        wine: 0x8E1F3A, wineLit: 0xC2415F, chill: 0x2E4C6B,
        glassTint: 0xFFFFFF, glassTintAlpha: 0,   // wie EwigesWissen: reines Milchglas
        glassSolid: 0x0B0B0C, glassSolidAlpha: 0.70,
        typeRot: 0xA32544, typeWeiss: 0xD8C77A, typeRose: 0xD98A8A, typeSchaum: 0xA8B8C4, typeSuess: 0xB5762E,
        gradientTop: 0x000000, gradientBottom: 0x111114,
        isDark: true)

    /// Das frühere Kellerdunkel: kaltes Blaugrau wie ein Kühlschrank bei Nacht.
    static let keller = Palette(
        bg: 0x14181F, panel: 0x1D232D, panel2: 0x232B37, frost: 0x2A323F,
        cream: 0xEDE6DA, muted: 0x8B94A3, mutedDim: 0x5C6472,
        wine: 0x8E1F3A, wineLit: 0xC2415F, chill: 0x2E4C6B,
        glassTint: 0x9FB2C8, glassTintAlpha: 0.03,
        glassSolid: 0x121821, glassSolidAlpha: 0.55,
        typeRot: 0xA32544, typeWeiss: 0xD8C77A, typeRose: 0xD98A8A, typeSchaum: 0xA8B8C4, typeSuess: 0xB5762E,
        gradientTop: 0x10141B, gradientBottom: 0x1A212B,
        isDark: true)

    /// Dunkle Tinte auf Etikettenpapier. Blasse Weinfarben wären auf Papier unsichtbar —
    /// darum sind sie hier satter.
    static let hell = Palette(
        bg: 0xF6F2EA, panel: 0xFFFFFF, panel2: 0xF0EAE0, frost: 0xDED6C8,
        cream: 0x1B202A, muted: 0x6A7280, mutedDim: 0x9AA1AD,
        wine: 0x8E1F3A, wineLit: 0xA82A4A, chill: 0x7C9DBB,
        glassTint: 0xFFFFFF, glassTintAlpha: 0.55,
        glassSolid: 0xFFFFFF, glassSolidAlpha: 0.70,
        typeRot: 0x8E1F3A, typeWeiss: 0x9C7C18, typeRose: 0xC0605F, typeSchaum: 0x627A8A, typeSuess: 0x9A6220,
        gradientTop: 0xFBF8F2, gradientBottom: 0xEDE6D9,
        isDark: false)

    /// Der Satz, der gerade gilt: im Hellen immer Papier, im Dunkeln Schwarz oder Keller.
    static func active(for trait: UITraitCollection) -> Palette {
        trait.userInterfaceStyle == .dark ? Appearance.current.darkPalette : .hell
    }
}

/// **Jeder Name hier ist eine Rolle, keine Farbe.** `bg` ist immer der Grund, `cream` immer
/// die Hauptschrift. Jede Farbe schlägt beim Zeichnen im gerade gültigen Farbsatz nach —
/// darum wechselt die ganze App ihr Design, ohne dass eine einzige Ansicht davon weiss.
enum Theme {
    static var bg: Color       { role(\.bg) }
    static var panel: Color    { role(\.panel) }
    static var panel2: Color   { role(\.panel2) }
    static var frost: Color    { role(\.frost) }
    static var cream: Color    { role(\.cream) }
    static var muted: Color    { role(\.muted) }
    static var mutedDim: Color { role(\.mutedDim) }
    static var wine: Color     { role(\.wine) }
    static var wineLit: Color  { role(\.wineLit) }
    static var chill: Color    { role(\.chill) }

    /// Eigenfarbe der Glasflächen — so wenig, dass es nur hebt, nicht färbt.
    static var glassTint: Color  { role(\.glassTint, alpha: \.glassTintAlpha) }
    /// Dichteres Glas für Flächen, die sich deutlich vom Inhalt abheben müssen.
    static var glassSolid: Color { role(\.glassSolid, alpha: \.glassSolidAlpha) }

    static var typeRot: Color    { role(\.typeRot) }
    static var typeWeiss: Color  { role(\.typeWeiss) }
    static var typeRose: Color   { role(\.typeRose) }
    static var typeSchaum: Color { role(\.typeSchaum) }
    static var typeSuess: Color  { role(\.typeSuess) }

    /// Die Enden des Verlauf-Hintergrunds: eine Fläche, die nach unten leicht kippt.
    static var gradientTop: Color    { role(\.gradientTop) }
    static var gradientBottom: Color { role(\.gradientBottom) }

    /// Für UIKit (Navigations- und Tab-Leiste), die mit SwiftUI-Farben nichts anfangen kann.
    static func uiRole(_ key: KeyPath<Palette, UInt32>, alpha: Double = 1) -> UIColor {
        UIColor { trait in UIColor(hex: Palette.active(for: trait)[keyPath: key], alpha: alpha) }
    }

    private static func role(_ key: KeyPath<Palette, UInt32>) -> Color {
        Color(uiRole(key))
    }

    private static func role(_ key: KeyPath<Palette, UInt32>, alpha: KeyPath<Palette, Double>) -> Color {
        Color(UIColor { trait in
            let p = Palette.active(for: trait)
            return UIColor(hex: p[keyPath: key], alpha: p[keyPath: alpha])
        })
    }

    /// Die Kante am Glas. Im Dunkeln ist sie ein Lichtreflex, im Hellen ein feiner
    /// Schatten — eine weisse Kante auf hellem Grund sieht schlicht niemand.
    static func edge(_ strength: Double) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: strength)
                : UIColor(white: 0, alpha: strength * 0.28)
        })
    }

    /// Schlagschatten. Im Hellen viel schwächer, sonst sieht die Seite schmutzig aus.
    static func shade(_ strength: Double) -> Color {
        Color(UIColor { trait in
            UIColor(white: 0, alpha: trait.userInterfaceStyle == .dark ? strength : strength * 0.40)
        })
    }

    /// Weinnamen stehen in einer Serifenschrift — so wie auf dem Etikett selbst.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Der Markenname und die Seitentitel stehen in Schreibschrift — dieselbe, mit der
    /// sich der Name beim Willkommen schreibt. Auf iOS immer vorhanden, kein Nachladen.
    static func script(_ size: CGFloat) -> Font {
        .custom("SnellRoundhand-Black", size: size)
    }

    /// Ein Seitentitel. Schreibschrift trägt optisch kleiner als Systemfett — darum
    /// deutlich grösser als die 34 pt, die hier vorher standen.
    static var pageTitle: Font { script(44) }

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

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(red:   CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >>  8) & 0xFF) / 255,
                  blue:  CGFloat( hex        & 0xFF) / 255,
                  alpha: alpha)
    }
}
