import SwiftUI
import SwiftData

/// Sucht den Marktpreis eines Weins im Internet und zeigt, **woher** er kommt.
///
/// Kein Raten: Der Server behält nur Preise, die er auf der Shop-Seite selber wiedergefunden
/// hat. Findet er keinen, steht hier ehrlich „nichts gefunden" — lieber eine Lücke als eine
/// erfundene Zahl im Kellerwert.
struct PriceLookupView: View {
    @Environment(\.dismiss) private var dismiss

    let name: String
    let producer: String
    let vintage: String
    let region: String
    let onChoose: (VinelloAPI.PriceResult, Double) -> Void

    @State private var result: VinelloAPI.PriceResult?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name).font(Theme.serif(20)).foregroundStyle(Theme.cream)
                            Text([producer, vintage, region].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                    }

                    if let result {
                        if result.found, let typical = result.typicalCHF {
                            found(result, typical: typical)
                        } else {
                            notFound
                        }
                    } else if let error {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Ging nicht").font(Theme.serif(18)).foregroundStyle(Theme.cream)
                                Text(error).font(.system(size: 14)).foregroundStyle(Theme.muted)
                            }
                        }
                        SecondaryButton(title: "Nochmals versuchen", systemImage: "arrow.clockwise") {
                            Task { await search() }
                        }
                    } else {
                        Card {
                            HStack(spacing: 12) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Suche in Weinshops …").foregroundStyle(Theme.cream)
                                    Text("Jeder Preis wird auf der Shop-Seite nachgeprüft. Meist ein paar Sekunden, bei seltenen Weinen bis zu einer Minute.")
                                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(AmbientBackground())
            .navigationTitle("Preis suchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schliessen") { dismiss() } }
            }
            .task { await search() }
        }
    }

    private func found(_ result: VinelloAPI.PriceResult, typical: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Richtpreis pro Flasche")
                    Text(chf(typical)).font(Theme.serif(38)).foregroundStyle(Theme.cream)
                    if let note = result.vintageNote, !note.isEmpty {
                        Label(note, systemImage: "exclamationmark.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.typeSuess)
                    }
                    if let low = result.lowCHF, let high = result.highCHF, high > low {
                        Text("Spanne \(chf(low)) – \(chf(high)) · \(result.sources.count) \(result.sources.count == 1 ? "Shop" : "Shops")")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    Text("Das ist, was die Flasche heute in Shops kostet — nicht unbedingt, was du bezahlt hast.")
                        .font(.system(size: 12)).foregroundStyle(Theme.mutedDim)
                }
            }

            PrimaryButton(title: "\(chf(typical)) übernehmen", systemImage: "checkmark") {
                onChoose(result, typical)
                dismiss()
            }

            SectionLabel(text: "Gefunden bei").padding(.top, 4)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(result.sources.enumerated()), id: \.offset) { index, source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(source.shop).font(.system(size: 15)).foregroundStyle(Theme.cream)
                                        Text([source.vintage, url.host].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 11)).foregroundStyle(Theme.mutedDim)
                                    }
                                    Spacer()
                                    Text(source.currency == "EUR"
                                         ? "€ \(String(format: "%.2f", source.price)) ≈ \(chf(source.priceCHF))"
                                         : chf(source.price))
                                        .font(.system(size: 14, design: .serif)).foregroundStyle(Theme.cream)
                                    Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Theme.mutedDim)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                            }
                        }
                        if index < result.sources.count - 1 {
                            Rectangle().fill(Theme.edge(0.07)).frame(height: 0.7).padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private var notFound: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kein Preis gefunden").font(Theme.serif(20)).foregroundStyle(Theme.cream)
                    Text("Für genau diesen Wein und Jahrgang hat kein Shop einen Preis, der sich überprüfen liess. Bei kleinen Winzern oder alten Jahrgängen ist das normal. Die App schreibt lieber nichts hin als eine erfundene Zahl.")
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
            }
            SecondaryButton(title: "Nochmals versuchen", systemImage: "arrow.clockwise") {
                Task { await search() }
            }
        }
    }

    private func search() async {
        result = nil
        error = nil
        do {
            result = try await VinelloAPI.findPrice(name: name, producer: producer, vintage: vintage, region: region)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func chf(_ value: Double) -> String {
        value.formatted(.currency(code: "CHF").precision(.fractionLength(value < 100 ? 2 : 0)))
    }
}

/// Preise für alle Weine ohne Preis suchen — für einen Keller, der schon voll ist und bei dem
/// niemand mehr weiss, was die Flaschen gekostet haben.
///
/// Läuft **nacheinander mit Pausen**: Die Gratis-Stufe von Groq erlaubt nur wenige Internet-
/// suchen pro Minute. Solange diese Seite offen ist, bleibt der Bildschirm an.
struct PriceBatchView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Wine.name) private var wines: [Wine]

    @State private var running = false
    @State private var current: String?
    @State private var done: [(name: String, price: Double?)] = []
    @State private var stopRequested = false
    @State private var lastError: String?
    @State private var task: Task<Void, Never>?

    /// Ausgetrunkene Weine (0 Flaschen) zählen nicht zum Kellerwert — für sie lohnt die Suche nicht.
    private var missing: [Wine] {
        wines.filter { ($0.price ?? 0) <= 0 && !$0.name.isEmpty && !$0.bottlesInCellar.isEmpty }
    }

    private var foundCount: Int { done.filter { $0.price != nil }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(running ? "Suche läuft …"
                             : !done.isEmpty ? "\(foundCount) \(foundCount == 1 ? "Preis" : "Preise") übernommen"
                             : "\(missing.count) \(missing.count == 1 ? "Wein" : "Weine") ohne Preis")
                            .font(Theme.serif(22)).foregroundStyle(Theme.cream)
                        Text("Die App sucht für jeden Wein den heutigen Shop-Preis und übernimmt ihn als **Richtpreis**. Das ist nicht dein Einkaufspreis, aber gut genug für den Kellerwert.\n\n**Runde 1** ist schnell (ein paar Sekunden pro Wein, mehrere gleichzeitig). Was dort nicht gefunden wird, sucht **Runde 2** gründlicher — das dauert pro Wein bis zu einer Minute. Lass die Seite offen.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        if let current {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(current).font(.system(size: 13)).foregroundStyle(Theme.cream).lineLimit(1)
                            }
                            .padding(.top, 4)
                        }
                        if let lastError {
                            Text(lastError).font(.system(size: 12)).foregroundStyle(Theme.typeSuess)
                        }
                    }
                }

                if running {
                    SecondaryButton(title: "Anhalten", systemImage: "stop.fill") { stop() }
                } else {
                    PrimaryButton(title: done.isEmpty ? "Preise suchen" : "Weitersuchen",
                                  systemImage: "magnifyingglass", enabled: !missing.isEmpty) {
                        start()
                    }
                }

                if !done.isEmpty {
                    SectionLabel(text: "Erledigt").padding(.top, 4)
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(done.enumerated().reversed()), id: \.offset) { _, item in
                                SpecRow(key: item.name,
                                        value: item.price.map { $0.formatted(.currency(code: "CHF")) } ?? "nicht gefunden",
                                        accent: item.price == nil ? Theme.mutedDim : nil)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(AmbientBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Preise suchen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Jederzeit raus: was schon gefunden ist, ist bereits gespeichert.
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { stop(); dismiss() }.fontWeight(.semibold)
            }
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.environment["WEINKELLER_AUTORUN"] == "1" { start() }
        }
        #endif
        .onDisappear {
            stop()
            Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = false }
        }
    }

    private func start() {
        task = Task { await run() }
    }

    /// Sofort aufhören — auch mitten in einer Minute langen Suche oder in der Pause danach.
    /// Die Preise, die schon da sind, bleiben; nur der laufende Wein wird nicht mehr fertig.
    private func stop() {
        stopRequested = true
        task?.cancel()
        task = nil
    }

    @MainActor
    private func run() async {
        running = true
        stopRequested = false
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            running = false
            current = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }

        // Runde 1: schnelle Suche, vier Weine gleichzeitig.
        let queue = missing
        var slow: [Wine] = []
        var next = 0
        while next < queue.count && !stopRequested {
            let lane = Array(queue[next..<min(next + 4, queue.count)])
            next += lane.count
            current = "Runde 1 · \(min(next, queue.count))/\(queue.count)"
            let results = await withTaskGroup(of: (Int, Result<VinelloAPI.PriceResult, Error>).self) { group in
                for (i, wine) in lane.enumerated() {
                    let (n, p, v, r) = (wine.name, wine.producer, wine.vintage, wine.region)
                    group.addTask {
                        do { return (i, .success(try await VinelloAPI.findPrice(name: n, producer: p, vintage: v, region: r, fastOnly: true))) }
                        catch { return (i, .failure(error)) }
                    }
                }
                var out: [(Int, Result<VinelloAPI.PriceResult, Error>)] = []
                for await item in group { out.append(item) }
                return out.sorted { $0.0 < $1.0 }
            }
            for (i, outcome) in results {
                let wine = lane[i]
                switch outcome {
                case .success(let result) where result.found && result.typicalCHF != nil:
                    wine.applyPrice(result, chosen: result.typicalCHF!)
                    done.append((wine.name, result.typicalCHF))
                case .success:
                    slow.append(wine)
                case .failure(let error):
                    if case VinelloAPI.Failure.offline = error {
                        lastError = error.localizedDescription
                        stopRequested = true
                    } else {
                        slow.append(wine)
                    }
                }
            }
            try? context.save()
        }

        // Runde 2: gründliche, langsame Suche für den Rest — einer nach dem anderen.
        for (index, wine) in slow.enumerated() {
            if stopRequested { break }
            current = "Runde 2 · \(index + 1)/\(slow.count): \(wine.name) \(wine.vintage)"
            do {
                let result = try await VinelloAPI.findPrice(name: wine.name, producer: wine.producer,
                                                            vintage: wine.vintage, region: wine.region)
                if Task.isCancelled || stopRequested { break }
                if result.found, let typical = result.typicalCHF {
                    wine.applyPrice(result, chosen: typical)
                    try? context.save()
                    done.append((wine.name, typical))
                } else {
                    done.append((wine.name, nil))
                }
                lastError = nil
                // Nur nach der langsamen Groq-Suche warten — sie ist pro Minute gebremst.
                if result.method == "groq" && index < slow.count - 1 && !stopRequested {
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                }
            } catch VinelloAPI.Failure.offline {
                lastError = VinelloAPI.Failure.offline.localizedDescription
                break
            } catch {
                if Task.isCancelled || stopRequested { break }   // Abbruch ist kein Fehler
                lastError = error.localizedDescription
                done.append((wine.name, nil))
            }
        }
    }
}
