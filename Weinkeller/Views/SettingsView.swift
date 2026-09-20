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

    /// Immer nur **ein** Lagerort offen. Bei drei Kühlschränken sind sonst
    /// fünfzehn Regalzeilen untereinander, und man sucht seins.
    @State private var openFridge: PersistentIdentifier?

    @State private var importing = false
    @State private var alert: String?
    @State private var confirmingReset = false
    @State private var exportFile: SharedFile?

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
                    backupSection
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
            .sheet(item: $exportFile) { file in ShareSheet(items: [file.url]).ignoresSafeArea() }
            #if DEBUG
            // Tabelle ohne Teilen-Fenster prüfen: SIMCTL_CHILD_WEINKELLER_EXPORT_TO=/pfad/keller.xlsx
            .task {
                if let path = ProcessInfo.processInfo.environment["WEINKELLER_EXPORT_TO"],
                   let url = try? CellarExport.file(wines: wines) {
                    try? FileManager.default.removeItem(atPath: path)
                    try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: path))
                }
            }
            #endif
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

    // MARK: - Lagerorte

    private var fridgeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Lagerorte")
            Text("Kühlschrank, Regal oder Kiste — stell die Ebenen so ein, wie sie wirklich dastehen. Ein Fach ist ein Platz für eine Flasche.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedDim)
                .padding(.bottom, 2)

            ForEach(fridges) { fridge in
                fridgeCard(fridge)
            }

            SecondaryButton(title: "Lagerort hinzufügen", systemImage: "plus", action: addFridge)
        }
    }

    /// Bei genau einem Lagerort gibt es nichts zu sortieren — der ist immer offen.
    private func isOpen(_ fridge: Fridge) -> Bool {
        fridges.count == 1 || openFridge == fridge.persistentModelID
    }

    private func fridgeCard(_ fridge: Fridge) -> some View {
        let capacity = fridge.sortedShelves.reduce(0) { $0 + $1.slots }
        let open = isOpen(fridge)

        return Card(padding: 0) {
            VStack(spacing: 0) {
                if open {
                    fridgeHeader(fridge, capacity: capacity, open: true)
                } else {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { openFridge = fridge.persistentModelID }
                    } label: {
                        fridgeHeader(fridge, capacity: capacity, open: false)
                    }
                    .buttonStyle(.plain)
                }

                if open {
                    Rectangle().fill(.white.opacity(0.07)).frame(height: 0.7)

                    StorageKindPicker(kind: Binding(
                        get: { fridge.kind },
                        set: { fridge.changeKind(to: $0); try? context.save() }))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                    Rectangle().fill(.white.opacity(0.07)).frame(height: 0.7)

                    ForEach(fridge.sortedShelves) { shelf in
                        shelfRow(shelf, in: fridge)
                        Rectangle().fill(.white.opacity(0.07)).frame(height: 0.7).padding(.leading, 16)
                    }

                    HStack(spacing: 18) {
                        Button("\(fridge.kind.levelWord) hinzufügen") { addShelf(to: fridge) }
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
    }

    /// Zugeklappt steht hier alles, was man zum Wiedererkennen braucht: Art, Name,
    /// wie voll er ist. Offen wird aus dem Namen ein Feld — an derselben Stelle,
    /// damit die Karte beim Aufklappen nicht springt.
    @ViewBuilder
    private func fridgeHeader(_ fridge: Fridge, capacity: Int, open: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: fridge.kind.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.wineLit)
                    .frame(width: 18)

                if open {
                    TextField("Name", text: Binding(
                        get: { fridge.name },
                        set: { fridge.name = $0.isEmpty ? fridge.kind.defaultName : $0 }))
                        .font(Theme.serif(19))
                        .foregroundStyle(Theme.cream)
                } else {
                    Text(fridge.name)
                        .font(Theme.serif(19))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("\(fridge.bottleCount) / \(capacity)")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Theme.muted)

                if fridges.count > 1 {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            openFridge = open ? nil : fridge.persistentModelID
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.mutedDim)
                            .rotationEffect(.degrees(open ? 180 : 0))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !open {
                Text("\(fridge.sortedShelves.count) \(fridge.kind.levelWordPlural) · \(max(0, capacity - fridge.bottleCount)) Fächer frei")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedDim)
                    .padding(.leading, 27)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
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
    private var winesWithPrice: Int { wines.filter { ($0.price ?? 0) > 0 && !$0.bottlesInCellar.isEmpty }.count }

    /// Eine Zeile in den Einstellungen: Symbol, Titel, Erklärung, Pfeil.
    private func settingsRow(icon: String, title: String, text: String) -> some View {
        Card {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.wineLit)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.cream)
                    Text(text)
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

            if winesWithPrice > 0 {
                NavigationLink { PriceUpdateView() } label: {
                    settingsRow(icon: "arrow.triangle.2.circlepath",
                                title: "Preise nochmals prüfen",
                                text: "Schaut bei \(winesWithPrice) \(winesWithPrice == 1 ? "Wein" : "Weinen") nach, ob der Preis gestiegen oder gesunken ist. Du entscheidest bei jedem.")
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Sichern

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Sichern")
            Button { export() } label: {
                settingsRow(icon: "square.and.arrow.up",
                            title: "Als Excel-Tabelle speichern",
                            text: "Alle Weine mit Anzahl, Plätzen, Preisen und Notizen — für den Computer, zum Weitergeben oder als Sicherung.")
            }
            .buttonStyle(.plain)
            .disabled(wines.isEmpty)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: WeinkellerApp.usesICloud ? "checkmark.icloud.fill" : "exclamationmark.icloud")
                    .foregroundStyle(WeinkellerApp.usesICloud ? Theme.wineLit : Theme.typeSuess)
                Text(WeinkellerApp.usesICloud
                     ? "Dein Keller wird automatisch in deinem iCloud gesichert. Er bleibt bei App- und iOS-Updates erhalten und ist auf einem neuen iPhone wieder da."
                     : "iCloud ist auf diesem iPhone nicht aktiv — der Keller liegt nur hier. Er bleibt bei Updates erhalten, aber speichere ab und zu eine Excel-Tabelle als Sicherung.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 4)
        }
    }

    private func export() {
        do {
            exportFile = SharedFile(url: try CellarExport.file(wines: wines))
        } catch {
            alert = "Die Tabelle konnte nicht erstellt werden: \(error.localizedDescription)"
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
        let shelf = Shelf(name: "\(fridge.kind.levelWord) \(count + 1)", slots: 8, order: count)
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
        // Die Art des zuletzt angelegten Orts weiterführen — siehe OnboardingView.
        let kind = fridges.last?.kind ?? .fridge
        let fridge = Fridge(name: "\(kind.defaultName) \(fridges.count + 1)", order: fridges.count, kind: kind)
        context.insert(fridge)
        let shelf = Shelf(name: "\(kind.levelWord) 1", slots: 8, order: 0)
        shelf.fridge = fridge
        context.insert(shelf)
        try? context.save()
        // Wer gerade einen Ort angelegt hat, will ihn einstellen — nicht erst suchen.
        openFridge = fridge.persistentModelID
    }

    private func deleteFridge(_ fridge: Fridge) {
        guard fridge.bottleCount == 0 else {
            alert = "In \(fridge.name) stehen noch \(fridge.bottleCount) Flaschen. Lager sie zuerst um."
            return
        }
        if openFridge == fridge.persistentModelID { openFridge = nil }
        context.delete(fridge)
        try? context.save()
    }
}
