import SwiftUI
import SwiftData

/// „Welchen Wein heute?" — zwei Fragen, dann ein Vorschlag.
///
/// **Kein Assistent mit Weiter-Knöpfen.** Die Antworten stehen offen auf einer Seite
/// und der Vorschlag darunter ändert sich sofort mit. Wer sich vertippt hat oder
/// ausprobieren will, wie es mit „heute darf's was kosten" aussähe, tippt einmal
/// statt sich durch vier Seiten zurückzuarbeiten.
struct TonightView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var bottles: [Bottle]

    @AppStorage("tonightCompany") private var companyRaw = Occasion.Company.twoOfUs.rawValue
    @AppStorage("tonightEffort") private var effortRaw = Occasion.Effort.everyday.rawValue

    @State private var openBottle: Bottle?

    private var company: Occasion.Company {
        Occasion.Company(rawValue: companyRaw) ?? .twoOfUs
    }
    private var effort: Occasion.Effort {
        Occasion.Effort(rawValue: effortRaw) ?? .everyday
    }

    private var inCellar: [Bottle] { bottles.filter { !$0.isDrunk } }

    private var picks: [Occasion.Pick] {
        Occasion.suggest(from: inCellar, company: company, effort: effort)
    }

    /// Wird der Wunsch wegen fremder Gäste gedämpft, soll das dastehen — sonst
    /// wirkt die App, als hätte sie die Antwort ignoriert.
    private var toned: Bool {
        Occasion.effective(effort, with: company) != effort
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Welchen Wein heute?")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.cream)

                    question("Mit wem trinkst du?") {
                        chips(Occasion.Company.allCases, selected: company) { companyRaw = $0.rawValue }
                    }

                    question("Was soll es sein?") {
                        chips(Occasion.Effort.allCases, selected: effort) { effortRaw = $0.rawValue }
                    }

                    if toned {
                        Text("Bei Gästen, die du kaum kennst, schlag ich dir bewusst nicht die teuerste Flasche vor.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.mutedDim)
                    }

                    if picks.isEmpty {
                        Card {
                            Text(inCellar.isEmpty
                                 ? "Noch keine Flasche im Keller."
                                 : "Zu dieser Auswahl finde ich nichts. Trag bei deinen Weinen Preise ein, dann wird der Vorschlag besser.")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.muted)
                        }
                    } else {
                        SectionLabel(text: "Mein Vorschlag")
                        suggestionCard(picks[0], big: true)

                        if picks.count > 1 {
                            SectionLabel(text: "Oder")
                                .padding(.top, 4)
                            ForEach(picks.dropFirst(), id: \.bottle.persistentModelID) { pick in
                                suggestionCard(pick, big: false)
                            }
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AmbientBackground())
            .scrollContentBackground(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    Button("Fertig") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.wineLit)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .sheet(item: $openBottle) { BottleDetailView(bottle: $0) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Bausteine

    private func question<Content: View>(_ title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: title)
            content()
        }
    }

    private func chips<T: Identifiable & Equatable>(_ options: [T],
                                                    selected: T,
                                                    label: @escaping (T) -> String = { _ in "" },
                                                    action: @escaping (T) -> Void) -> some View {
        FlowChips(options: options, selected: selected, action: action)
    }

    @ViewBuilder
    private func suggestionCard(_ pick: Occasion.Pick, big: Bool) -> some View {
        if let wine = pick.bottle.wine {
            Button { openBottle = pick.bottle } label: {
                Card {
                    HStack(spacing: 14) {
                        LabelThumb(wine: wine, width: big ? 62 : 44, height: big ? 82 : 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(wine.name)
                                .font(Theme.serif(big ? 20 : 16))
                                .foregroundStyle(Theme.cream)
                                .multilineTextAlignment(.leading)
                            Text([wine.producer, wine.vintage].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                            Text(pick.reason)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.wineLit)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 8) {
                                Text(pick.bottle.placeLabel)
                                if let price = wine.price, price > 0 {
                                    Text(price.formatted(.currency(code: "CHF").precision(.fractionLength(0))))
                                }
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.mutedDim)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// Auswahlkapseln, die umbrechen statt seitlich zu scrollen — vier Möglichkeiten
/// passen auf einem iPhone nicht in eine Zeile, und was man wegscrollen muss,
/// übersieht man.
private struct FlowChips<T: Identifiable & Equatable>: View {
    let options: [T]
    let selected: T
    let action: (T) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 7) {
                    ForEach(rows[index]) { option in
                        chip(option)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Zwei pro Zeile: alle Beschriftungen hier sind kurz genug, und eine feste
    /// Aufteilung bleibt ruhiger als ein Layout, das je nach Text springt.
    private var rows: [[T]] {
        stride(from: 0, to: options.count, by: 2).map {
            Array(options[$0..<min($0 + 2, options.count)])
        }
    }

    private func chip(_ option: T) -> some View {
        let active = option == selected
        return Button { action(option) } label: {
            HStack(spacing: 6) {
                if let symbol = (option as? Occasion.Company)?.symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                }
                Text(text(for: option)).font(.system(size: 13))
            }
            .foregroundStyle(active ? Theme.cream : Theme.muted)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background { Capsule().fill(active ? Theme.wine : .clear) }
            .overlay { Capsule().strokeBorder(active ? .clear : .white.opacity(0.12), lineWidth: 0.8) }
        }
        .buttonStyle(.plain)
    }

    private func text(for option: T) -> String {
        if let c = option as? Occasion.Company { return c.label }
        if let e = option as? Occasion.Effort { return e.label }
        return ""
    }
}
