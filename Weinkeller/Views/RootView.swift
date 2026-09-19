import SwiftUI
import SwiftData

struct RootView: View {
    @State private var tab: Tab = .start
    @AppStorage("onboarded") private var onboarded = false
    @State private var greeting = true
    @AppStorage("appearance") private var appearanceRaw = Appearance.schwarz.rawValue

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
    /// Bei jedem weiteren Start schreibt sich kurz der Name, dann ist man drin.
    @ViewBuilder
    private var main: some View {
        if onboarded {
            ZStack {
                shell
                    // Schwarz und Keller sind für das iPhone beide „dunkel" — beim Wechsel
                    // ändert sich für es nichts, also zeichnet es von selbst nicht neu.
                    // Die neue Kennung baut die Seiten frisch auf; der Tab bleibt, weil er
                    // hier oben liegt.
                    .id(appearanceRaw)
                if greeting {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                // Nur beim Start, nicht nach dem Willkommensablauf — wer gerade
                // eingerichtet hat, will nicht nochmal begrüsst werden.
                guard greeting else { return }
                try? await Task.sleep(nanoseconds: 1_150_000_000)
                withAnimation(.easeOut(duration: 0.45)) { greeting = false }
            }
        } else {
            OnboardingView()
                .onAppear { greeting = false }
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
            case "home":
                HomeView()
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
            case "walk":
                SlotWalkView()
            case "priceupdate":
                PriceUpdateView()
            case "guided":
                GuidedPlacingView()
            case "prices":
                PriceBatchView()
            case "pricelookup":
                PriceLookupView(name: "Amarone della Valpolicella Classico", producer: "Tommasi",
                                vintage: "2017", region: "Venetien") { _, _ in }
            case "fonts":
                FontProbe()
            case "onboarding":
                OnboardingView()
            case "form":
                WineFormView()
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
