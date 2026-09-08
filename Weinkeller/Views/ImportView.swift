import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Eine bestehende Weinliste aus Excel übernehmen.
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
            .navigationTitle("Aus Excel übernehmen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Abbrechen" : "Fertig") { dismiss() }
                }
            }
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                          allowsMultipleSelection: false) { outcome in
                load(outcome)
            }
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
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("So geht's")
                        .font(Theme.serif(20))
                        .foregroundStyle(Theme.cream)
                    step(1, "In Excel: **Datei → Speichern unter → CSV UTF-8**.")
                    step(2, "Die Datei aufs iPhone bringen — per AirDrop, Mail oder iCloud Drive.")
                    step(3, "Hier unten auswählen. Danach sagst du, welche Spalte was ist.")
                }
            }

            Card {
                Text("Die App liest **nur**, was in der Datei steht. Nichts geht ins Internet, und dein bestehender Keller bleibt unverändert — der Import kommt dazu.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }

            PrimaryButton(title: "Datei auswählen", systemImage: "doc.badge.plus") {
                picking = true
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
                    Text("\(table.rows.count) Zeilen · \(table.header.count) Spalten")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Welche Spalte ist was?")
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
                    Text("**\(preview.bottles - preview.placed) Flaschen** haben noch keinen Platz. Sie landen unter „Noch einräumen“ — dort kannst du sie in Ruhe verteilen.")
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
            SecondaryButton(title: "Andere Datei wählen") { picking = true }
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
            PrimaryButton(title: "Fertig") { dismiss() }
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
                let data = try Data(contentsOf: url)
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)   // altes Excel schreibt Latin-1
                guard let text else {
                    error = "Die Datei liess sich nicht lesen. Beim Speichern in Excel bitte „CSV UTF-8“ wählen."
                    return
                }
                let parsed = CSV.parse(text)
                guard !parsed.header.isEmpty, !parsed.rows.isEmpty else {
                    error = "In der Datei stehen keine Zeilen. Hat sie eine Kopfzeile mit den Spaltennamen?"
                    return
                }
                fileName = url.lastPathComponent
                mapping = WineImport.guessMapping(header: parsed.header)
                table = parsed
                result = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
