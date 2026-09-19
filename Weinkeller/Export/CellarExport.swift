import Foundation
import SwiftUI
import UIKit

/// Der ganze Keller als Excel-Datei — für den Computer, zum Weitergeben oder als Sicherung.
///
/// Zwei Blätter:
/// - **Weine**: eine Zeile pro Wein, mit Anzahl, Preis, Wert, Trinkfenster und Notiz.
///   Die Spaltennamen sind so gewählt, dass die App die Datei auch wieder einlesen kann.
/// - **Flaschen**: eine Zeile pro Flasche mit Kühlschrank, Regal und Fach — wer die App
///   nicht mehr hat, weiss so immer noch, was wo liegt.
enum CellarExport {

    static func file(wines: [Wine], now: Date = Date()) throws -> URL {
        let data = XLSXWriter.data(sheets: [wineSheet(wines), bottleSheet(wines)])
        let stamp = now.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Weinkeller \(stamp).xlsx")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func sorted(_ wines: [Wine]) -> [Wine] {
        wines.sorted {
            let byName = $0.name.localizedStandardCompare($1.name)
            return byName == .orderedSame ? $0.vintage < $1.vintage : byName == .orderedAscending
        }
    }

    private static func wineSheet(_ wines: [Wine]) -> XLSXWriter.Sheet {
        typealias C = XLSXWriter.Cell
        var rows: [[C]] = [[
            .text("Name"), .text("Winzer"), .text("Jahrgang"), .text("Art"), .text("Region"), .text("Traube"),
            .text("Anzahl"), .text("Preis CHF"), .text("Preisangabe"), .text("Wert im Keller CHF"),
            .text("Trinkreif ab"), .text("Trinkreif bis"), .text("Bewertung"), .text("Getrunken"),
            .text("Notiz"), .text("Barcode"),
        ]]
        for wine in sorted(wines) {
            let inCellar = wine.bottlesInCellar.count
            let drunk = (wine.bottles ?? []).filter(\.isDrunk).count
            let window = wine.drinkWindow
            rows.append([
                .text(wine.name),
                .text(wine.producer),
                Int(wine.vintage).map { .number(Double($0)) } ?? .text(wine.vintage),
                .text(wine.type.label),
                .text(wine.region),
                .text(wine.grape),
                .number(Double(inCellar)),
                wine.price.map { .money($0) } ?? .empty,
                wine.price == nil ? .empty : .text(wine.priceIsEstimate ? "Richtpreis aus dem Internet" : "selber eingetragen"),
                wine.price.map { .money($0 * Double(inCellar)) } ?? .empty,
                window.map { .number(Double($0.lowerBound)) } ?? .empty,
                window.map { .number(Double($0.upperBound)) } ?? .empty,
                wine.rating > 0 ? .number(Double(wine.rating)) : .empty,
                drunk > 0 ? .number(Double(drunk)) : .empty,
                .text(wine.note),
                .text(wine.barcode ?? ""),
            ])
        }
        return XLSXWriter.Sheet(name: "Weine", rows: rows,
                                widths: [34, 24, 10, 12, 20, 16, 8, 11, 24, 18, 12, 12, 10, 10, 40, 16])
    }

    private static func bottleSheet(_ wines: [Wine]) -> XLSXWriter.Sheet {
        typealias C = XLSXWriter.Cell
        var rows: [[C]] = [[
            .text("Name"), .text("Jahrgang"), .text("Kühlschrank"), .text("Regal"), .text("Fach"), .text("Status"),
        ]]
        for wine in sorted(wines) {
            let bottles = (wine.bottles ?? []).sorted { a, b in
                // Im Keller zuerst, dann nach Platz; Getrunkene am Schluss.
                if a.isDrunk != b.isDrunk { return !a.isDrunk }
                return (a.shelf?.name ?? "~", a.slot) < (b.shelf?.name ?? "~", b.slot)
            }
            for bottle in bottles {
                let vintage: C = Int(wine.vintage).map { .number(Double($0)) } ?? .text(wine.vintage)
                let status: String
                if let drunkAt = bottle.drunkAt {
                    status = "getrunken am " + drunkAt.formatted(date: .numeric, time: .omitted)
                } else {
                    status = bottle.hasPlace ? "im Keller" : "noch einräumen"
                }
                rows.append([
                    .text(wine.name), vintage,
                    .text(bottle.isDrunk ? "" : bottle.shelf?.fridge?.name ?? ""),
                    .text(bottle.isDrunk ? "" : bottle.shelf?.name ?? ""),
                    bottle.hasPlace && !bottle.isDrunk ? .number(Double(bottle.slot + 1)) : .empty,
                    .text(status),
                ])
            }
        }
        return XLSXWriter.Sheet(name: "Flaschen", rows: rows, widths: [34, 10, 16, 12, 8, 22])
    }
}

/// Das normale Teilen-Fenster von iOS: in Dateien sichern, per Mail, AirDrop, WhatsApp …
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Für `.sheet(item:)` — eine fertige Datei, die geteilt werden soll.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
