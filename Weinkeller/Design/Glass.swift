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
    /// Genau der Kartenlook von [[EwigesWissen]] (Ben, 14.09.2026: „mach es so wie bei
    /// ewiges wissen"): nur Apples Milchglas, **keine** Eigenfarbe darüber, eine feine,
    /// gleichmässige Kante und ein kaum sichtbarer Schatten.
    ///
    /// Vorher lag ein helles Grau auf dem Glas, dazu eine starke Lichtkante oben links —
    /// das machte die Karten grau und hart statt glasig.
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
                shape.strokeBorder(Theme.edge(0.18), lineWidth: 0.5)
            }
            .clipShape(shape)
            .shadow(color: Theme.shade(shadow ? 0.08 : 0), radius: 14, x: 0, y: 4)
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
