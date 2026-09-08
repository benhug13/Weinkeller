import SwiftUI
import SwiftData
import PhotosUI

/// Flasche erfassen oder Wein bearbeiten.
struct WineFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let editing: Wine?
    @State private var draft: Draft
    @State private var shelf: Shelf?
    @State private var slot: Int
    @State private var photoItem: PhotosPickerItem?

    /// Neue Flasche an einem bekannten Platz.
    init(place: Place, prefill: CatalogWine? = nil) {
        self.editing = nil
        _draft = State(initialValue: Draft(prefill))
        _shelf = State(initialValue: place.shelf)
        _slot  = State(initialValue: place.slot)
    }

    /// Neue Flasche, Platz wird noch gewählt.
    init(prefill: CatalogWine? = nil) {
        self.editing = nil
        _draft = State(initialValue: Draft(prefill))
        _shelf = State(initialValue: nil)
        _slot  = State(initialValue: 0)
    }

    /// Bestehenden Wein bearbeiten. Gilt für alle Flaschen dieses Weins.
    init(editing wine: Wine) {
        self.editing = wine
        _draft = State(initialValue: Draft(wine))
        _shelf = State(initialValue: nil)
        _slot  = State(initialValue: 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Etikett") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack(spacing: 14) {
                            if let data = draft.photo, let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable().scaledToFill()
                                    .frame(width: 52, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Text(draft.photo == nil ? "Foto wählen" : "Foto ersetzen")
                        }
                    }
                }

                Section {
                    TextField("Name", text: $draft.name)
                    TextField("Winzer", text: $draft.producer)
                    Picker("Art", selection: $draft.type) {
                        ForEach(WineType.allCases) { type in
                            Label {
                                Text(type.label)
                            } icon: {
                                Circle().fill(type.color).frame(width: 9, height: 9)
                            }
                            .tag(type)
                        }
                    }
                }

                Section {
                    TextField("Jahrgang", text: $draft.vintage).keyboardType(.numberPad)
                    TextField("Preis CHF", text: $draft.price).keyboardType(.decimalPad)
                    TextField("Region", text: $draft.region)
                    TextField("Traube", text: $draft.grape)
                }

                Section("Notiz") {
                    TextField("Notiz", text: $draft.note, axis: .vertical).lineLimit(3...6)
                }

                if editing == nil {
                    Section("Platz im Keller") {
                        PlacePicker(shelf: $shelf, slot: $slot)
                    }
                }
            }
            .navigationTitle(editing == nil ? "Flasche erfassen" : "Wein bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Einlagern" : "Speichern", action: save)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: photoItem) { _, item in
                Task { draft.photo = await Self.loadShrunkImage(from: item) }
            }
        }
    }

    private func save() {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        if let wine = editing {
            draft.apply(to: wine)
            try? context.save()
            dismiss()
            return
        }

        let wine = Wine(name: name)
        draft.apply(to: wine)
        context.insert(wine)

        if let shelf {
            let bottle = Bottle(wine: wine, shelf: shelf, slot: slot)
            context.insert(bottle)
        }
        try? context.save()
        dismiss()
    }

    /// Fotos vom iPhone sind riesig. Auf 900 px verkleinern, sonst wächst die Datenbank ins Uferlose.
    private static func loadShrunkImage(from item: PhotosPickerItem?) async -> Data? {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return nil }

        let maxSide: CGFloat = 900
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        guard scale < 1 else { return image.jpegData(compressionQuality: 0.75) }

        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.75)
    }
}

/// Zwischenspeicher fürs Formular, damit ein Abbruch nichts an der Datenbank ändert.
private struct Draft {
    var name = ""
    var producer = ""
    var vintage = ""
    var type: WineType = .rot
    var region = ""
    var grape = ""
    var price = ""
    var note = ""
    var barcode: String?
    var photo: Data?

    init(_ catalog: CatalogWine?) {
        guard let catalog else { return }
        name = catalog.name
        producer = catalog.producer
        vintage = catalog.vintage
        type = catalog.wineType
        region = catalog.region
        grape = catalog.grape
        barcode = catalog.barcode
    }

    init(_ wine: Wine) {
        name = wine.name
        producer = wine.producer
        vintage = wine.vintage
        type = wine.type
        region = wine.region
        grape = wine.grape
        price = wine.price.map { String(format: "%.2f", $0) } ?? ""
        note = wine.note
        barcode = wine.barcode
        photo = wine.photo
    }

    func apply(to wine: Wine) {
        wine.name = name.trimmingCharacters(in: .whitespaces)
        wine.producer = producer
        wine.vintage = vintage
        wine.type = type
        wine.region = region
        wine.grape = grape
        wine.price = Double(price.replacingOccurrences(of: ",", with: "."))
        wine.note = note
        wine.barcode = barcode
        wine.photo = photo
    }
}
