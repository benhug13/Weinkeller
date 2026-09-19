import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

/// Eine bestehende Weinliste übernehmen — egal, wie sie aufgeschrieben ist.
///
/// Jeder führt seine Liste anders: Excel, Word, ein PDF vom Weinhändler, eine Notiz im
/// iPhone oder ein Blatt Papier. Alle Wege enden in derselben Tabelle, darum sieht der
/// Besitzer danach immer dieselbe Zuordnung und dieselbe Vorschau.
struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Fridge.order) private var fridges: [Fridge]

    @State private var picking = false
    @State private var table: CSV.Table?
    @State private var mapping: [WineImport.Field: Int] = [:]
    @State private var fileName = ""
    @State private var error: String?
    @State private var result: WineImport.Result?
    @State private var source: ListReader.Source?
    @State private var pasting = false
    @State private var pastedText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var takingPhoto = false
    @State private var pickingFromLibrary = false
    @State private var reading = false
    @State private var readingLabel = false

    /// Die Vorschläge, so wie der Besitzer sie ändert. **Erst „Übernehmen" schreibt in den Keller.**
    @State private var drafts: [WineImport.Draft] = []
    @State private var editing: WineImport.Draft?
    @State private var showMapping = false

    /// Ein Foto kann zwei ganz verschiedene Dinge sein: eine **Liste** (viele Weine, eine Zeile
    /// pro Wein, auf dem Gerät gelesen) oder **eine Flasche** (ein Etikett, dessen Text nicht
    /// zeilenweise auseinandergerissen werden darf). Darum vorher fragen, nicht nachher raten.
    private enum PhotoKind { case list, bottle }
    @State private var photoKind: PhotoKind = .list

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let result {
                        doneCard(result)
                    } else if !drafts.isEmpty {
                        reviewSection
                    } else {
                        startCard
                    }
                }
                .padding(18)
            }
            .background(AmbientBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Liste übernehmen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Abbrechen" : "Fertig") { dismiss() }
                }
            }
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: ListReader.importableTypes,
                          allowsMultipleSelection: false) { outcome in
                load(outcome)
            }
            .sheet(isPresented: $pasting) { pasteSheet }
            .sheet(item: $editing) { draft in
                DraftEditor(draft: draft) { changed in
                    if let index = drafts.firstIndex(where: { $0.id == changed.id }) {
                        drafts[index] = changed
                    }
                }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { image in read(image: image) }
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $pickingFromLibrary, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) {
                guard let item = photoItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        read(image: image)
                    }
                    photoItem = nil
                }
            }
            .overlay {
                if reading || readingLabel {
                    ProgressView(readingLabel ? "Etikett wird gelesen …" : "Liste wird gelesen …")
                        .padding(24)
                        .glassPanel(radius: 18)
                }
            }
            #if DEBUG
            // Etikett einer einzelnen Flasche ohne Kamera: SIMCTL_CHILD_WEINKELLER_BOTTLE_FILE=/pfad/etikett.jpg
            .onAppear {
                guard drafts.isEmpty,
                      let path = ProcessInfo.processInfo.environment["WEINKELLER_BOTTLE_FILE"],
                      let image = UIImage(contentsOfFile: path) else { return }
                photoKind = .bottle
                read(image: image)
            }
            // Für Screenshots ohne Dateiauswahl: SIMCTL_CHILD_WEINKELLER_IMPORT_FILE=/pfad/liste.xlsx
            .onAppear {
                guard drafts.isEmpty,
                      let path = ProcessInfo.processInfo.environment["WEINKELLER_IMPORT_FILE"],
                      !path.isEmpty else { return }
                load(.success([URL(fileURLWithPath: path)]))
                // WEINKELLER_IMPORT_EDIT=1 öffnet gleich die erste Zeile — für Screenshots ohne Antippen.
                if ProcessInfo.processInfo.environment["WEINKELLER_IMPORT_EDIT"] == "1" {
                    editing = drafts.first
                }
            }
            #endif
            .alert("Ging nicht", isPresented: Binding(get: { error != nil },
                                                     set: { if !$0 { error = nil } })) {
                Button("Verstanden") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: - Start

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wo steht deine Liste?")
                        .font(Theme.serif(22))
                        .foregroundStyle(Theme.cream)
                    Text("Danach siehst du jeden Wein einzeln und kannst ändern oder wegwerfen — **erst dann** kommt etwas in den Keller. Listen liest die App auf dem Gerät; nur das Etikett einer einzelnen Flasche geht ins Internet.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
            }

            sourceButton(icon: "doc.fill",
                         title: "Datei",
                         text: "Excel, Word, PDF oder CSV — aus Dateien, iCloud Drive oder einer Mail.") {
                picking = true
            }
            sourceButton(icon: "doc.on.clipboard",
                         title: "Text einfügen",
                         text: "Aus Notizen, WhatsApp oder einer Mail kopiert. Eine Zeile pro Wein.") {
                pastedText = UIPasteboard.general.hasStrings ? (UIPasteboard.general.string ?? "") : ""
                pasting = true
            }
            if CameraPicker.isAvailable {
                sourceButton(icon: "camera.fill",
                             title: "Liste fotografieren",
                             text: "Ein Blatt Papier oder ein Ausdruck. Die Schrift wird auf dem iPhone gelesen.") {
                    photoKind = .list
                    takingPhoto = true
                }
            }
            sourceButton(icon: "photo.on.rectangle",
                         title: "Foto aus der Mediathek",
                         text: "Ein Bild oder Screenshot der Liste, das schon auf dem iPhone ist.") {
                photoKind = .list
                pickingFromLibrary = true
            }
            sourceButton(icon: "wineglass.fill",
                         title: "Eine einzelne Flasche",
                         text: "Kein Blatt, nur eine Flasche? Das Etikett wird gelesen — Winzer, Name, Jahrgang getrennt. Braucht Internet.") {
                photoKind = .bottle
                if CameraPicker.isAvailable { takingPhoto = true } else { pickingFromLibrary = true }
            }

            Text("Tipp: Steht in der Liste nicht, in welchem Fach eine Flasche liegt, ist das kein Problem. Danach hilft dir die App beim Einräumen — Fach für Fach.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedDim)
                .padding(.top, 4)
        }
    }

    private func sourceButton(icon: String, title: String, text: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) { sourceRow(icon: icon, title: title, text: text) }
            .buttonStyle(.plain)
    }

    private func sourceRow(icon: String, title: String, text: String) -> some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.wineLit)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.cream)
                    Text(text)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.mutedDim)
            }
        }
    }

    private var pasteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Eine Zeile pro Wein, zum Beispiel:\n„Barolo Cannubi 2016, 3 Flaschen, CHF 95“")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                TextEditor(text: $pastedText)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.cream)
                    .padding(10)
                    .glassPanel(radius: 16, shadow: false)
            }
            .padding(18)
            .background(AmbientBackground())
            .navigationTitle("Text einfügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { pasting = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Weiter") {
                        pasting = false
                        accept(ListReader.table(fromText: pastedText), name: "Eingefügter Text", source: .text)
                    }
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.cream)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.wine))
            Text(.init(text))
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Durchschauen und ändern

    /// Jede erkannte Zeile als eigene Karte: antippen zum Ändern, **X zum Wegwerfen**.
    /// Nichts davon ist im Keller, solange „Übernehmen" nicht gedrückt ist.
    private var reviewSection: some View {
        let summary = WineImport.summary(drafts: drafts, fridges: fridges)

        return VStack(alignment: .leading, spacing: 18) {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileName)
                        .font(Theme.serif(17))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    Text([source.map { "aus \($0.label)" },
                          "\(summary.wines) Weine", "\(summary.bottles) Flaschen"]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                    Text("Stimmt etwas nicht, tipp die Zeile an. Was nicht dazugehört, wirfst du mit **✕** weg.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedDim)
                        .padding(.top, 2)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Gefundene Weine")
                VStack(spacing: 8) {
                    ForEach(drafts) { draft in
                        draftRow(draft)
                    }
                }
                SecondaryButton(title: "Wein von Hand dazu", systemImage: "plus") {
                    let new = WineImport.Draft()
                    drafts.append(new)
                    editing = new
                }
            }

            if summary.bottles > summary.placed {
                Card {
                    Text("**\(summary.bottles - summary.placed) Flaschen** haben noch keinen Platz. Das ist normal — danach hilft dir die App: entweder Fach für Fach nachschauen, was wo liegt, oder neu einräumen, und sie sagt dir, wohin.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
            }

            PrimaryButton(title: summary.bottles == 1 ? "1 Flasche übernehmen" : "\(summary.bottles) Flaschen übernehmen",
                          systemImage: "square.and.arrow.down",
                          enabled: summary.wines > 0) {
                result = WineImport.run(drafts: drafts, fridges: fridges, context: context)
            }

            if let table {
                mappingCard(table)
            }

            SecondaryButton(title: "Von vorne — andere Liste") { reset() }
        }
    }

    private func draftRow(_ draft: WineImport.Draft) -> some View {
        Card {
            HStack(spacing: 12) {
                Circle().fill(draft.type.color).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.hasName ? draft.name : "Ohne Namen — wird nicht übernommen")
                        .font(Theme.serif(17))
                        .foregroundStyle(draft.hasName ? Theme.cream : Theme.mutedDim)
                        .lineLimit(2)
                    if !draft.producer.isEmpty {
                        Text(draft.producer)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Text(draft.summaryLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedDim)
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.mutedDim)
                // Eigener Knopf statt Wischen: Ben soll das Wegwerfen sehen, nicht erraten.
                Button {
                    drafts.removeAll { $0.id == draft.id }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.cream)
                        .frame(width: 30, height: 30)
                        .glassPanel(radius: 15, highlight: 0.22, shadow: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(draft.name) wegwerfen")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = draft }
    }

    /// Nur nötig, wenn die Liste aus einer Tabelle kommt und eine Spalte falsch geraten wurde.
    /// Darum zugeklappt — und mit Warnung, weil neues Zuordnen die Änderungen überschreibt.
    private func mappingCard(_ table: CSV.Table) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showMapping.toggle()
            } label: {
                Card {
                    HStack {
                        Text("Spalten zuordnen")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.cream)
                        Spacer()
                        Image(systemName: showMapping ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.mutedDim)
                    }
                }
            }
            .buttonStyle(.plain)

            if showMapping {
                Text("Achtung: Änderst du hier etwas, wird die Liste oben neu gelesen — deine Korrekturen gehen dabei verloren.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedDim)
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(WineImport.Field.allCases.enumerated()), id: \.element) { index, field in
                            HStack {
                                Text(field.label + (field.isRequired ? " *" : ""))
                                    .font(.system(size: 14))
                                    .foregroundStyle(field.isRequired ? Theme.cream : Theme.muted)
                                Spacer()
                                Picker("", selection: binding(for: field)) {
                                    Text("—").tag(-1)
                                    ForEach(Array(table.header.enumerated()), id: \.offset) { i, title in
                                        Text(title.isEmpty ? "Spalte \(i + 1)" : title).tag(i)
                                    }
                                }
                                .labelsHidden()
                                .tint(Theme.cream)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            if index < WineImport.Field.allCases.count - 1 {
                                Rectangle().fill(.white.opacity(0.06)).frame(height: 0.7)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
            }
        }
    }

    private func line(_ key: String, _ value: String, warn: Bool = false) -> some View {
        HStack {
            Text(key).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(warn ? Theme.typeSuess : Theme.cream)
        }
    }

    private func binding(for field: WineImport.Field) -> Binding<Int> {
        Binding(
            get: { mapping[field] ?? -1 },
            set: {
                mapping[field] = $0 < 0 ? nil : $0
                // Andere Spalte → die Vorschläge stimmen nicht mehr, also neu lesen.
                if let table { drafts = WineImport.drafts(table: table, mapping: mapping) }
            }
        )
    }

    // MARK: - Fertig

    private func doneCard(_ result: WineImport.Result) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Übernommen")
                        .font(Theme.serif(22))
                        .foregroundStyle(Theme.cream)
                    line("Weine", "\(result.wines)")
                    line("Flaschen", "\(result.bottles)")
                    if result.unplaced > 0 {
                        line("noch einzuräumen", "\(result.unplaced)", warn: true)
                    }
                }
            }
            if result.unplaced > 0 {
                NavigationLink {
                    UnplacedView()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.to.line").font(.system(size: 15, weight: .semibold))
                        Text("Jetzt einräumen").font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.wineLit, Theme.wine],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                }
                SecondaryButton(title: "Später") { dismiss() }
            } else {
                PrimaryButton(title: "Fertig") { dismiss() }
            }
        }
    }

    // MARK: - Datei laden

    private func load(_ outcome: Result<[URL], Error>) {
        switch outcome {
        case .failure(let err):
            error = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            // Dateien aus der Dateien-App liegen ausserhalb der App — erst Zugriff holen.
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

            do {
                let loaded = try ListReader.table(from: url)
                accept(loaded.table, name: url.lastPathComponent, source: loaded.source)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func read(image: UIImage) {
        switch photoKind {
        case .list:   readList(image: image)
        case .bottle: readBottle(image: image)
        }
    }

    private func readList(image: UIImage) {
        reading = true
        Task {
            do {
                let table = try await ListReader.table(fromImage: image)
                accept(table, name: "Foto der Liste", source: .photo)
            } catch {
                self.error = error.localizedDescription
            }
            reading = false
        }
    }

    /// Eine einzelne Flasche: Das Etikett wird als **ein** Wein gelesen, nicht Zeile für Zeile.
    private func readBottle(image: UIImage) {
        readingLabel = true
        Task {
            do {
                guard let data = VinelloAPI.shrink(image, maxSide: 1024) else {
                    throw VinelloAPI.Failure.server("Das Foto liess sich nicht lesen.")
                }
                let label = try await VinelloAPI.readLabel(data)
                guard label.isWineLabel else {
                    error = "Auf dem Foto ist kein Weinetikett zu erkennen. Nochmals näher versuchen?"
                    readingLabel = false
                    return
                }
                var draft = WineImport.draft(fromLabel: label)
                if !draft.hasName { draft.name = label.producer }
                table = nil
                source = nil
                fileName = "Foto einer Flasche"
                result = nil
                drafts.append(draft)
                // Direkt offen: bei einer einzelnen Flasche will man Anzahl und Preis eintragen.
                editing = draft
            } catch {
                self.error = error.localizedDescription
            }
            readingLabel = false
        }
    }

    private func accept(_ parsed: CSV.Table, name: String, source: ListReader.Source) {
        guard !parsed.header.isEmpty, !parsed.rows.isEmpty else {
            error = "In der Liste wurden keine Weine gefunden. Steht pro Zeile ein Wein?"
            return
        }
        fileName = name
        self.source = source
        mapping = WineImport.guessMapping(table: parsed)
        let found = WineImport.drafts(table: parsed, mapping: mapping)
        guard !found.isEmpty else {
            error = "In der Liste wurden keine Namen gefunden. Ist es vielleicht das Etikett einer einzelnen Flasche? Dann „Eine einzelne Flasche“ nehmen."
            return
        }
        table = parsed
        drafts = found
        result = nil
        showMapping = false
    }

    private func reset() {
        table = nil
        source = nil
        drafts = []
        mapping = [:]
        fileName = ""
        showMapping = false
    }
}

/// Eine einzelne Zeile der Liste ändern, bevor sie in den Keller geht.
///
/// Bewusst dasselbe schlichte `Form` wie im Wein-Formular: Wer eine falsch gelesene Zeile
/// korrigiert, will tippen, nicht Glaskarten anschauen.
private struct DraftEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: WineImport.Draft
    @State private var priceText: String
    private let save: (WineImport.Draft) -> Void

    init(draft: WineImport.Draft, save: @escaping (WineImport.Draft) -> Void) {
        _draft = State(initialValue: draft)
        _priceText = State(initialValue: draft.price.map { String(format: $0 == $0.rounded() ? "%.0f" : "%.2f", $0) } ?? "")
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    TextField("Winzer", text: $draft.producer)
                    Picker("Art", selection: $draft.type) {
                        ForEach(WineType.allCases) { type in
                            Label {
                                Text(type.label)
                            } icon: {
                                Circle().fill(type.color).frame(width: 9, height: 9)
                            }
                            .tag(type)
                        }
                    }
                } footer: {
                    Text("Ohne Namen wird die Zeile nicht übernommen.")
                }

                Section {
                    TextField("Jahrgang", text: $draft.vintage).keyboardType(.numberPad)
                    Stepper("Flaschen: \(draft.count)", value: $draft.count, in: 0...200)
                    TextField("Preis CHF", text: $priceText).keyboardType(.decimalPad)
                    TextField("Region", text: $draft.region)
                    TextField("Traube", text: $draft.grape)
                }

                Section {
                    TextField("Notiz", text: $draft.note, axis: .vertical).lineLimit(2...5)
                }

                if !draft.shelfText.isEmpty || !draft.slotText.isEmpty {
                    Section {
                        Text([draft.fridgeText, draft.shelfText, draft.slotText]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(Theme.muted)
                    } header: {
                        Text("Platz aus der Liste")
                    } footer: {
                        Text("Findet die App diesen Platz im Keller, liegt die Flasche nachher dort.")
                    }
                }
            }
            .navigationTitle(draft.hasName ? draft.name : "Neuer Wein")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        draft.price = WineImport.price(from: priceText)
                        save(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}
