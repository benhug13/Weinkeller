import SwiftUI
import SwiftData

/// Ein Wein: Etikett, Trinkfenster, Preis und Angaben — und unten der Knopf, um den zu tun,
/// wofür man Wein kauft.
struct WineDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let wine: Wine

    @State private var isEditing = false
    @State private var isAdding = false
    @State private var askWhichBottle = false
    @State private var justDrunk: String?

    private var bottles: [Bottle] {
        wine.bottlesInCellar.sorted { $0.slot < $1.slot }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                drinkWindowCard
                specsCard
                placesCard
                actions
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .background(AmbientBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle(wine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .sheet(isPresented: $isEditing) { WineFormView(editing: wine) }
        .sheet(isPresented: $isAdding) { AddBottleView(wine: wine) }
        .confirmationDialog("Welche Flasche?", isPresented: $askWhichBottle, titleVisibility: .visible) {
            ForEach(bottles) { bottle in
                Button(bottle.placeLabel) { drink(bottle) }
            }
            Button("Abbrechen", role: .cancel) { }
        }
        .alert("Zum Wohl!", isPresented: Binding(get: { justDrunk != nil },
                                                 set: { if !$0 { justDrunk = nil } })) {
            Button("Danke") { justDrunk = nil }
        } message: {
            Text(justDrunk ?? "")
        }
    }

    // MARK: - Kopf

    private var header: some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                LabelThumb(wine: wine, width: 88, height: 118)
                VStack(alignment: .leading, spacing: 6) {
                    Text(wine.name)
                        .font(Theme.serif(24))
                        .foregroundStyle(Theme.cream)
                    if !wine.producer.isEmpty {
                        Text(wine.producer)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: 7) {
                        TypeDot(type: wine.type)
                        Text(wine.type.label)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                        if !wine.vintage.isEmpty {
                            Text("· \(wine.vintage)")
                                .font(.system(size: 13).monospacedDigit())
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    if wine.rating > 0 {
                        RatingStars(rating: .constant(wine.rating), size: 15, interactive: false)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Trinkfenster

    @ViewBuilder
    private var drinkWindowCard: some View {
        if let window = wine.drinkWindow {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Trinkfenster")
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(String(window.lowerBound)) – \(String(window.upperBound))")
                                .font(Theme.serif(26))
                                .foregroundStyle(Theme.cream)
                            Spacer()
                            Text(wine.drinkStatus.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(statusColor)
                        }
                        WindowBar(window: window)
                        Text("Richtwert aus Traube, Region und Art — nicht in Stein gemeisselt.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.mutedDim)
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        switch wine.drinkStatus {
        case .ready, .lastCall: return Theme.wineLit
        case .past:             return Theme.typeSuess
        case .tooYoung:         return Theme.typeSchaum
        case .unknown:          return Theme.mutedDim
        }
    }

    // MARK: - Angaben

    private var specsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Angaben")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    let rows = specRows
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        SpecRow(key: row.0, value: row.1, isLast: index == rows.count - 1)
                    }
                }
            }
        }
    }

    private var specRows: [(String, String)] {
        var rows: [(String, String)] = []
        if !wine.vintage.isEmpty { rows.append(("Jahrgang", wine.vintage)) }
        if !wine.region.isEmpty  { rows.append(("Region", wine.region)) }
        if !wine.grape.isEmpty   { rows.append(("Traube", wine.grape)) }
        if let price = wine.price, price > 0 {
            rows.append(("Preis pro Flasche", price.formatted(.currency(code: "CHF"))))
            if bottles.count > 1 {
                rows.append(("Wert im Keller",
                             (price * Double(bottles.count)).formatted(.currency(code: "CHF"))))
            }
        }
        if let code = wine.barcode, !code.isEmpty { rows.append(("Barcode", code)) }
        if !wine.note.isEmpty { rows.append(("Notiz", wine.note)) }
        if rows.isEmpty { rows.append(("Noch nichts erfasst", "—")) }
        return rows
    }

    // MARK: - Plätze

    private var placesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: bottles.isEmpty
                         ? "Keine Flasche mehr im Keller"
                         : (bottles.count == 1 ? "1 Flasche im Keller" : "\(bottles.count) Flaschen im Keller"))
            if !bottles.isEmpty {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(bottles.enumerated()), id: \.element.id) { index, bottle in
                            NavigationLink {
                                BottleDetailView(bottle: bottle)
                            } label: {
                                HStack {
                                    Text(bottle.placeLabel)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.cream)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.mutedDim)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < bottles.count - 1 {
                                Rectangle().fill(.white.opacity(0.07)).frame(height: 0.7)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Knöpfe

    /// Unten steht **nur** der Knopf, für den man Wein kauft. Alles andere liegt
    /// hinter den drei Punkten oben rechts — man braucht es selten.
    private var actions: some View {
        PrimaryButton(title: "Trinken", systemImage: "wineglass.fill",
                      enabled: !bottles.isEmpty) {
            if bottles.count == 1 {
                drink(bottles[0])
            } else {
                askWhichBottle = true
            }
        }
        .padding(.top, 4)
    }

    private var moreMenu: some View {
        Menu {
            Button {
                isAdding = true
            } label: {
                Label("Weitere Flasche einlagern", systemImage: "plus")
            }
            Button {
                isEditing = true
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                deleteWine()
            } label: {
                Label("Wein löschen", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .frame(width: 32, height: 32)
                .glassPanel(radius: 16, highlight: 0.30, shadow: false)
        }
        .accessibilityLabel("Mehr")
    }

    /// Flasche als getrunken buchen: sie verschwindet aus dem Keller, das Fach wird frei,
    /// der Wein selbst bleibt in der Liste.
    private func drink(_ bottle: Bottle) {
        let place = bottle.placeLabel
        bottle.drunkAt = Date()
        try? context.save()
        justDrunk = "\(wine.name) ist ausgebucht.\n\(place) ist wieder frei."
    }

    private func deleteWine() {
        context.delete(wine)
        try? context.save()
        dismiss()
    }
}

/// Zeigt, wo im Trinkfenster man gerade steht.
struct WindowBar: View {
    let window: ClosedRange<Int>
    private var now: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        GeometryReader { geo in
            let span = Double(window.upperBound - window.lowerBound)
            let progress = span > 0 ? Double(now - window.lowerBound) / span : 0
            let clamped = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.typeSchaum, Theme.wineLit, Theme.typeSuess],
                                         startPoint: .leading, endPoint: .trailing))
                    .opacity(0.55)
                // Wo stehen wir heute?
                Circle()
                    .fill(Theme.cream)
                    .frame(width: 9, height: 9)
                    .offset(x: geo.size.width * clamped - 4.5)
                    .opacity(progress >= 0 && progress <= 1 ? 1 : 0)
            }
        }
        .frame(height: 6)
    }
}

/// Weitere Flasche eines bereits erfassten Weins einlagern — der häufigste Fall im Alltag.
struct AddBottleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let wine: Wine
    @State private var shelf: Shelf?
    @State private var slot = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Platz im Keller") {
                    PlacePicker(shelf: $shelf, slot: $slot)
                }
            }
            .navigationTitle(wine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Einlagern") {
                        guard let shelf else { return }
                        context.insert(Bottle(wine: wine, shelf: shelf, slot: slot))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(shelf == nil)
                }
            }
        }
    }
}
