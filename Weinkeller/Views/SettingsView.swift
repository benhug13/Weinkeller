import SwiftUI
import SwiftData

/// Kühlschränke einstellen, Hintergrund wählen, bestehende Liste übernehmen.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Fridge.order) private var fridges: [Fridge]
    @Query private var wines: [Wine]
    @Query private var bottles: [Bottle]

    @AppStorage("appearance") private var appearanceRaw = Appearance.schwarz.rawValue
    @AppStorage("settingsDesignOpen") private var designOpen = false
    @AppStorage("backdrop") private var backdropRaw = Backdrop.schlicht.rawValue
    @AppStorage("backdropStrength") private var strength: Double = 1.0

    @AppStorage("onboarded") private var onboarded = false

    @State private var importing = false
    @State private var alert: String?
    @State private var confirmingReset = false

    private var backdrop: Backdrop { Backdrop(rawValue: backdropRaw) ?? .schlicht }
    private var appearance: Appearance { Appearance(rawValue: appearanceRaw) ?? .schwarz }
    private var inCellar: Int { bottles.filter { !$0.isDrunk }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Einstellungen")
                        .font(Theme.pageTitle)
                        .foregroundStyle(Theme.cream)
                        .padding(.top, 4)

                    designSection
                    fridgeSection
                    listSection
                    priceSection
                    statsSection
                    resetSection
                    aboutSection
                }
                .padding(18)
            }
            .background(AmbientBackground())
            .scrollContentBackground(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $importing) { ImportView() }
            .alert("Geht nicht",
                   isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
                Button("Verstanden", role: .cancel) { alert = nil }
            } message: {
                Text(alert ?? "")
            }
        }
    }

    // MARK: - Design

    /// Ganz oben, aber zugeklappt: wer nur Regale einstellen will, sieht einen Balken,
    /// keine Farbmuster. Aufgeklappt bleibt es offen, bis man es wieder zuklappt.
    private var designSection: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.snappy(duration: 0.3)) { designOpen.toggle() }
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.wineLit)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Design")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.cream)
                            Text("\(appearance.label) · Hintergrund \(backdrop.label)")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .rotationEffect(.degrees(designOpen ? 180 : 0))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if designOpen {
                    Rectangle().fill(Theme.edge(0.07)).frame(height: 0.7)
                    VStack(alignment: .leading, spacing: 18) {
                        themeChooser
                        backdropChooser
                    }
                    .padding(16)
                    .transition(.opacity)
                }
            }
        }
    }

    private var themeChooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Farben")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(Appearance.allCases) { option in
                    Button { appearanceRaw = option.rawValue } label: {
                        ThemeTile(option: option, selected: option == appearance)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var backdropChooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Hintergrund")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Backdrop.allCases) { option in
                        Button { backdropRaw = option.rawValue } label: {
                            Text(option.label)
                                .font(.system(size: 13))
                                .foregroundStyle(option == backdrop ? Color.white : Theme.muted)
                                .padding(.horizontal, 13).padding(.vertical, 7)
                                .background { Capsule().fill(option == backdrop ? Theme.wine : .clear) }
                                .overlay {
                                    Capsule().strokeBorder(option == backdrop ? .clear : Theme.edge(0.14),
                                                           lineWidth: 0.8)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if backdrop != .schlicht {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Stärke").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(Int(strength * 100)) %")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(Theme.muted)
                    }
                    Slider(value: $strength, in: 0.2...1.4).tint(Theme.wine)
                }
            }

            Text("„Schlicht“ ist die reine Grundfarbe ohne alles. Die farbigen Scheine sind Geschmackssache.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedDim)
        }
    }

    // MARK: - Kühlschränke

    private var fridgeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Kühlschränke")
            Text("Stell die Regale so ein, wie sie wirklich im Gerät sind. Ein Fach ist ein Platz für eine Flasche.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedDim)
                .padding(.bottom, 2)

            ForEach(fridges) { fridge in
                fridgeCard(fridge)
            }

            SecondaryButton(title: "Kühlschrank hinzufügen", systemImage: "plus", action: addFridge)
        }
    }

    private func fridgeCard(_ fridge: Fridge) -> some View {
        let capacity = fridge.sortedShelves.reduce(0) { $0 + $1.slots }

        return Card(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    TextField("Name", text: Binding(
                        get: { fridge.name },
                        set: { fridge.name = $0.isEmpty ? "Kühlschrank" : $0 }))
                        .font(Theme.serif(19))
                        .foregroundStyle(Theme.cream)
                    Spacer()
                    Text("\(fridge.bottleCount) / \(capacity)")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                Rectangle().fill(.white.opacity(0.07)).frame(height: 0.7)

                ForEach(fridge.sortedShelves) { shelf in
                    shelfRow(shelf, in: fridge)
                    Rectangle().fill(.white.opacity(0.07)).frame(height: 0.7).padding(.leading, 16)
                }

                HStack(spacing: 18) {
                    Button("Regal hinzufügen") { addShelf(to: fridge) }
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.wineLit)
                    Spacer()
                    Button("Löschen") { deleteFridge(fridge) }
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0xD1687E))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
        }
    }

    private func shelfRow(_ shelf: Shelf, in fridge: Fridge) -> some View {
        HStack(spacing: 12) {
            Text(shelf.name)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text("\(shelf.slots) Fächer")
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(Theme.cream)

            HStack(spacing: 0) {
                stepButton("minus") { setSlots(shelf.slots - 1, on: shelf) }
                Rectangle().fill(.white.opacity(0.12)).frame(width: 0.8, height: 18)
                stepButton("plus") { setSlots(shelf.slots + 1, on: shelf) }
            }
            .background(Capsule().fill(.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.8))

            Button {
                deleteShelf(shelf, in: fridge)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.mutedDim)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .frame(width: 34, height: 30)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bestehende Liste

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: wines.isEmpty ? "Bestehende Liste" : "Weitere Sammlung")
            Button { importing = true } label: {
                Card {
                    HStack(spacing: 13) {
                        Image(systemName: "tablecells")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.wineLit)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(wines.isEmpty ? "Liste übernehmen" : "Weitere Liste dazunehmen")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.cream)
                            // Typischer Fall: eine ganze Sammlung dazugekauft, samt Liste des Vorbesitzers.
                            Text(wines.isEmpty
                                 ? "Excel, Word, PDF, Text oder Foto — nichts abtippen."
                                 : "Neue Sammlung gekauft? Ihre Liste kommt zu deinem Keller dazu — nichts wird ersetzt.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.mutedDim)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Preise

    private var winesWithoutPrice: Int { wines.filter { ($0.price ?? 0) <= 0 }.count }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Preise")
            NavigationLink { PriceBatchView() } label: {
                Card {
                    HStack(spacing: 13) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.wineLit)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Preise im Internet suchen")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.cream)
                            Text(winesWithoutPrice == 0
                                 ? "Alle Weine haben einen Preis."
                                 : "\(winesWithoutPrice) \(winesWithoutPrice == 1 ? "Wein hat" : "Weine haben") noch keinen Preis. Für Flaschen, deren Preis niemand mehr weiss.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.mutedDim)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bestand

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Bestand")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    SpecRow(key: "Weine", value: "\(wines.count)")
                    SpecRow(key: "Flaschen im Keller", value: "\(inCellar)")
                    SpecRow(key: "Katalog",
                            value: WineCatalog.shared.isEmpty ? "noch nicht gefüllt"
                                                             : "\(WineCatalog.shared.wines.count) Weine",
                            isLast: true)
                }
            }
        }
    }

    // MARK: - Von vorne beginnen

    /// Damit man die App jemandem zeigen kann, wie er sie beim ersten Mal erlebt —
    /// und damit ein verkorkster Anfang nicht das Neuinstallieren braucht.
    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Neu anfangen")
            Button { confirmingReset = true } label: {
                Card {
                    HStack(spacing: 13) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.wineLit)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Von vorne beginnen")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.cream)
                            Text("Löscht alle Weine und startet die App wie beim allerersten Mal.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.mutedDim)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .confirmationDialog("Wirklich alles löschen?",
                            isPresented: $confirmingReset,
                            titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) { startOver() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("\(wines.count) \(wines.count == 1 ? "Wein" : "Weine") und \(inCellar) \(inCellar == 1 ? "Flasche" : "Flaschen") werden gelöscht. Das lässt sich nicht rückgängig machen — bei eingeschaltetem iCloud auch auf deinen anderen Geräten.")
        }
    }

    /// Beides im selben Durchgang: SwiftUI baut die Ansicht dann in einem Zug um und
    /// diese Seite wird abgeräumt, statt nochmal auf gelöschte Objekte zuzugreifen.
    private func startOver() {
        onboarded = false
        FreshStart.wipe(context)
    }

    // MARK: - Über

    private var aboutSection: some View {
        VStack(alignment: .center, spacing: 4) {
            Wordmark(size: 30, color: Theme.muted)
            Text("Alles bleibt auf diesem Gerät.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.mutedDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Keller ändern

    /// Fächer dürfen nur so weit schrumpfen, wie hinten keine Flasche steht.
    private func setSlots(_ value: Int, on shelf: Shelf) {
        let want = max(1, min(60, value))
        let stranded = shelf.bottlesInCellar.filter { $0.slot >= want }
        guard stranded.isEmpty else {
            alert = "In \(shelf.name) stehen \(stranded.count) Flaschen auf einem Fach, das dann wegfiele. Lager sie zuerst um."
            return
        }
        shelf.slots = want
        try? context.save()
    }

    private func addShelf(to fridge: Fridge) {
        let count = fridge.sortedShelves.count
        let shelf = Shelf(name: "Regal \(count + 1)", slots: 8, order: count)
        shelf.fridge = fridge
        context.insert(shelf)
        try? context.save()
    }

    private func deleteShelf(_ shelf: Shelf, in fridge: Fridge) {
        guard shelf.bottlesInCellar.isEmpty else {
            alert = "In \(shelf.name) stehen noch \(shelf.bottlesInCellar.count) Flaschen. Lager sie zuerst um."
            return
        }
        context.delete(shelf)
        try? context.save()
    }

    private func addFridge() {
        let fridge = Fridge(name: "Kühlschrank \(fridges.count + 1)", order: fridges.count)
        context.insert(fridge)
        let shelf = Shelf(name: "Regal 1", slots: 8, order: 0)
        shelf.fridge = fridge
        context.insert(shelf)
        try? context.save()
    }

    private func deleteFridge(_ fridge: Fridge) {
        guard fridge.bottleCount == 0 else {
            alert = "In \(fridge.name) stehen noch \(fridge.bottleCount) Flaschen. Lager sie zuerst um."
            return
        }
        context.delete(fridge)
        try? context.save()
    }
}
