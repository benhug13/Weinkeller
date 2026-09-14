import SwiftUI
import SwiftData

/// Hilfe fürs Einräumen, wenn eine Liste keine Plätze hat.
///
/// Das Problem dahinter: In einer Excel- oder Word-Liste steht fast nie, **in welchem Fach**
/// eine Flasche liegt — und oft weiss es der Besitzer selber nicht mehr. Raten kann die App
/// das nicht. Aber sie kann den Weg dahin so kurz machen, dass es eine Viertelstunde vor dem
/// offenen Kühlschrank ist statt eines Abends mit Papier:
///
/// - **Nachschauen:** Die App geht Fach für Fach durch, der Besitzer tippt, welche Flasche dort
///   liegt. Gesucht wird nur unter den Flaschen **ohne Platz** — das sind wenige, darum trifft
///   auch ein schnell getippter Wortanfang oder ein gescanntes Etikett.
/// - **Neu einräumen:** Die App nimmt Flasche um Flasche und sagt, in welches Fach sie gehört.
///   Gut, wenn ohnehin alles raus und neu hinein soll.
enum PlacingMode: String, Identifiable {
    case walk, guided
    var id: String { rawValue }
}

/// Ein freies Fach, festgehalten beim Start — sonst würde sich die Reihenfolge verschieben,
/// sobald das erste Fach belegt ist.
struct SlotRef: Hashable {
    let shelf: Shelf
    let slot: Int

    var fridgeName: String { shelf.fridge?.name ?? "Kühlschrank" }
    var shortLabel: String { "\(shelf.name) · Fach \(slot + 1)" }

    static func == (a: SlotRef, b: SlotRef) -> Bool {
        a.shelf.persistentModelID == b.shelf.persistentModelID && a.slot == b.slot
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(shelf.persistentModelID)
        hasher.combine(slot)
    }

    /// Alle freien Fächer, so wie man vor dem Gerät steht: Kühlschrank, Regal von oben, Fach von links.
    static func freeSlots(in fridges: [Fridge]) -> [SlotRef] {
        fridges.flatMap { fridge in
            fridge.sortedShelves.flatMap { shelf in
                shelf.freeSlots.map { SlotRef(shelf: shelf, slot: $0) }
            }
        }
    }
}

// MARK: - Nachschauen: Fach für Fach

@MainActor
struct SlotWalkView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Fridge.order) private var fridges: [Fridge]
    @Query private var bottles: [Bottle]

    @State private var slots: [SlotRef] = []
    @State private var position = 0
    @State private var history: [(position: Int, bottle: Bottle?)] = []
    @State private var search = ""
    @State private var scanning = false
    @State private var scanHint: String?
    @FocusState private var searchFocused: Bool

    private var unplaced: [Bottle] { bottles.filter { !$0.isDrunk && !$0.hasPlace } }

    /// Ein Wein mit mehreren Flaschen erscheint einmal — man tippt „den Barolo", nicht eine von vier.
    private var candidates: [(wine: Wine, bottles: [Bottle])] {
        var byWine: [PersistentIdentifier: (Wine, [Bottle])] = [:]
        for bottle in unplaced {
            guard let wine = bottle.wine else { continue }
            byWine[wine.persistentModelID, default: (wine, [])].1.append(bottle)
        }
        let all = byWine.values.map { (wine: $0.0, bottles: $0.1) }
        let query = TextMatching.normalize(search)
        guard !query.isEmpty else {
            return all.sorted { $0.wine.name.localizedCompare($1.wine.name) == .orderedAscending }
        }
        // Wortanfänge zählen: „bar 16" findet „Barolo Cannubi 2016".
        let words = query.split(separator: " ").map(String.init)
        return all
            .filter { item in
                let hay = TextMatching.normalize(item.wine.searchText)
                let hayWords = hay.split(separator: " ")
                return words.allSatisfy { w in hayWords.contains { $0.hasPrefix(w) } || hay.contains(w) }
            }
            .sorted { $0.wine.name.localizedCompare($1.wine.name) == .orderedAscending }
    }

    private var current: SlotRef? { position < slots.count ? slots[position] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let current, !unplaced.isEmpty {
                    slotCard(current)
                    actionRow
                    searchField
                    if let scanHint {
                        Text(scanHint)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                    SectionLabel(text: "Welche Flasche liegt hier?")
                        .padding(.top, 4)
                    LazyVStack(spacing: 8) {
                        ForEach(candidates, id: \.wine.persistentModelID) { item in
                            candidateRow(item.wine, count: item.bottles.count) {
                                assign(item.bottles[0])
                            }
                        }
                    }
                    if candidates.isEmpty {
                        Text(search.isEmpty ? "" : "Keine Flasche ohne Platz passt zu „\(search)“.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    doneCard
                }
            }
            .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AmbientBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Fach für Fach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !slots.isEmpty {
                ToolbarItem(placement: .primaryAction) { jumpMenu }
            }
        }
        .onAppear {
            if slots.isEmpty { slots = SlotRef.freeSlots(in: fridges) }
        }
        .sheet(isPresented: $scanning) { scanSheet }
    }

    private func slotCard(_ ref: SlotRef) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: "Fach \(position + 1) von \(slots.count)")
                    Spacer()
                    Text("\(unplaced.count) ohne Platz")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.fridgeName)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                    Text(ref.shortLabel)
                        .font(Theme.serif(30))
                        .foregroundStyle(Theme.cream)
                }
                SlotStrip(shelf: ref.shelf, highlight: ref.slot)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if !history.isEmpty {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.cream)
                        .frame(width: 50, height: 46)
                        .glassPanel(radius: 16, highlight: 0.22, shadow: false)
                }
                .accessibilityLabel("Zurück")
            }
            SecondaryButton(title: "Fach ist leer", systemImage: "arrow.right") { skip() }
            if ScannerView.isSupported {
                Button { scanning = true } label: {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.cream)
                        .frame(width: 50, height: 46)
                        .glassPanel(radius: 16, highlight: 0.22, shadow: false)
                }
                .accessibilityLabel("Etikett scannen")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Name, Winzer oder Jahrgang", text: $search)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.cream)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.mutedDim)
                }
            }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassPanel(radius: 20, highlight: 0.22, shadow: false)
    }

    private var jumpMenu: some View {
        Menu {
            ForEach(Array(shelfStarts.enumerated()), id: \.offset) { _, entry in
                Button("\(entry.ref.fridgeName) · \(entry.ref.shelf.name)") {
                    position = entry.index
                }
            }
        } label: {
            Label("Springen", systemImage: "list.bullet")
        }
    }

    /// Erstes freies Fach jedes Regals — damit man mit dem Regal anfangen kann, vor dem man steht.
    private var shelfStarts: [(index: Int, ref: SlotRef)] {
        var seen = Set<PersistentIdentifier>()
        return slots.enumerated().compactMap { index, ref in
            seen.insert(ref.shelf.persistentModelID).inserted ? (index, ref) : nil
        }
    }

    private var doneCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(unplaced.isEmpty ? "Alles eingeräumt" : "Alle freien Fächer durch")
                        .font(Theme.serif(22))
                        .foregroundStyle(Theme.cream)
                    Text(unplaced.isEmpty
                         ? "Jede Flasche hat jetzt ihr Fach."
                         : "\(unplaced.count) \(unplaced.count == 1 ? "Flasche hat" : "Flaschen haben") noch keinen Platz. Vielleicht liegen sie woanders — im Karton oder schon getrunken. Du findest sie weiter unter „Noch einräumen“.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }
            PrimaryButton(title: "Fertig") { dismiss() }
        }
    }

    private var scanSheet: some View {
        NavigationStack {
            ScannerView(onBarcode: { code in
                if let hit = candidates.first(where: { $0.wine.barcode == code }) {
                    assign(hit.bottles[0])
                    scanHint = "Per Barcode erkannt: \(hit.wine.name)"
                } else {
                    scanHint = "Dieser Barcode gehört zu keiner Flasche ohne Platz."
                }
                scanning = false
            }, onText: { text in
                // Nur unter den Flaschen ohne Platz suchen — wenige Kandidaten, sicherer Treffer.
                let ranked = candidates
                    .map { ($0, TextMatching.score(query: text, candidate: $0.wine.searchText)) }
                    .filter { $0.1 >= 0.5 }
                    .sorted { $0.1 > $1.1 }
                guard let best = ranked.first else { return }
                if ranked.count == 1 || best.1 > ranked[1].1 {
                    search = best.0.wine.name
                    scanHint = "Erkannt: \(best.0.wine.name) — antippen zum Bestätigen."
                    scanning = false
                }
            })
            .ignoresSafeArea()
            .navigationTitle("Etikett scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { scanning = false }
                }
            }
        }
    }

    // MARK: - Aktionen

    private func assign(_ bottle: Bottle) {
        guard let ref = current else { return }
        bottle.shelf = ref.shelf
        bottle.slot = ref.slot
        try? context.save()
        history.append((position, bottle))
        advance()
    }

    private func skip() {
        history.append((position, nil))
        advance()
    }

    private func advance() {
        search = ""
        searchFocused = false
        withAnimation(.snappy(duration: 0.25)) { position += 1 }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        if let bottle = last.bottle {
            bottle.shelf = nil
            bottle.slot = 0
            try? context.save()
        }
        scanHint = nil
        withAnimation(.snappy(duration: 0.25)) { position = last.position }
    }

    private func candidateRow(_ wine: Wine, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Card(padding: 12) {
                HStack(spacing: 12) {
                    LabelThumb(wine: wine, width: 38, height: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(wine.name)
                            .font(Theme.serif(16))
                            .foregroundStyle(Theme.cream)
                            .lineLimit(1)
                        Text([wine.producer, wine.vintage].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if count > 1 {
                        Text("×\(count)")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Neu einräumen: die App sagt, wohin

struct GuidedPlacingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Fridge.order) private var fridges: [Fridge]
    @Query private var bottles: [Bottle]

    enum Order: String, CaseIterable, Identifiable {
        case type, readiness
        var id: String { rawValue }
        var label: String { self == .type ? "Nach Art" : "Nach Trinkreife" }
        var hint: String {
            self == .type
                ? "Schaumwein, Weiss, Rosé, Rot, Süss — gleiche Weine nebeneinander."
                : "Was bald getrunken werden sollte, kommt in die ersten Fächer."
        }
    }

    @State private var order: Order = .type
    @State private var queue: [Bottle] = []
    @State private var slots: [SlotRef] = []
    @State private var bottleIndex = 0
    @State private var slotIndex = 0
    @State private var history: [(bottleIndex: Int, slotIndex: Int, placed: Bool)] = []

    private var currentBottle: Bottle? { bottleIndex < queue.count ? queue[bottleIndex] : nil }
    private var currentSlot: SlotRef? { slotIndex < slots.count ? slots[slotIndex] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if history.isEmpty {
                    orderPicker
                }
                if let bottle = currentBottle, let slot = currentSlot, let wine = bottle.wine {
                    progress
                    bottleCard(wine)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.wineLit)
                        .frame(maxWidth: .infinity)
                    slotCard(slot)
                    PrimaryButton(title: "Liegt drin", systemImage: "checkmark") { place() }
                    HStack(spacing: 10) {
                        if !history.isEmpty {
                            SecondaryButton(title: "Zurück", systemImage: "arrow.uturn.backward") { undo() }
                        }
                        SecondaryButton(title: "Später", systemImage: "forward") { later() }
                    }
                } else {
                    doneCard
                }
            }
            .padding(18)
        }
        .background(AmbientBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Neu einräumen")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if queue.isEmpty && slots.isEmpty { prepare() } }
        .onChange(of: order) { prepare() }
    }

    private var orderPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Reihenfolge", selection: $order) {
                ForEach(Order.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(order.hint)
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedDim)
        }
    }

    private var progress: some View {
        HStack {
            SectionLabel(text: "Flasche \(bottleIndex + 1) von \(queue.count)")
            Spacer()
            Text("\(slots.count - slotIndex) Fächer frei")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.muted)
        }
    }

    private func bottleCard(_ wine: Wine) -> some View {
        Card {
            HStack(spacing: 14) {
                LabelThumb(wine: wine, width: 52, height: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text(wine.name)
                        .font(Theme.serif(22))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(2)
                    Text([wine.producer, wine.vintage, wine.type.label].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func slotCard(_ ref: SlotRef) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.fridgeName)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                    Text(ref.shortLabel)
                        .font(Theme.serif(30))
                        .foregroundStyle(Theme.cream)
                }
                SlotStrip(shelf: ref.shelf, highlight: ref.slot)
            }
        }
    }

    private var doneCard: some View {
        let left = bottles.filter { !$0.isDrunk && !$0.hasPlace }.count
        return VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(left == 0 ? "Alles eingeräumt" : (currentSlot == nil ? "Kein Fach mehr frei" : "Durch"))
                        .font(Theme.serif(22))
                        .foregroundStyle(Theme.cream)
                    Text(left == 0
                         ? "Jede Flasche hat jetzt ihr Fach."
                         : "\(left) \(left == 1 ? "Flasche hat" : "Flaschen haben") noch keinen Platz. Mehr Fächer gibt es in den Einstellungen unter „Kühlschränke“.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }
            PrimaryButton(title: "Fertig") { dismiss() }
        }
    }

    // MARK: - Ablauf

    private func prepare() {
        let open = bottles.filter { !$0.isDrunk && !$0.hasPlace }
        queue = open.sorted(by: order == .type ? Self.byType : Self.byReadiness)
        slots = SlotRef.freeSlots(in: fridges)
        bottleIndex = 0
        slotIndex = 0
        history = []
    }

    private func place() {
        guard let bottle = currentBottle, let slot = currentSlot else { return }
        bottle.shelf = slot.shelf
        bottle.slot = slot.slot
        try? context.save()
        history.append((bottleIndex, slotIndex, true))
        withAnimation(.snappy(duration: 0.25)) {
            bottleIndex += 1
            slotIndex += 1
        }
    }

    private func later() {
        history.append((bottleIndex, slotIndex, false))
        withAnimation(.snappy(duration: 0.25)) { bottleIndex += 1 }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        if last.placed, last.bottleIndex < queue.count {
            queue[last.bottleIndex].shelf = nil
            queue[last.bottleIndex].slot = 0
            try? context.save()
        }
        withAnimation(.snappy(duration: 0.25)) {
            bottleIndex = last.bottleIndex
            slotIndex = last.slotIndex
        }
    }

    private static let typeOrder: [WineType] = [.schaum, .weiss, .rose, .rot, .suess]

    private static func byType(_ a: Bottle, _ b: Bottle) -> Bool {
        let ta = typeOrder.firstIndex(of: a.wine?.type ?? .rot) ?? 0
        let tb = typeOrder.firstIndex(of: b.wine?.type ?? .rot) ?? 0
        if ta != tb { return ta < tb }
        return byName(a, b)
    }

    /// Dringendes zuerst: über der Zeit → jetzt trinken → trinkreif → noch zu jung → unbekannt.
    private static func byReadiness(_ a: Bottle, _ b: Bottle) -> Bool {
        func rank(_ bottle: Bottle) -> (Int, Int) {
            switch bottle.wine?.drinkStatus ?? .unknown {
            case .past(let y):     return (0, -y)
            case .lastCall:        return (1, 0)
            case .ready:           return (2, 0)
            case .tooYoung(let y): return (3, y)
            case .unknown:         return (4, 0)
            }
        }
        let ra = rank(a), rb = rank(b)
        if ra != rb { return ra < rb }
        return byName(a, b)
    }

    private static func byName(_ a: Bottle, _ b: Bottle) -> Bool {
        let na = (a.wine?.name ?? "") + (a.wine?.vintage ?? "")
        let nb = (b.wine?.name ?? "") + (b.wine?.vintage ?? "")
        return na.localizedCompare(nb) == .orderedAscending
    }
}

// MARK: - Fachleiste

/// Das Regal als Reihe kleiner Kästchen: belegt, frei, und das gesuchte Fach in Weinrot.
/// So sieht man sofort „das dritte von links", ohne zu zählen.
struct SlotStrip: View {
    let shelf: Shelf
    let highlight: Int

    var body: some View {
        let taken = Set(shelf.bottlesInCellar.map(\.slot))
        HStack(spacing: shelf.slots > 16 ? 2 : 4) {
            ForEach(0..<shelf.slots, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index == highlight ? Theme.wineLit
                          : taken.contains(index) ? Theme.frost : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(index == highlight ? Color.clear : Theme.edge(0.18), lineWidth: 0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: index == highlight ? 18 : 14)
            }
        }
        .frame(height: 18)
        .accessibilityLabel("Fach \(highlight + 1) von \(shelf.slots)")
    }
}
