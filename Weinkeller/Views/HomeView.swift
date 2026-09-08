import SwiftUI
import SwiftData

/// Die Startseite: was der Keller wert ist, was heute dran wäre, und wie voll die Geräte sind.
struct HomeView: View {
    @Query(sort: \Fridge.order) private var fridges: [Fridge]
    @Query private var wines: [Wine]
    @Query private var bottles: [Bottle]

    @State private var scanning = false
    @State private var openBottle: Bottle?

    private var inCellar: [Bottle] { bottles.filter { !$0.isDrunk } }
    private var unplaced: [Bottle] { inCellar.filter { !$0.hasPlace } }

    private var cellarValue: Double {
        inCellar.reduce(0) { $0 + ($1.wine?.price ?? 0) }
    }

    /// Flaschen, die jetzt im Trinkfenster stehen — die jüngste Empfehlung zuerst.
    private var readyNow: [Bottle] {
        inCellar.filter { bottle in
            guard let wine = bottle.wine else { return false }
            switch wine.drinkStatus {
            case .ready, .lastCall: return true
            default: return false
            }
        }
    }

    private var overdue: [Bottle] {
        inCellar.filter {
            if case .past = $0.wine?.drinkStatus { return true }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleRow
                    valueCard
                    unplacedCard
                    recommendation
                    counters
                    fridgeSection
                    factsSection
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AmbientBackground())
            .scrollContentBackground(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $scanning) { ScanFlowView() }
            .sheet(item: $openBottle) { BottleDetailView(bottle: $0) }
        }
    }

    // MARK: - Titel

    /// Steht im Inhalt statt in einer Navigationsleiste — dadurch fällt der graue
    /// Balken oben weg und der Titel sitzt wirklich zuoberst.
    private var titleRow: some View {
        HStack(alignment: .center) {
            Text("Weinkeller")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.cream)
            Spacer()
            GlassIconButton(systemName: "viewfinder") { scanning = true }
                .accessibilityLabel("Flasche scannen")
        }
        .padding(.top, 4)
    }

    // MARK: - Wert

    private var valueCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Wert im Keller")
                Text(cellarValue > 0 ? cellarValue.formatted(.currency(code: "CHF").precision(.fractionLength(0)))
                                     : "—")
                    .font(Theme.serif(38))
                    .foregroundStyle(Theme.cream)
                Text("\(inCellar.count) Flaschen · \(wines.count) Weine")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                if cellarValue == 0 && !inCellar.isEmpty {
                    Text("Trag bei den Weinen einen Preis ein, dann steht hier der Wert.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedDim)
                }
            }
        }
    }

    /// Nach dem Übernehmen einer Excel-Liste stehen oft viele Flaschen ohne Fach da.
    /// Der Hinweis verschwindet von selbst, sobald alles eingeräumt ist.
    @ViewBuilder
    private var unplacedCard: some View {
        if !unplaced.isEmpty {
            NavigationLink {
                UnplacedView()
            } label: {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "tray.full")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.wineLit)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(unplaced.count) Flaschen ohne Platz")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.cream)
                            Text("Noch einräumen")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.mutedDim)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empfehlung

    @ViewBuilder
    private var recommendation: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Heute trinken")

            if let pick = readyNow.first, let wine = pick.wine {
                Button { openBottle = pick } label: {
                    Card {
                        HStack(spacing: 14) {
                            LabelThumb(wine: wine, width: 54, height: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(wine.name)
                                    .font(Theme.serif(19))
                                    .foregroundStyle(Theme.cream)
                                    .multilineTextAlignment(.leading)
                                Text([wine.producer, wine.vintage].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.muted)
                                HStack(spacing: 6) {
                                    TypeDot(type: wine.type)
                                    Text(wine.drinkStatus.label)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.wineLit)
                                }
                                Text(pick.placeLabel)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.mutedDim)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Card {
                    Text(inCellar.isEmpty
                         ? "Noch keine Flasche im Keller. Scann eine oder tipp im Keller auf ein freies Fach."
                         : "Gerade steht nichts im Trinkfenster. Trag bei deinen Weinen Jahrgang und Traube ein — dann rechnet die App die Trinkreife aus.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var counters: some View {
        HStack(spacing: 10) {
            counter(value: readyNow.count, label: "trinkreif", tint: Theme.wineLit)
            counter(value: overdue.count, label: "über der Zeit", tint: Theme.typeSuess)
        }
    }

    private func counter(value: Int, label: String, tint: Color) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(Theme.serif(26))
                    .foregroundStyle(value == 0 ? Theme.mutedDim : tint)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: - Kühlschränke

    private var fridgeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: fridges.count == 1 ? "Dein Kühlschrank" : "Deine Kühlschränke")

            ForEach(fridges) { fridge in
                let capacity = fridge.sortedShelves.reduce(0) { $0 + $1.slots }
                NavigationLink {
                    FridgeView(fridge: fridge)
                } label: {
                    Card {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(fridge.name)
                                    .font(Theme.serif(18))
                                    .foregroundStyle(Theme.cream)
                                Spacer()
                                Text("\(fridge.bottleCount) von \(capacity)")
                                    .font(.system(size: 13).monospacedDigit())
                                    .foregroundStyle(Theme.muted)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.mutedDim)
                            }
                            FillBar(ratio: capacity > 0 ? Double(fridge.bottleCount) / Double(capacity) : 0)
                            Text("\(fridge.sortedShelves.count) Regale · \(max(0, capacity - fridge.bottleCount)) Fächer frei")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.mutedDim)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Zahlen

    @ViewBuilder
    private var factsSection: some View {
        if !inCellar.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Zahlen")
                Card {
                    VStack(spacing: 0) {
                        if let dearest = inCellar.compactMap(\.wine).max(by: { ($0.price ?? 0) < ($1.price ?? 0) }),
                           let price = dearest.price, price > 0 {
                            factRow("Teuerste Flasche", dearest.name,
                                    price.formatted(.currency(code: "CHF").precision(.fractionLength(0))))
                        }
                        if let oldest = inCellar.compactMap(\.wine).filter({ !$0.vintage.isEmpty })
                            .min(by: { $0.vintage < $1.vintage }) {
                            factRow("Ältester Jahrgang", oldest.name, oldest.vintage)
                        }
                        if let region = topRegion {
                            factRow("Meiste Weine aus", region.name, "\(region.count)")
                        }
                        factRow("Rot / Weiss", "",
                                "\(count(of: .rot)) / \(count(of: .weiss))")
                    }
                }
            }
        }
    }

    private var topRegion: (name: String, count: Int)? {
        let regions = inCellar.compactMap(\.wine?.region).filter { !$0.isEmpty }
        guard !regions.isEmpty else { return nil }
        let tally = Dictionary(grouping: regions, by: { $0 }).mapValues(\.count)
        guard let best = tally.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, best.value)
    }

    private func count(of type: WineType) -> Int {
        inCellar.filter { $0.wine?.type == type }.count
    }

    private func factRow(_ key: String, _ middle: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            if !middle.isEmpty {
                Text(middle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(value)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(Theme.cream)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.07)).frame(height: 0.7) }
    }
}

/// Etikettfoto, oder ein Ersatz mit dem Anfangsbuchstaben in der Farbe der Weinart.
struct LabelThumb: View {
    let wine: Wine
    var width: CGFloat = 42
    var height: CGFloat = 56

    var body: some View {
        Group {
            if let data = wine.photo, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.panel2.overlay {
                    Text(String(wine.name.prefix(1)).uppercased())
                        .font(Theme.serif(width * 0.4))
                        .foregroundStyle(wine.type.color)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
        }
    }
}
