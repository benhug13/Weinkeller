import SwiftUI

/// Der Name in Schreibschrift, der sich von links nach rechts selber schreibt.
///
/// Steht an genau einer Stelle, weil er an drei Orten auftaucht: beim allerersten
/// Willkommen, beim kurzen Gruss zu jedem Start und klein unten in den Einstellungen.
struct Wordmark: View {
    var size: CGFloat = 60
    var color: Color = Theme.cream
    /// 0 = noch nichts geschrieben, 1 = fertig. Animiert wird von aussen.
    var reveal: Double = 1

    var body: some View {
        Text(AppInfo.name)
            .font(Theme.script(size))
            .foregroundStyle(color)
            .mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: reveal),
                    .init(color: .clear, location: min(reveal + 0.06, 1)),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            }
    }
}

/// Kurzer Gruss bei jedem Start: der Name schreibt sich, dann ist man in der App.
///
/// Bewusst schnell — das hier ist ein Gruss, kein Vorspann. Wer die App zum Nachschauen
/// öffnet, während er vor dem Kühlschrank steht, will nicht warten.
struct SplashView: View {
    @State private var reveal: Double = 0

    var body: some View {
        ZStack {
            AmbientBackground()
            Wordmark(size: 54, reveal: reveal)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85)) { reveal = 1 }
        }
    }
}
