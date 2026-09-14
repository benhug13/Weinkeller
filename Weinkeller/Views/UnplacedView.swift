import SwiftUI
import SwiftData

/// Flaschen, die im Keller stehen, aber noch keinem Fach zugeordnet sind —
/// typisch nach dem Übernehmen einer Excel-Liste ohne Platzangaben.
struct UnplacedView: View {
    @Environment(\.modelContext) private var context
    @Query private var bottles: [Bottle]
    @Query(sort: \Fridge.order) private var fridges: [Fridge]

    @State private var placing: Bottle?
    @State private var shelf: Shelf?
    @State private var slot = 0
    @State private var mode: PlacingMode?

    private var unplaced: [Bottle] {
        bottles
            .filter { !$0.isDrunk && !$0.hasPlace }
            .sorted { ($0.wine?.name ?? "") < ($1.wine?.name ?? "") }
    }

    private var freeSlotCount: Int {
        fridges.flatMap(\.sortedShelves).reduce(0) { $0 + $1.freeSlots.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if unplaced.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Alles eingeräumt")
                                .font(Theme.serif(18))
                                .foregroundStyle(Theme.cream)
                            Text("Jede Flasche im Keller hat ein Fach.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(unplaced.count) \(unplaced.count == 1 ? "Flasche" : "Flaschen") ohne Platz")
                                .font(Theme.serif(21))
                                .foregroundStyle(Theme.cream)
                            Text("In der Liste stand nicht, wo sie liegen. Such dir aus, wie du vorgehen willst — beides geht direkt vor dem offenen Kühlschrank. \(freeSlotCount) Fächer sind frei.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    modeCard(.walk,
                             icon: "eye",
                             title: "Nachschauen, was wo liegt",
                             text: "Die Flaschen liegen schon drin. Die App geht Fach für Fach durch, du tippst, welche Flasche dort liegt.")
                    modeCard(.guided,
                             icon: "arrow.down.to.line",
                             title: "Neu einräumen",
                             text: "Die Flaschen sind draussen. Die App nimmt eine nach der anderen und sagt dir, in welches Fach sie gehört.")

                    SectionLabel(text: "Oder einzeln")
                        .padding(.top, 8)

                    ForEach(unplaced) { bottle in
                        Button {
                            start(placing: bottle)
                        } label: {
                            Card(padding: 12) {
                                HStack(spacing: 12) {
                                    if let wine = bottle.wine {
                                        LabelThumb(wine: wine, width: 40, height: 54)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(wine.name)
                                                .font(Theme.serif(16))
                                                .foregroundStyle(Theme.cream)
                                                .lineLimit(1)
                                            Text([wine.producer, wine.vintage]
                                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                                .font(.system(size: 12))
                                                .foregroundStyle(Theme.muted)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    Text("Einräumen")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.wineLit)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
        }
        .background(AmbientBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Noch einräumen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $placing) { bottle in placeSheet(for: bottle) }
        .navigationDestination(item: $mode) { mode in
            switch mode {
            case .walk:   SlotWalkView()
            case .guided: GuidedPlacingView()
            }
        }
    }

    private func modeCard(_ target: PlacingMode, icon: String, title: String, text: String) -> some View {
        Button { mode = target } label: {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Theme.wineLit)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.cream)
                        Text(text)
                            .font(.system(size: 13))
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
        .buttonStyle(.plain)
    }

    private func placeSheet(for bottle: Bottle) -> some View {
        NavigationStack {
            Form {
                Section {
                    PlacePicker(shelf: $shelf, slot: $slot)
                } header: {
                    Text(bottle.wine?.name ?? "Flasche")
                }
            }
            .navigationTitle("Einräumen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { placing = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        guard let shelf else { return }
                        bottle.shelf = shelf
                        bottle.slot = slot
                        try? context.save()
                        placing = nil
                    }
                    .disabled(shelf == nil)
                }
            }
        }
    }

    private func start(placing bottle: Bottle) {
        shelf = nil          // PlacePicker schlägt dann selber das erste freie Fach vor
        slot = 0
        self.placing = bottle
    }
}
