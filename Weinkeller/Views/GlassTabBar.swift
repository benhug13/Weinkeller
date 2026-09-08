import SwiftUI

/// Die schwebende Tab-Leiste.
///
/// ⚠️ **Das ist ein Nachbau.** Ab iOS 26 macht das System aus einer normalen `TabView` von
/// selbst so eine runde Glas-Kapsel — aber nur, wenn die App **mit dem iOS-26-SDK gebaut**
/// wurde. Dieser Mac hat Xcode 15.2, hier bliebe es sonst der alte durchgehende Balken.
///
/// **Beim Xcode-Cloud-Build (iOS 26) prüfen:** dann reicht wieder die normale `TabView`,
/// und dieser Nachbau kann raus — die echte Leiste kann Dinge, die ein Nachbau nicht kann
/// (sie schrumpft beim Scrollen und verschmilzt mit dem Inhalt darunter).
enum Tab: String, CaseIterable, Identifiable {
    case start, weine, einstellungen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .start:         return "Start"
        case .weine:         return "Weine"
        case .einstellungen: return "Einstellungen"
        }
    }

    var icon: String {
        switch self {
        case .start:         return "house.fill"
        case .weine:         return "wineglass.fill"
        case .einstellungen: return "gearshape.fill"
        }
    }
}

struct GlassTabBar: View {
    @Binding var selection: Tab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selection == tab ? Theme.cream : Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selection == tab {
                            // Die Auswahl gleitet mit, statt zu springen.
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.wineLit, Theme.wine],
                                                     startPoint: .top, endPoint: .bottom))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.20), lineWidth: 0.8))
                                .matchedGeometryEffect(id: "auswahl", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
            }
        }
        .padding(5)
        // Bewusst NICHT durchscheinend: Ben will unten nichts durchschimmern sehen.
        .background {
            Capsule().fill(Theme.panel)
        }
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.13), lineWidth: 0.8)
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.40), radius: 16, y: 6)
        .padding(.horizontal, 22)
    }
}
