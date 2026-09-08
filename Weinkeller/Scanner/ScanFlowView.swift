import SwiftUI
import SwiftData

/// Der Ablauf beim Scannen, in genau der Reihenfolge, die nichts kostet:
/// 1. Steht die Flasche schon im eigenen Keller? → sofort anzeigen
/// 2. Kennt der mitgelieferte Katalog sie? → Formular ist schon ausgefüllt
/// 3. Nichts gefunden? → „Wein nicht gefunden" und von Hand eintragen
struct ScanFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var wines: [Wine]

    @State private var status: Status = .searching
    @State private var scannedBarcode: String?
    @State private var formPrefill: CatalogWine?
    @State private var addToWine: Wine?

    enum Status {
        case searching
        case knownWine(Wine)            // steht schon im Keller
        case fromCatalog(CatalogWine)   // im Katalog gefunden
        case notFound(CatalogWine)      // nichts gefunden, Vorschlag aus dem Gelesenen
    }

    var body: some View {
        NavigationStack {
            Group {
                if ScannerView.isSupported {
                    ZStack(alignment: .bottom) {
                        ScannerView(onBarcode: handle(barcode:), onText: handle(text:))
                            .ignoresSafeArea()
                        resultCard
                            .padding(.horizontal, 18)
                            .padding(.bottom, 28)
                    }
                } else {
                    unsupported
                }
            }
            .navigationTitle("Scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(item: $formPrefill) { prefill in
                WineFormView(prefill: prefill)
            }
            .sheet(item: $addToWine) { wine in
                AddBottleView(wine: wine)
            }
        }
    }

    private var unsupported: some View {
        ContentUnavailableView {
            Label("Kamera nicht verfügbar", systemImage: "camera.fill")
        } description: {
            Text("Dieses Gerät kann nicht scannen — im Simulator gibt es keine Kamera. Auf dem iPhone geht es.")
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        switch status {
        case .searching:
            card(title: "Barcode oder Etikett vor die Kamera halten", subtitle: nil)

        case .knownWine(let wine):
            card(title: wine.name, subtitle: "Steht schon im Keller — \(wine.bottlesInCellar.count) Flaschen") {
                Button("Weitere Flasche einlagern") { addToWine = wine }
                    .buttonStyle(.borderedProminent)
                Button("Weiter scannen") { reset() }
                    .buttonStyle(.bordered)
            }

        case .fromCatalog(let found):
            card(title: found.name, subtitle: "Im Katalog gefunden") {
                Button("Einlagern") { formPrefill = found }
                    .buttonStyle(.borderedProminent)
                Button("Weiter scannen") { reset() }
                    .buttonStyle(.bordered)
            }

        case .notFound(let suggestion):
            card(title: "Wein nicht gefunden", subtitle: "Trag ihn ein — dann kennt ihn die App ab jetzt.") {
                Button("Jetzt eintragen") { formPrefill = suggestion }
                    .buttonStyle(.borderedProminent)
                Button("Weiter scannen") { reset() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func card(title: String,
                      subtitle: String?,
                      @ViewBuilder actions: () -> some View = { EmptyView() }) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(Theme.serif(18))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            actions()
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(Theme.cream)
    }

    private func reset() {
        status = .searching
        scannedBarcode = nil
    }

    private func handle(barcode: String) {
        guard case .searching = status else { return }
        scannedBarcode = barcode

        if let mine = wines.first(where: { $0.barcode == barcode }) {
            status = .knownWine(mine)
        } else if let found = WineCatalog.shared.lookup(barcode: barcode) {
            status = .fromCatalog(found)
        } else {
            status = .notFound(CatalogWine(barcode: barcode, name: ""))
        }
    }

    private func handle(text: String) {
        guard case .searching = status else { return }

        // Zuerst der eigene Keller: das sind ein paar hundert Weine, kein Vergleich zur Welt.
        // Genau darum reicht hier eine Texterkennung, die einzelne Buchstaben verliest.
        let ownMatch = wines
            .map { ($0, TextMatching.score(query: text,
                                           candidate: "\($0.name) \($0.producer) \($0.region)")) }
            .max { $0.1 < $1.1 }

        if let ownMatch, ownMatch.1 >= 0.5 {
            status = .knownWine(ownMatch.0)
        } else if let found = WineCatalog.shared.bestMatch(for: text) {
            status = .fromCatalog(found)
        } else {
            status = .notFound(CatalogWine(
                barcode: scannedBarcode,
                name: String(text.prefix(60)).trimmingCharacters(in: .whitespaces),
                vintage: TextMatching.vintage(in: text) ?? ""
            ))
        }
    }
}
