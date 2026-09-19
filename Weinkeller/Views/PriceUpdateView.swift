import SwiftUI
import SwiftData

/// Alle Preise nochmals nachschauen — und zeigen, was sich verändert hat.
///
/// Anders als die erste Preissuche schreibt diese Seite **nichts von selber** in den Keller.
/// Am Schluss steht eine Liste „vorher → heute", und der Besitzer entscheidet bei jedem Wein:
/// übernehmen oder verwerfen. Sonst könnte ein einzelner falscher Shop-Treffer einen
/// sorgfältig eingetragenen Einkaufspreis überschreiben.
///
/// Gesucht wird nur schnell (Tavily, 2 Suchen pro Wein). Die langsame Groq-Suche lohnt hier
/// nicht: Wird ein Wein nicht gefunden, bleibt einfach der alte Preis.
struct PriceUpdateView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Wine.name) private var wines: [Wine]

    struct Change: Identifiable {
        let id = UUID()
        let wine: Wine
        let old: Double
        let new: Double
        let result: VinelloAPI.PriceResult

        var percent: Double { (new - old) / old * 100 }
    }

    @State private var task: Task<Void, Never>?
    @State private var running = false
    @State private var checked = 0
    @State private var total = 0
    @State private var changes: [Change] = []
    @State private var unchanged = 0
    @State private var notFound = 0
    @State private var accepted = 0
    @State private var dropped = 0
    @State private var started = false
    @State private var usage: VinelloAPI.Usage?
    @State private var lastError: String?

    /// Nur Weine mit Preis und mit Flaschen im Keller — ausgetrunkene zählen nicht zum Wert.
    private var candidates: [Wine] {
        wines.filter { ($0.price ?? 0) > 0 && !$0.name.isEmpty && !$0.bottlesInCellar.isEmpty }
    }

    /// Unter 5 % Unterschied ist Rauschen zwischen Shops, keine echte Preisänderung.
    private static let threshold = 5.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                introCard
                if !started || running { quotaCard }

                if running {
                    SecondaryButton(title: "Anhalten", systemImage: "stop.fill") { stop() }
                } else if !started {
                    PrimaryButton(title: "Preise prüfen", systemImage: "arrow.triangle.2.circlepath",
                                  enabled: !candidates.isEmpty && usage?.left != 0) { start() }
                }

                if started { resultSection }
            }
            .padding(18)
        }
        .background(AmbientBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Preise prüfen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { stop(); dismiss() }.fontWeight(.semibold)
            }
        }
        .task {
            usage = try? await VinelloAPI.usage()
            #if DEBUG
            if ProcessInfo.processInfo.environment["WEINKELLER_AUTORUN"] == "1", !started { start() }
            #endif
        }
        .onDisappear {
            stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Oben

    private var introCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(running ? "Prüfe \(checked) von \(total) …"
                     : started ? (lastError == nil ? "Fertig geprüft" : "Angehalten")
                     : "\(candidates.count) \(candidates.count == 1 ? "Wein" : "Weine") mit Preis")
                    .font(Theme.serif(22)).foregroundStyle(Theme.cream)
                if running {
                    ProgressView(value: Double(checked), total: Double(max(total, 1)))
                        .tint(Theme.wineLit)
                }
                if !started {
                    Text("Die App schaut für jeden Wein den heutigen Shop-Preis nach. Danach siehst du, **welcher Preis gestiegen oder gesunken ist** — und entscheidest bei jedem Wein, ob du den neuen Preis übernimmst. Von selber wird nichts überschrieben.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                if let lastError {
                    Text(lastError).font(.system(size: 12)).foregroundStyle(Theme.typeSuess)
                }
            }
        }
    }

    /// Wie viel vom Gratis-Kontingent schon weg ist — bevor man 200 Weine auf einmal prüft.
    @ViewBuilder
    private var quotaCard: some View {
        if let usage {
            let needed = candidates.count * usage.perWine
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Gratis-Suchen diesen Monat")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.cream)
                        Spacer()
                        Text("\(Int((usage.share * 100).rounded())) % verbraucht")
                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.muted)
                    }
                    ProgressView(value: usage.share)
                        .tint(usage.share > 0.85 ? Theme.typeSuess : Theme.wineLit)
                    Text(usage.left == 0
                         ? "Alle \(usage.limit) Gratis-Suchen sind diesen Monat gebraucht. Nächsten Monat geht es wieder."
                         : "\(usage.used) von \(usage.limit) gebraucht, noch \(usage.left) frei. Diese Prüfung braucht etwa **\(needed)** (rund \(usage.perWine) pro Wein).")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    if needed > usage.left && usage.left > 0 {
                        Text("Reicht für etwa \(usage.left / max(usage.perWine, 1)) Weine. Die übrigen findet die Suche erst nächsten Monat — sie bleiben dann einfach beim alten Preis.")
                            .font(.system(size: 12)).foregroundStyle(Theme.typeSuess)
                    }
                }
            }
        }
    }

    // MARK: - Ergebnis

    @ViewBuilder
    private var resultSection: some View {
        let sorted = changes.sorted { abs($0.percent) > abs($1.percent) }

        if !sorted.isEmpty {
            HStack {
                SectionLabel(text: "Verändert")
                Spacer()
                if !running {
                    Button("Alle übernehmen") { acceptAll() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.wineLit)
                }
            }
            .padding(.top, 4)
            VStack(spacing: 8) {
                ForEach(sorted) { change in changeRow(change) }
            }
        }

        Card(padding: 0) {
            VStack(spacing: 0) {
                SpecRow(key: "Geprüft", value: "\(checked)")
                SpecRow(key: "Gleich geblieben (±5 %)", value: "\(unchanged)")
                SpecRow(key: "Nicht gefunden", value: "\(notFound)", accent: notFound > 0 ? Theme.mutedDim : nil)
                if accepted > 0 { SpecRow(key: "Übernommen", value: "\(accepted)") }
                SpecRow(key: "Verworfen", value: "\(dropped)", isLast: true)
            }
        }

        if !running && changes.isEmpty {
            PrimaryButton(title: "Fertig", systemImage: "checkmark") { dismiss() }
        }
    }

    private func changeRow(_ change: Change) -> some View {
        let up = change.new > change.old
        return Card {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(change.wine.name)
                        .font(Theme.serif(17)).foregroundStyle(Theme.cream).lineLimit(2)
                    if !change.wine.vintage.isEmpty || !change.wine.producer.isEmpty {
                        Text([change.wine.producer, change.wine.vintage].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(chf(change.old)).foregroundStyle(Theme.muted).strikethrough()
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.mutedDim)
                        Text(chf(change.new)).foregroundStyle(Theme.cream).fontWeight(.semibold)
                    }
                    .font(.system(size: 14).monospacedDigit())
                    Label(percentText(change.percent), systemImage: up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(up ? Theme.wineLit : Theme.chill)
                    if let note = change.result.vintageNote, !note.isEmpty {
                        Text(note).font(.system(size: 11)).foregroundStyle(Theme.mutedDim)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    roundButton("checkmark", filled: true, label: "\(change.wine.name) übernehmen") { accept(change) }
                    roundButton("xmark", filled: false, label: "\(change.wine.name) verwerfen") { drop(change) }
                }
            }
        }
    }

    private func roundButton(_ symbol: String, filled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(filled ? Color.white : Theme.cream)
                .frame(width: 36, height: 36)
                .background {
                    if filled { Circle().fill(Theme.wine) } else { Circle().fill(.white.opacity(0.08)) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Ablauf

    private func start() {
        started = true
        task = Task { await run() }
    }

    private func stop() {
        task?.cancel()
        task = nil
    }

    @MainActor
    private func run() async {
        let queue = candidates
        total = queue.count
        running = true
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            running = false
            UIApplication.shared.isIdleTimerDisabled = false
            Task { usage = try? await VinelloAPI.usage() }
        }

        var next = 0
        while next < queue.count, !Task.isCancelled {
            let lane = Array(queue[next..<min(next + 4, queue.count)])
            next += lane.count
            let results = await withTaskGroup(of: (Int, VinelloAPI.PriceResult?, Error?).self) { group in
                for (i, wine) in lane.enumerated() {
                    let (n, p, v, r) = (wine.name, wine.producer, wine.vintage, wine.region)
                    // ⚠️ Erst in eine eigene Konstante warten, dann das Tupel bauen. Steht `try await`
                    // mitten im Tupel, kam mit Swift 6.4 bei Erfolg immer Nummer 0 zurück — und der
                    // Preis landete beim falschen Wein (gemessen 19.09.2026).
                    group.addTask {
                        do {
                            let found = try await VinelloAPI.findPrice(name: n, producer: p, vintage: v, region: r, fastOnly: true)
                            return (i, found, nil)
                        }
                        catch { return (i, nil, error) }
                    }
                }
                var out: [(Int, VinelloAPI.PriceResult?, Error?)] = []
                for await item in group { out.append(item) }
                return out.sorted { $0.0 < $1.0 }
            }
            if Task.isCancelled { break }

            for (i, result, error) in results {
                let wine = lane[i]
                checked += 1
                if let error {
                    // Offline oder Kontingent leer: aufhören und klar sagen, warum — nicht jeden
                    // weiteren Wein still als „nicht gefunden" zählen.
                    if let failure = error as? VinelloAPI.Failure, failure.isQuota || failure == .offline {
                        lastError = error.localizedDescription
                        return
                    }
                    notFound += 1
                    continue
                }
                guard let result, result.found, let new = result.typicalCHF, new > 0,
                      let old = wine.price, old > 0 else {
                    notFound += 1
                    continue
                }
                let rounded = (new * 100).rounded() / 100
                if abs(rounded - old) / old * 100 < Self.threshold {
                    unchanged += 1
                } else {
                    changes.append(Change(wine: wine, old: old, new: rounded, result: result))
                }
            }
        }
    }

    private func accept(_ change: Change) {
        change.wine.applyPrice(change.result, chosen: change.new)
        try? context.save()
        withAnimation(.snappy(duration: 0.25)) {
            changes.removeAll { $0.id == change.id }
            accepted += 1
        }
    }

    private func drop(_ change: Change) {
        withAnimation(.snappy(duration: 0.25)) {
            changes.removeAll { $0.id == change.id }
            dropped += 1
        }
    }

    private func acceptAll() {
        for change in changes { change.wine.applyPrice(change.result, chosen: change.new) }
        try? context.save()
        withAnimation(.snappy(duration: 0.25)) {
            accepted += changes.count
            changes.removeAll()
        }
    }

    // MARK: - Hilfen

    private func chf(_ value: Double) -> String {
        "CHF " + value.formatted(.number.precision(.fractionLength(value == value.rounded() ? 0 : 2))
                                    .grouping(.automatic).locale(Locale(identifier: "de_CH")))
    }

    private func percentText(_ percent: Double) -> String {
        let value = Int(percent.rounded())
        let formatted = abs(value).formatted(.number.grouping(.automatic).locale(Locale(identifier: "de_CH")))
        return (value >= 0 ? "+" : "−") + formatted + " %"
    }
}
