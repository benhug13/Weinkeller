import SwiftUI
import SwiftData

/// Eine einzelne Flasche im Keller.
struct BottleDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let bottle: Bottle

    @State private var isMoving = false
    @State private var isEditing = false
    @State private var moveShelf: Shelf?
    @State private var moveSlot = 0

    var body: some View {
        NavigationStack {
            List {
                if let wine = bottle.wine {
                    Section { WineHeader(wine: wine) }

                    Section {
                        row("Platz", bottle.placeLabel)
                        if !wine.vintage.isEmpty { row("Jahrgang", wine.vintage) }
                        if !wine.region.isEmpty  { row("Region", wine.region) }
                        if !wine.grape.isEmpty   { row("Traube", wine.grape) }
                        if let price = wine.price {
                            row("Preis", String(format: "CHF %.2f", price))
                        }
                        row("Eingelagert", bottle.addedAt.formatted(date: .numeric, time: .omitted))
                        row("Im Keller", "\(wine.bottlesInCellar.count) Flaschen")
                    }

                    if !wine.note.isEmpty {
                        Section("Notiz") { Text(wine.note) }
                    }

                    Section {
                        Button("Als getrunken markieren", action: markAsDrunk)
                        Button("Umlagern") { prepareMove() }
                        Button("Wein bearbeiten") { isEditing = true }
                    }

                    Section {
                        Button("Flasche löschen", role: .destructive, action: deleteBottle)
                    } footer: {
                        Text("Der Wein bleibt in der Liste, nur diese Flasche verschwindet.")
                    }
                }
            }
            .navigationTitle("Flasche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $isEditing) {
                if let wine = bottle.wine { WineFormView(editing: wine) }
            }
            .sheet(isPresented: $isMoving) { moveSheet }
        }
    }

    private var moveSheet: some View {
        NavigationStack {
            Form {
                Section("Neuer Platz") {
                    PlacePicker(shelf: $moveShelf, slot: $moveSlot, keepSlot: bottle.slot)
                }
            }
            .navigationTitle("Umlagern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { isMoving = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen", action: move)
                }
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func prepareMove() {
        moveShelf = bottle.shelf
        moveSlot = bottle.slot
        isMoving = true
    }

    private func move() {
        guard let moveShelf else { return }
        bottle.shelf = moveShelf
        bottle.slot = moveSlot
        try? context.save()
        isMoving = false
        dismiss()
    }

    private func markAsDrunk() {
        bottle.drunkAt = Date()
        try? context.save()
        dismiss()
    }

    private func deleteBottle() {
        context.delete(bottle)
        try? context.save()
        dismiss()
    }
}

/// Kopfzeile mit Etikettfoto und Namen — überall gleich, damit ein Wein überall gleich aussieht.
struct WineHeader: View {
    let wine: Wine

    var body: some View {
        HStack(spacing: 14) {
            if let data = wine.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 72, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(wine.name).font(Theme.serif(22))
                Text([wine.producer, wine.type.label].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
    }
}
