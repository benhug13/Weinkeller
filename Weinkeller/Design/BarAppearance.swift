import SwiftUI
import UIKit

/// Leisten oben und unten dunkel und durchscheinend machen.
///
/// SwiftUI allein reicht hier nicht: ohne diese Einstellung zeichnet iOS die Tab-Leiste als
/// **hellgrauen Balken**, der im dunklen Keller-Look wie ein Fremdkörper sitzt. Über die
/// UIKit-Erscheinung bekommt sie denselben Milchglas-Effekt wie die Karten.
enum BarAppearance {
    static func apply() {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let ground = UIColor(Theme.bg).withAlphaComponent(0.45)

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundEffect = blur
        tab.backgroundColor = ground
        tab.shadowColor = UIColor.white.withAlphaComponent(0.10)   // feine Lichtkante statt harter Linie
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Oben zwei Zustände, sonst stimmt der Farbton nicht:
        //
        // 1. **Ganz oben, nicht gescrollt:** komplett durchsichtig. Nur so hat der Balken
        //    exakt dieselbe Farbe wie die Seite — jede eigene Fläche, auch Milchglas,
        //    ist ein anderer Ton und man sieht einen hellen Streifen.
        // 2. **Sobald gescrollt wird:** Milchglas, damit der Titel über dem
        //    durchlaufenden Inhalt lesbar bleibt.
        let titles: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor(Theme.cream)]

        let navTop = UINavigationBarAppearance()
        navTop.configureWithTransparentBackground()
        navTop.backgroundEffect = nil
        navTop.backgroundColor = .clear
        navTop.shadowColor = .clear
        navTop.titleTextAttributes = titles
        navTop.largeTitleTextAttributes = titles

        let navScrolled = UINavigationBarAppearance()
        navScrolled.configureWithTransparentBackground()
        navScrolled.backgroundEffect = blur
        navScrolled.backgroundColor = ground
        navScrolled.shadowColor = UIColor.white.withAlphaComponent(0.08)
        navScrolled.titleTextAttributes = titles
        navScrolled.largeTitleTextAttributes = titles

        UINavigationBar.appearance().scrollEdgeAppearance = navTop
        UINavigationBar.appearance().standardAppearance = navScrolled
        UINavigationBar.appearance().compactAppearance = navScrolled
    }
}
