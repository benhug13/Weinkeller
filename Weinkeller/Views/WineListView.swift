import SwiftUI
import SwiftData

/// Alle erfassten Weine: suchen, nach Art filtern, sortieren.
struct WineListView: View {
    @Query(sort: \Wine.name) private var wines: [Wine]

    @State private var search = ""
    @State private var filter: WineType?
    @State private var sort: SortOrder = .name
    @State private var scanning = false

    enum SortOrder: String, CaseIterable, Identifiable {
        case name, vintage, price, readiness, rating
        var id: String { rawValue }
        var label: String {
            switch self {
            case .name:      return "Name"
            case .vintage:   return "Jahrgang"
            case .price:     return "Preis"
            case .readiness: return "Trinkreife"
            case .rating:    return "Bewertung"
            }
        }
    }

    private var shown: [Wine] {
        var list = wines

        if let filter { list = list.filter { $0.type == filter } }

        let query = TextMatching.normalize(search)
        if !query.isEmpty { list = list.filter { $0.searchText.contains(query) } }

        switch sort {
        case .name:
            list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .vintage:
            // Ohne Jahrgang nach hinten, sonst stehen sie vor den ältesten Flaschen.
            list.sort { ($0.vintage.isEmpty ? "9999" : $0.vintage) < ($1.vintage.isEmpty ? "9999" : $1.vintage) }
        case .price:
            list.sort { ($0.price ?? 0) > ($1.price ?? 0) }
        case .readiness:
            list.sort { rank(for: $0) < rank(for: $1) }
        case .rating:
            // Unbewertete nach hinten, sonst stehen sie vor den Fünf-Sterne-Weinen.
            list.sort { ($0.rating == 0 ? -1 : $0.rating) > ($1.rating == 0 ? -1 : $1.rating) }
        }
        return list
    }

    /// Was jetzt getrunken werden sollte, steht oben.
    private func rank(for wine: Wine) -> Int {
        switch wine.drinkStatus {
        case .lastCall: return 0
        case .past:     return 1
        case .ready:    return 2
        case .tooYoung: return 3
        case .unknown:  return 4
        }
    }

    private var bottleCount: Int {
        wines.reduce(0) { $0 + $1.bottlesInCellar.count }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    titleRow
                    searchField
                    filterChips
                    summary

                    if shown.isEmpty {
                        emptyState
                    } else {
                        ForEach(shown) { wine in
                            NavigationLink {
                                WineDetailView(wine: wine)
                            } label: {
                                WineCard(wine: wine)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
            .background(AmbientBackground())
            .scrollContentBackground(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $scanning) { ScanFlowView() }
        }
    }

    // MARK: - Kopf

    private var titleRow: some View {
        HStack {
            Text("Weine")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.cream)
            Spacer()
            Menu {
                Picker("Sortieren", selection: $sort) {
                    ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                    .frame(width: 34, height: 34)
                    .glassPanel(radius: 17, highlight: 0.34, shadow: false)
            }
            .accessibilityLabel("Sortieren")

            GlassIconButton(systemName: "viewfinder") { scanning = true }
                .accessibilityLabel("Flasche scannen")
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.mutedDim)
            TextField("Wein, Winzer, Jahrgang suchen", text: $search)
                .font(.system(size: 15))
                .foregroundStyle(Theme.cream)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.mutedDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassPanel(radius: 16, highlight: 0.22, shadow: false)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip(label: "Alle", color: nil, active: filter == nil) { filter = nil }
                ForEach(WineType.allCases) { type in
                    chip(label: type.label, color: type.color, active: filter == type) {
                        filter = (filter == type) ? nil : type
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.bottom, 2)
    }

    private func chip(label: String, color: Color?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Text(label).font(.system(size: 13))
            }
            .foregroundStyle(active ? Theme.cream : Theme.muted)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                Capsule().fill(active ? Theme.wine : .clear)
            }
            .overlay {
                Capsule().strokeBorder(active ? .clear : .white.opacity(0.12), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        Text("\(shown.count) \(shown.count == 1 ? "Wein" : "Weine") · \(bottleCount) Flaschen im Keller")
            .font(.system(size: 12))
            .foregroundStyle(Theme.mutedDim)
            .padding(.bottom, 2)
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(wines.isEmpty ? "Noch kein Wein erfasst" : "Nichts gefunden")
                    .font(Theme.serif(18))
                    .foregroundStyle(Theme.cream)
                Text(wines.isEmpty
                     ? "Scann eine Flasche oder tipp im Kühlschrank auf ein freies Fach."
                     : "Andere Schreibweise probieren oder den Filter zurücksetzen.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Ein Wein in der Liste: Etikett, Name, Herkunft — und wo er im Trinkfenster steht.
struct WineCard: View {
    let wine: Wine

    private var subtitle: String {
        [wine.producer, wine.vintage, wine.region]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var statusColor: Color {
        switch wine.drinkStatus {
        case .ready, .lastCall: return Theme.wineLit
        case .past:             return Theme.typeSuess
        case .tooYoung:         return Theme.typeSchaum
        case .unknown:          return Theme.mutedDim
        }
    }

    var body: some View {
        Card(padding: 12) {
            HStack(spacing: 13) {
                LabelThumb(wine: wine, width: 46, height: 62)

                VStack(alignment: .leading, spacing: 3) {
                    Text(wine.name)
                        .font(Theme.serif(17))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    // Kein Farbpunkt hier: der Anfangsbuchstabe links trägt die Farbe
                    // der Weinart schon. Zwei Farbzeichen nebeneinander verwirren nur.
                    HStack(spacing: 8) {
                        Text(wine.drinkStatus.label)
                            .font(.system(size: 11))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                        if wine.rating > 0 {
                            RatingStars(rating: .constant(wine.rating), size: 9, interactive: false)
                        }
                    }
                    .padding(.top, 1)
                }

                Spacer(minLength: 4)

                Text("\(wine.bottlesInCellar.count)")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(wine.bottlesInCellar.isEmpty ? Theme.mutedDim : Theme.cream)
                    .frame(minWidth: 28)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.08)))
            }
        }
    }
}
