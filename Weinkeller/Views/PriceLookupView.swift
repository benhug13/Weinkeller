import SwiftUI
import SwiftData

/// Sucht den Marktpreis eines Weins im Internet und zeigt, **woher** er kommt.
///
/// Kein Raten: Der Server behält nur Preise, die er auf der Shop-Seite selber wiedergefunden
/// hat. Findet er keinen, steht hier ehrlich „nichts gefunden" — lieber eine Lücke als eine
/// erfundene Zahl im Kellerwert.
@MainActor
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
                                    Text("Jeder Preis wird auf der Shop-Seite nachgeprüft. Das dauert ein paar Sekunden.")
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
                                        Text(url.host ?? "").font(.system(size: 11)).foregroundStyle(Theme.mutedDim)
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
@MainActor
struct PriceBatchView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Wine.name) private var wines: [Wine]

    @State private var running = false
    @State private var current: String?
    @State private var done: [(name: String, price: Double?)] = []
    @State private var stopRequested = false
    @State private var lastError: String?

    private var missing: [Wine] { wines.filter { ($0.price ?? 0) <= 0 && !$0.name.isEmpty } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(running ? "Suche läuft …" : "\(missing.count) \(missing.count == 1 ? "Wein" : "Weine") ohne Preis")
                            .font(Theme.serif(22)).foregroundStyle(Theme.cream)
                        Text("Die App sucht für jeden Wein den heutigen Shop-Preis und übernimmt ihn als **Richtpreis**. Das ist nicht dein Einkaufspreis, aber gut genug für den Kellerwert. Etwa **30 Sekunden pro Wein** — lass die Seite offen.")
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
                    SecondaryButton(title: "Anhalten", systemImage: "stop.fill") { stopRequested = true }
                } else {
                    PrimaryButton(title: "Preise suchen", systemImage: "magnifyingglass", enabled: !missing.isEmpty) {
                        Task { await run() }
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
        .onDisappear {
            stopRequested = true
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func run() async {
        running = true
        stopRequested = false
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            running = false
            current = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }

        // Nur einmal pro Wein versuchen: was nicht gefunden wird, fliegt aus der Warteschlange.
        let queue = missing
        for (index, wine) in queue.enumerated() {
            if stopRequested { break }
            current = "\(index + 1)/\(queue.count): \(wine.name) \(wine.vintage)"
            do {
                let result = try await VinelloAPI.findPrice(name: wine.name, producer: wine.producer,
                                                            vintage: wine.vintage, region: wine.region)
                if result.found, let typical = result.typicalCHF {
                    wine.applyPrice(result, chosen: typical)
                    try? context.save()
                    done.append((wine.name, typical))
                } else {
                    done.append((wine.name, nil))
                }
                lastError = nil
            } catch VinelloAPI.Failure.offline {
                lastError = VinelloAPI.Failure.offline.localizedDescription
                break
            } catch {
                lastError = error.localizedDescription
                done.append((wine.name, nil))
            }
            // Pause, damit die Gratis-Stufe nicht dauernd ausgelastet ist.
            if index < queue.count - 1 && !stopRequested {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
            }
        }
    }
}
