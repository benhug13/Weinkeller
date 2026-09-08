import SwiftUI
import SwiftData

/// Der erste Start: Name in Handschrift, dann die eine Frage, die alles Weitere bestimmt —
/// **fängst du bei null an, oder hast du schon eine Liste?**
struct OnboardingView: View {
    @AppStorage("onboarded") private var onboarded = false
    @Environment(\.modelContext) private var context
    @Query(sort: \Fridge.order) private var fridges: [Fridge]

    @State private var step: Step = {
        #if DEBUG
        // Für Screenshots: SIMCTL_CHILD_WEINKELLER_STEP=choice|setup|guide
        switch ProcessInfo.processInfo.environment["WEINKELLER_STEP"] {
        case "choice": return .choice
        case "setup":  return .setup
        case "guide":  return .guide
        default:       return .welcome
        }
        #else
        return .welcome
        #endif
    }()
    @State private var reveal: Double = 0
    @State private var importing = false

    enum Step { case welcome, choice, setup, guide }

    var body: some View {
        ZStack {
            AmbientBackground()

            switch step {
            case .welcome: welcome
            case .choice:  choice
            case .setup:   setup
            case .guide:   guide
            }
        }
        .sheet(isPresented: $importing, onDismiss: { finish() }) { ImportView() }
    }

    // MARK: - 1. Willkommen

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()

            // Der Name wird von links nach rechts sichtbar, als würde er geschrieben.
            Text(AppInfo.name)
                .font(.custom("SnellRoundhand-Black", size: 60))
                .foregroundStyle(Theme.cream)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: reveal),
                        .init(color: .clear, location: min(reveal + 0.06, 1)),
                        .init(color: .clear, location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
                }

            Text(AppInfo.tagline)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .padding(.horizontal, 40)
                .opacity(reveal > 0.9 ? 1 : 0)
                .animation(.easeIn(duration: 0.5), value: reveal > 0.9)

            Spacer()

            PrimaryButton(title: "Los geht's") {
                withAnimation(.snappy) { step = .choice }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .opacity(reveal > 0.9 ? 1 : 0)
            .animation(.easeIn(duration: 0.5), value: reveal > 0.9)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6)) { reveal = 1 }
        }
    }

    // MARK: - 2. Wie fängst du an?

    private var choice: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()

            Text("Wie fängst du an?")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.cream)
            Text("Beides geht — du kannst später jederzeit wechseln.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 6)

            optionCard(icon: "wineglass",
                       title: "Ich fange bei null an",
                       text: "Der Keller ist leer. Du stellst deine Kühlschränke ein und erfasst die Flaschen nach und nach.") {
                step = .setup
            }

            optionCard(icon: "tablecells",
                       title: "Ich habe schon eine Liste",
                       text: "Eine Excel- oder Numbers-Tabelle mit deinen Weinen. Die lesen wir ein, dann musst du nichts abtippen.") {
                step = .guide
            }

            Spacer()
        }
        .padding(24)
    }

    private func optionCard(icon: String, title: String, text: String,
                            action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Card {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.wineLit)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(Theme.serif(19))
                            .foregroundStyle(Theme.cream)
                            .multilineTextAlignment(.leading)
                        Text(text)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3a. Kühlschränke einstellen

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Deine Kühlschränke")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.cream)
                Text("Stell sie so ein, wie sie wirklich dastehen. Ein Fach ist ein Platz für eine Flasche. Ändern kannst du das jederzeit in den Einstellungen.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)

                ForEach(fridges) { fridge in
                    fridgeCard(fridge)
                }

                SecondaryButton(title: "Kühlschrank hinzufügen", systemImage: "plus") {
                    addFridge()
                }

                PrimaryButton(title: "Fertig — Keller ist eingerichtet") { finish() }
                    .padding(.top, 6)
            }
            .padding(24)
        }
    }

    private func fridgeCard(_ fridge: Fridge) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: Binding(
                    get: { fridge.name },
                    set: { fridge.name = $0.isEmpty ? "Kühlschrank" : $0 }))
                    .font(Theme.serif(19))
                    .foregroundStyle(Theme.cream)

                Stepper(value: Binding(
                    get: { fridge.sortedShelves.count },
                    set: { setShelfCount($0, for: fridge) }), in: 1...20) {
                    HStack {
                        Text("Regale").foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(fridge.sortedShelves.count)")
                            .font(.system(size: 15).monospacedDigit())
                            .foregroundStyle(Theme.cream)
                    }
                }

                Stepper(value: Binding(
                    get: { fridge.sortedShelves.first?.slots ?? 8 },
                    set: { value in fridge.sortedShelves.forEach { $0.slots = value } }), in: 1...40) {
                    HStack {
                        Text("Fächer pro Regal").foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(fridge.sortedShelves.first?.slots ?? 8)")
                            .font(.system(size: 15).monospacedDigit())
                            .foregroundStyle(Theme.cream)
                    }
                }

                Text("Platz für \(fridge.sortedShelves.reduce(0) { $0 + $1.slots }) Flaschen")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedDim)
            }
        }
    }

    // MARK: - 3b. Anleitung zur Liste

    private var guide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Deine Liste einlesen")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.cream)

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        guideStep(1, "In **Excel oder Numbers**: Datei → Speichern unter → **CSV UTF-8**.")
                        guideStep(2, "Die Datei aufs iPhone bringen — **AirDrop**, Mail an dich selbst oder iCloud Drive.")
                        guideStep(3, "Hier auswählen. Die App zeigt dir die Spalten, und du sagst, **welche was ist**.")
                        guideStep(4, "Steht in der Liste schon Regal und Fach, werden die Flaschen gleich eingeräumt. Sonst landen sie unter **„Noch einräumen“**.")
                    }
                }

                Card {
                    Text("Alles bleibt auf deinem Gerät. Nichts geht ins Internet.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }

                PrimaryButton(title: "Datei auswählen", systemImage: "doc.badge.plus") {
                    importing = true
                }
                SecondaryButton(title: "Später — erst Kühlschränke einstellen") {
                    withAnimation(.snappy) { step = .setup }
                }
            }
            .padding(24)
        }
    }

    private func guideStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.cream)
                .frame(width: 21, height: 21)
                .background(Circle().fill(Theme.wine))
            Text(.init(text))
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Keller anpassen

    private func setShelfCount(_ target: Int, for fridge: Fridge) {
        let shelves = fridge.sortedShelves
        let slots = shelves.first?.slots ?? 8
        if target > shelves.count {
            for index in shelves.count..<target {
                let shelf = Shelf(name: "Regal \(index + 1)", slots: slots, order: index)
                shelf.fridge = fridge
                context.insert(shelf)
            }
        } else if target < shelves.count {
            for shelf in shelves[target...] { context.delete(shelf) }
        }
    }

    private func addFridge() {
        let fridge = Fridge(name: "Kühlschrank \(fridges.count + 1)", order: fridges.count)
        context.insert(fridge)
        for index in 0..<5 {
            let shelf = Shelf(name: "Regal \(index + 1)", slots: 8, order: index)
            shelf.fridge = fridge
            context.insert(shelf)
        }
    }

    private func finish() {
        try? context.save()
        onboarded = true
    }
}

/// Name und Untertitel an einer Stelle — damit ein Namenswechsel eine Zeile ist.
enum AppInfo {
    static let name = "Weinkeller"
    static let tagline = "Dein Keller auf dem Handy.\nWelche Flasche wo liegt, und wann sie so weit ist."
}
