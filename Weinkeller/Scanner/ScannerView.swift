import SwiftUI
import VisionKit

/// Kamera-Ansicht, die Barcode **und** Etikettentext in einem Durchgang liest.
/// Alles passiert auf dem Gerät: kein Netz, kein Schlüssel, keine Kosten pro Scan.
struct ScannerView: UIViewControllerRepresentable {
    var onBarcode: (String) -> Void
    var onText: (String) -> Void

    /// `isAvailable` prüft zusätzlich, ob die Kamera gerade benutzbar ist —
    /// im Simulator ist sie das nie, auf dem iPhone praktisch immer.
    @MainActor
    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .ean8, .upce, .code128]),
                .text()
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        guard controller.isScanning == false else { return }
        try? controller.startScanning()
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let parent: ScannerView
        private var textLines: [String] = []
        private var didReportBarcode = false

        init(_ parent: ScannerView) { self.parent = parent }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                switch item {
                case .barcode(let code):
                    // Ein Barcode ist eindeutig — sobald einer da ist, ist die Sache klar.
                    guard let value = code.payloadStringValue, !didReportBarcode else { continue }
                    didReportBarcode = true
                    parent.onBarcode(value)
                case .text(let text):
                    textLines.append(text.transcript)
                    // Erst nach ein paar Zeilen melden: eine einzelne Zeile ist selten der Weinname.
                    if textLines.count >= 3 {
                        parent.onText(textLines.joined(separator: " "))
                        textLines.removeAll()
                    }
                @unknown default:
                    continue
                }
            }
        }
    }
}
