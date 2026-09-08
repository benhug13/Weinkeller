import SwiftUI

/// Der Grund hinter dem Glas — vom Besitzer wählbar.
///
/// Warum überhaupt etwas: Glas braucht etwas zum Brechen. Auf einer völlig flachen Fläche
/// sieht jedes Material aus wie ein grauer Kasten. Wem das zu bunt ist, nimmt „Ruhig" —
/// dann bleiben nur die Kanten und Schatten als Tiefenwirkung.
enum Backdrop: String, CaseIterable, Identifiable {
    case schlicht, verlauf, dezent, wein, kuehl, daemmerung

    var id: String { rawValue }

    var label: String {
        switch self {
        case .schlicht:   return "Schlicht"
        case .verlauf:    return "Verlauf"
        case .dezent:     return "Dezent"
        case .wein:       return "Weinrot"
        case .kuehl:      return "Kühl"
        case .daemmerung: return "Dämmerung"
        }
    }

    struct Glow {
        let color: Color
        let center: UnitPoint
        let radius: CGFloat
        let opacity: Double
    }

    var glows: [Glow] {
        switch self {
        case .schlicht, .verlauf:
            return []
        case .dezent:
            return [
                Glow(color: Theme.wine,  center: .init(x: 0.05, y: 0.00), radius: 400, opacity: 0.22),
                Glow(color: Theme.chill, center: .init(x: 0.98, y: 0.55), radius: 430, opacity: 0.18),
            ]
        case .wein:
            return [
                Glow(color: Theme.wine,    center: .init(x: 0.02, y: 0.00), radius: 380, opacity: 0.50),
                Glow(color: Theme.chill,   center: .init(x: 0.95, y: 0.30), radius: 300, opacity: 0.30),
                Glow(color: Theme.wine,    center: .init(x: 0.30, y: 0.62), radius: 320, opacity: 0.22),
            ]
        case .kuehl:
            return [
                Glow(color: Theme.chill,               center: .init(x: 0.10, y: 0.05), radius: 400, opacity: 0.45),
                Glow(color: Color(hex: 0x3A6E7A),      center: .init(x: 0.95, y: 0.60), radius: 380, opacity: 0.30),
            ]
        case .daemmerung:
            return [
                Glow(color: Color(hex: 0x7A3A1F),      center: .init(x: 0.08, y: 0.02), radius: 380, opacity: 0.40),
                Glow(color: Theme.wine,                center: .init(x: 0.90, y: 0.45), radius: 340, opacity: 0.32),
                Glow(color: Color(hex: 0x2B3A5C),      center: .init(x: 0.40, y: 0.95), radius: 380, opacity: 0.30),
            ]
        }
    }
}

struct AmbientBackground: View {
    @AppStorage("backdrop") private var backdropRaw = Backdrop.schlicht.rawValue
    @AppStorage("backdropStrength") private var strength: Double = 1.0

    private var backdrop: Backdrop { Backdrop(rawValue: backdropRaw) ?? .schlicht }

    var body: some View {
        BackdropCanvas(backdrop: backdrop, strength: strength)
            .ignoresSafeArea()
    }
}

/// Ohne @AppStorage — damit die Einstellungen eine Vorschau zeigen können.
struct BackdropCanvas: View {
    let backdrop: Backdrop
    var strength: Double = 1.0

    var body: some View {
        ZStack {
            Theme.bg

            // „Verlauf" ist bewusst kein Farbfleck, sondern eine ruhige Fläche,
            // die nach unten hin ganz leicht aufhellt — Tiefe ohne Grafik.
            if backdrop == .verlauf {
                LinearGradient(
                    colors: [Color(hex: 0x10141B), Theme.bg, Color(hex: 0x1A212B)],
                    startPoint: .top, endPoint: .bottom)
                    .opacity(min(1, strength))
            }

            ForEach(Array(backdrop.glows.enumerated()), id: \.offset) { _, glow in
                RadialGradient(colors: [glow.color.opacity(glow.opacity * strength), .clear],
                               center: glow.center, startRadius: 8, endRadius: glow.radius)
            }
        }
    }
}
