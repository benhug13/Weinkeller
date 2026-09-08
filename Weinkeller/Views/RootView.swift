import SwiftUI
import SwiftData

struct RootView: View {
    @State private var tab: Tab = .start
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        #if DEBUG
        if let screen = ProcessInfo.processInfo.environment["WEINKELLER_SCREEN"] {
            DebugScreen(name: screen)
        } else {
            main
        }
        #else
        main
        #endif
    }

    /// Beim allerersten Start führt der Willkommensablauf durch die Einrichtung.
    @ViewBuilder
    private var main: some View {
        if onboarded {
            shell
        } else {
            OnboardingView()
        }
    }

    private var shell: some View {
        ZStack(alignment: .bottom) {
            // Ein einziger Hintergrund für alles — sonst hat der Boden einen anderen
            // Farbton als die Fläche darüber und es entsteht ein sichtbarer Streifen.
            AmbientBackground()

            Group {
                switch tab {
                case .start:         HomeView()
                case .weine:         WineListView()
                case .einstellungen: SettingsView()
                }
            }
            // Platz für die Leiste, damit unten nichts abgeschnitten endet.
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 96) }
            // Statt zuzudecken: der Inhalt wird nach unten ausgeblendet. Dadurch scrollt
            // nichts durch die Leiste und nichts unter ihr durch — und der Hintergrund
            // bleibt durchgehend derselbe.
            .mask { contentMask }

            GlassTabBar(selection: $tab)
                .padding(.bottom, 6)
        }
        .ignoresSafeArea(.keyboard)
    }

    /// Sichtbar bis kurz über der Leiste, dann weicher Übergang, darunter nichts mehr.
    private var contentMask: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 34)
            Color.clear.frame(height: 96)
        }
        .ignoresSafeArea()
    }
}

#if DEBUG
/// Springt beim Start direkt auf eine Ansicht, damit man sie ohne Antippen ansehen kann.
/// `SIMCTL_CHILD_WEINKELLER_SCREEN=fridge|wine|wines|settings xcrun simctl launch booted ch.weinkeller.app`
struct DebugScreen: View {
    let name: String
    @Query(sort: \Fridge.order) private var fridges: [Fridge]
    @Query(sort: \Wine.name) private var wines: [Wine]

    var body: some View {
        NavigationStack {
            switch name {
            case "fridge":
                if let fridge = fridges.first { FridgeView(fridge: fridge) }
            case "wines":
                WineListView()
            case "wine":
                if let wine = wines.first { WineDetailView(wine: wine) }
            case "settings":
                SettingsView()
            case "import":
                ImportView()
            case "unplaced":
                UnplacedView()
            case "fonts":
                FontProbe()
            case "onboarding":
                OnboardingView()
            default:
                Text("Unbekannte Ansicht: \(name)")
            }
        }
    }
}
#endif

#if DEBUG
/// Prüft, welche Schreibschriften auf dem Gerät wirklich da sind.
struct FontProbe: View {
    private let candidates = [
        "SnellRoundhand", "SnellRoundhand-Bold", "SnellRoundhand-Black",
        "Zapfino", "SavoyeLetPlain", "Noteworthy-Light", "Noteworthy-Bold",
        "BradleyHandITCTT-Bold", "ChalkboardSE-Regular", "SignPainter-HouseScript",
        "PartyLetPlain", "MarkerFelt-Thin", "AmericanTypewriter",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(candidates, id: \.self) { name in
                    let exists = UIFont(name: name, size: 20) != nil
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exists ? "✓ \(name)" : "✗ \(name)")
                            .font(.system(size: 11))
                            .foregroundStyle(exists ? .green : .red)
                        if exists {
                            Text("Weinkeller")
                                .font(.custom(name, size: 34))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding()
        }
        .background(.black)
    }
}
#endif
