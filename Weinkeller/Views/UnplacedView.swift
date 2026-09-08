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
    @State private var askAutoFill = false

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
                            Text("\(unplaced.count) Flaschen ohne Platz")
                                .font(Theme.serif(19))
                                .foregroundStyle(Theme.cream)
                            Text("\(freeSlotCount) Fächer sind frei. Tipp eine Flasche an, um sie einzuräumen — oder füll der Reihe nach auf und stell sie danach genauso hin.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    SecondaryButton(title: "Der Reihe nach auffüllen", systemImage: "arrow.down.to.line") {
                        askAutoFill = true
                    }

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
        .confirmationDialog("Der Reihe nach auffüllen?",
                            isPresented: $askAutoFill, titleVisibility: .visible) {
            Button("\(min(unplaced.count, freeSlotCount)) Flaschen verteilen") { autoFill() }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Die Flaschen werden von vorne in die freien Fächer gelegt. Nur sinnvoll, wenn du sie danach auch so in den Kühlschrank stellst.")
        }
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

    /// Legt die Flaschen von vorne in die freien Fächer — Kühlschrank für Kühlschrank.
    private func autoFill() {
        var queue = unplaced
        outer: for fridge in fridges {
            for shelf in fridge.sortedShelves {
                for free in shelf.freeSlots {
                    guard let bottle = queue.first else { break outer }
                    queue.removeFirst()
                    bottle.shelf = shelf
                    bottle.slot = free
                }
            }
        }
        try? context.save()
    }
}
