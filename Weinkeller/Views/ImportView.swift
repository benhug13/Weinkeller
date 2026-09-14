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
    @State private var reading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let result {
                        doneCard(result)
                    } else if let table {
                        mappingSection(table)
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
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { image in read(image: image) }
                    .ignoresSafeArea()
            }
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
                if reading {
                    ProgressView("Liste wird gelesen …")
                        .padding(24)
                        .glassPanel(radius: 18)
                }
            }
            #if DEBUG
            // Für Screenshots ohne Dateiauswahl: SIMCTL_CHILD_WEINKELLER_IMPORT_FILE=/pfad/liste.xlsx
            .onAppear {
                guard table == nil,
                      let path = ProcessInfo.processInfo.environment["WEINKELLER_IMPORT_FILE"],
                      !path.isEmpty else { return }
                load(.success([URL(fileURLWithPath: path)]))
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
                    Text("Die App liest **nur**, was in der Liste steht. Nichts geht ins Internet, und dein bestehender Keller bleibt unverändert — die Liste kommt dazu.")
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
                    takingPhoto = true
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                sourceRow(icon: "photo.on.rectangle",
                          title: "Foto aus der Mediathek",
                          text: "Ein Bild oder Screenshot der Liste, das schon auf dem iPhone ist.")
            }
            .buttonStyle(.plain)

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

    // MARK: - Spalten zuordnen

    private func mappingSection(_ table: CSV.Table) -> some View {
        let preview = WineImport.preview(table: table, mapping: mapping, fridges: fridges)

        return VStack(alignment: .leading, spacing: 18) {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileName)
                        .font(Theme.serif(17))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    Text([source.map { "aus \($0.label)" }, "\(table.rows.count) Zeilen", "\(table.header.count) Spalten"]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Vorschau")
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        line("Weine, die übernommen werden", "\(preview.importable)")
                        line("Flaschen insgesamt", "\(preview.bottles)")
                        line("davon mit Platz aus der Tabelle", "\(preview.placed)")
                        if preview.skipped > 0 {
                            line("Zeilen ohne Namen (übersprungen)", "\(preview.skipped)", warn: true)
                        }
                        if !preview.samples.isEmpty {
                            Text("z. B. " + preview.samples.joined(separator: ", "))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.mutedDim)
                                .padding(.top, 2)
                        }
                    }
                }
            }

            if preview.bottles > preview.placed {
                Card {
                    Text("**\(preview.bottles - preview.placed) Flaschen** haben noch keinen Platz. Das ist normal — danach hilft dir die App: entweder Fach für Fach nachschauen, was wo liegt, oder neu einräumen, und sie sagt dir, wohin.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
            }

            PrimaryButton(title: "\(preview.bottles) Flaschen übernehmen",
                          systemImage: "square.and.arrow.down",
                          enabled: preview.importable > 0) {
                result = WineImport.run(table: table, mapping: mapping,
                                        fridges: fridges, context: context)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Spalten zuordnen")
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

            SecondaryButton(title: "Andere Liste wählen") { self.table = nil; source = nil }
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
            set: { mapping[field] = $0 < 0 ? nil : $0 }
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

    private func accept(_ parsed: CSV.Table, name: String, source: ListReader.Source) {
        guard !parsed.header.isEmpty, !parsed.rows.isEmpty else {
            error = "In der Liste wurden keine Weine gefunden. Steht pro Zeile ein Wein?"
            return
        }
        fileName = name
        self.source = source
        mapping = WineImport.guessMapping(header: parsed.header)
        table = parsed
        result = nil
    }
}
