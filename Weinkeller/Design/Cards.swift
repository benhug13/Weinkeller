import SwiftUI

/// Eine Karte. Alle Blöcke auf der Startseite sitzen in dieser Form, damit die Seite ruhig bleibt.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = 22
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: radius)
    }
}

/// Füllbalken für ein Regal oder einen ganzen Kühlschrank.
struct FillBar: View {
    let ratio: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                Capsule().fill(
                    LinearGradient(colors: [Theme.wine, Theme.wineLit],
                                   startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * min(max(ratio, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// Farbpunkt der Weinart — dasselbe Zeichen überall in der App.
struct TypeDot: View {
    let type: WineType
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(type.color).frame(width: size, height: size)
    }
}
