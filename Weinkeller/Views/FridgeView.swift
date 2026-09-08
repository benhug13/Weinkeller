import SwiftUI
import SwiftData

/// Ein Kühlschrank von innen — aber nur das, was wirklich drin steht.
/// Leere Fächer bekommen eine Zeile, keine vierzig gestrichelten Kästchen.
struct FridgeView: View {
    let fridge: Fridge

    @State private var openBottle: Bottle?
    @State private var newBottlePlace: Place?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(fridge.sortedShelves) { shelf in
                    shelfCard(shelf)
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .background(AmbientBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle(fridge.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openBottle) { BottleDetailView(bottle: $0) }
        .sheet(item: $newBottlePlace) { WineFormView(place: $0) }
    }

    private func shelfCard(_ shelf: Shelf) -> some View {
        let bottles = shelf.bottlesInCellar.sorted { $0.slot < $1.slot }
        let free = shelf.freeSlots

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: shelf.name)
                Spacer()
                Text("\(bottles.count) / \(shelf.slots)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.mutedDim)
            }

            FillBar(ratio: shelf.slots > 0 ? Double(bottles.count) / Double(shelf.slots) : 0, height: 2)

            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(bottles) { bottle in
                        Button { openBottle = bottle } label: { row(for: bottle) }
                            .buttonStyle(.plain)
                        if bottle.id != bottles.last?.id || !free.isEmpty {
                            Rectangle().fill(.white.opacity(0.07)).frame(height: 0.7)
                        }
                    }

                    if let first = free.first {
                        Button {
                            newBottlePlace = Place(shelf: shelf, slot: first)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.wineLit)
                                    .frame(width: 26)
                                Text(free.count == 1 ? "1 Fach frei" : "\(free.count) Fächer frei")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.muted)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(for bottle: Bottle) -> some View {
        HStack(spacing: 10) {
            Text("\(bottle.slot + 1)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.mutedDim)
                .frame(width: 26, alignment: .leading)

            if let wine = bottle.wine {
                TypeDot(type: wine.type)
                VStack(alignment: .leading, spacing: 2) {
                    Text(wine.name)
                        .font(Theme.serif(16))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    if !wine.producer.isEmpty {
                        Text(wine.producer)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.mutedDim)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(wine.vintage)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// Ein Platz im Keller: Regal plus Fachnummer.
struct Place: Identifiable, Hashable {
    let shelf: Shelf
    var slot: Int

    var id: String { "\(shelf.persistentModelID.hashValue)-\(slot)" }
}
