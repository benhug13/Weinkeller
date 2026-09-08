import SwiftUI

/// Der glasige Look.
///
/// ⚠️ **Warum nicht Apples echtes `.glassEffect()`?** Das gibt es erst im iOS-26-SDK, und
/// dieser Mac hat Xcode 15.2 mit iOS 17.2 — das Symbol existiert dort gar nicht, es liesse
/// sich nicht einmal übersetzen. Darum hier derselbe Look aus `.ultraThinMaterial`, einer
/// leichten Eigenfarbe und einer Lichtkante.
///
/// **Beim Umstieg auf Xcode Cloud (iOS 26):** nur `glassPanel` unten anpassen —
/// `.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: radius))` unter
/// `if #available(iOS 26, *)`. Alle Ansichten benutzen ausschliesslich diese Funktion,
/// sonst ist nirgends Glas verdrahtet.
extension View {
    func glassPanel(radius: CGFloat = 22,
                    tint: Color = Theme.glassTint,
                    highlight: Double = 0.38,
                    shadow: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background {
                shape.fill(.ultraThinMaterial)
                shape.fill(tint)
            }
            .overlay {
                // Lichtkante: oben links hell, unten rechts fast weg — wie eine Glaskante.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(highlight), .white.opacity(0.06), .white.opacity(highlight * 0.35)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(shadow ? 0.34 : 0), radius: 16, y: 8)
    }
}

/// Runder Glasknopf für die Werkzeugleiste.
struct GlassIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .frame(width: 34, height: 34)
                .glassPanel(radius: 17, highlight: 0.34, shadow: false)
        }
    }
}
