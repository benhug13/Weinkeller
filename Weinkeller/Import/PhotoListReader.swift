import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// Liest eine fotografierte Papierliste.
///
/// Die Texterkennung liefert einzelne Textstücke mit Position, keine Zeilen. Auf einer Liste
/// steht der Preis aber oft weit rechts vom Namen — für Vision zwei Stücke. Darum setzen wir
/// Zeilen selber zusammen: Stücke auf gleicher Höhe gehören zusammen, links nach rechts gelesen.
/// Danach ist es gewöhnlicher Text für `FreeTextList`. Alles läuft auf dem Gerät, nichts geht ins Netz.
extension ListReader {

    #if canImport(UIKit)
    static func table(fromImage image: UIImage) async throws -> CSV.Table {
        if let cgImage = image.cgImage {
            return try await table(fromCGImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        }
        // Manche Bilder (z.B. aus Filtern) haben kein CGImage — neu zeichnen, dabei ist die Drehung schon eingerechnet.
        let rendered = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
        guard let cgImage = rendered.cgImage else { throw ListReaderError.nothingRecognized }
        return try await table(fromCGImage: cgImage, orientation: .up)
    }
    #endif

    static func table(fromCGImage image: CGImage,
                      orientation: CGImagePropertyOrientation = .up) async throws -> CSV.Table {
        let lines = try await recognizeLines(in: image, orientation: orientation)
        let table = table(fromText: lines.joined(separator: "\n"))
        guard !table.rows.isEmpty else { throw ListReaderError.nothingRecognized }
        return table
    }

    static func recognizeLines(in original: CGImage,
                               orientation: CGImagePropertyOrientation) async throws -> [String] {
        let image = flattenedOnWhite(original)
        return try await withCheckedThrowingContinuation { continuation in
            // Texterkennung dauert je nach Foto eine Sekunde — nicht auf dem Hauptthread.
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let wanted = ["de-DE", "fr-FR", "it-IT", "en-US"]
                let supported = (try? request.supportedRecognitionLanguages()) ?? []
                let languages = wanted.filter(supported.contains)
                if !languages.isEmpty { request.recognitionLanguages = languages }

                do {
                    try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
                    let pieces = (request.results ?? []).compactMap { observation -> Piece? in
                        guard let text = observation.topCandidates(1).first?.string,
                              !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                        let box = observation.boundingBox
                        return Piece(text: text, minX: box.minX, midY: box.midY, height: box.height)
                    }
                    continuation.resume(returning: groupIntoLines(pieces))
                } catch {
                    continuation.resume(throwing: ListReaderError.nothingRecognized)
                }
            }
        }
    }

    /// Durchsichtige Bilder (Screenshots, exportierte PNGs) sieht Vision als schwarzen Grund —
    /// schwarze Schrift darauf verschwindet. Darum auf Weiss legen; Kamerafotos bleiben unverändert.
    private static func flattenedOnWhite(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    struct Piece {
        var text: String
        var minX: CGFloat
        var midY: CGFloat
        var height: CGFloat
    }

    /// Stücke, deren Mitte auf der Höhe einer Zeile liegt, gehören zu dieser Zeile.
    /// Die Toleranz ist eine halbe Zeilenhöhe — genug für ein leicht schräges Foto,
    /// zu wenig, um zwei Zeilen zu verschmelzen. Vision misst y von unten nach oben.
    static func groupIntoLines(_ pieces: [Piece]) -> [String] {
        var lines: [[Piece]] = []
        for piece in pieces.sorted(by: { $0.midY > $1.midY }) {
            let candidates = lines.indices.compactMap { index -> (Int, CGFloat)? in
                let line = lines[index]
                let midY: CGFloat = line.map(\.midY).reduce(0, +) / CGFloat(line.count)
                let height: CGFloat = max(line.map(\.height).max() ?? 0, piece.height)
                let distance = abs(midY - piece.midY)
                return distance < height * 0.5 ? (index, distance) : nil
            }
            if let best = candidates.min(by: { $0.1 < $1.1 }) {
                lines[best.0].append(piece)
            } else {
                lines.append([piece])
            }
        }
        func averageY(_ line: [Piece]) -> CGFloat {
            line.map(\.midY).reduce(0, +) / CGFloat(line.count)
        }
        let ordered: [[Piece]] = lines.sorted { averageY($0) > averageY($1) }
        return ordered.map { line -> String in
            line.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ")
        }
    }
}

#if canImport(UIKit)
private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
#endif
