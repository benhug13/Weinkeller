import SwiftUI
import SwiftData

/// Wählt Kühlschrank, Regal und Fach. Es werden nur **freie** Fächer angeboten —
/// ein belegtes Fach anzubieten wäre eine Einladung zum Fehler.
struct PlacePicker: View {
    @Query(sort: \Fridge.order) private var fridges: [Fridge]

    @Binding var shelf: Shelf?
    @Binding var slot: Int

    /// Beim Umlagern bleibt das aktuelle Fach wählbar, obwohl es belegt ist.
    var keepSlot: Int?

    private var fridge: Fridge? { shelf?.fridge ?? fridges.first }

    private var availableSlots: [Int] {
        guard let shelf else { return [] }
        var free = shelf.freeSlots
        if let keepSlot, !free.contains(keepSlot) { free.append(keepSlot) }
        return free.sorted()
    }

    var body: some View {
        Group {
            Picker("Kühlschrank", selection: fridgeBinding) {
                ForEach(fridges) { Text($0.name).tag(Optional($0.persistentModelID)) }
            }

            if let fridge {
                Picker("Regal", selection: shelfBinding) {
                    ForEach(fridge.sortedShelves) { Text($0.name).tag(Optional($0.persistentModelID)) }
                }
            }

            if availableSlots.isEmpty {
                Text("Dieses Regal ist voll. Wähl ein anderes.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            } else {
                Picker("Fach", selection: $slot) {
                    ForEach(availableSlots, id: \.self) { Text("Fach \($0 + 1)").tag($0) }
                }
            }
        }
        .onAppear(perform: pickFirstFreeIfNeeded)
    }

    private var fridgeBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { fridge?.persistentModelID },
            set: { id in
                guard let target = fridges.first(where: { $0.persistentModelID == id }) else { return }
                shelf = target.sortedShelves.first { !$0.freeSlots.isEmpty } ?? target.sortedShelves.first
                slot = shelf?.freeSlots.first ?? 0
            }
        )
    }

    private var shelfBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { shelf?.persistentModelID },
            set: { id in
                guard let target = fridge?.sortedShelves.first(where: { $0.persistentModelID == id }) else { return }
                shelf = target
                slot = target.freeSlots.first ?? 0
            }
        )
    }

    /// Beim Öffnen gleich das erste freie Fach vorschlagen, damit der Normalfall ohne Tippen geht.
    private func pickFirstFreeIfNeeded() {
        guard shelf == nil else { return }
        for fridge in fridges {
            if let free = fridge.sortedShelves.first(where: { !$0.freeSlots.isEmpty }) {
                shelf = free
                slot = free.freeSlots.first ?? 0
                return
            }
        }
    }
}
