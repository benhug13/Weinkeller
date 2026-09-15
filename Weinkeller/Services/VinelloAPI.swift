import Foundation
import UIKit

/// Verbindung zum eigenen kleinen Server (`vinello-api.vercel.app`).
///
/// **Warum ein Server und nicht direkt Groq?** Der Groq-Schlüssel darf nicht in die App —
/// aus einer App-Datei lässt er sich auslesen. Er liegt auf dem Server; die App schickt nur
/// eine App-Kennung mit, damit nicht jede beliebige Webseite den Server benutzt.
///
/// **Keine Datenbank:** Ein Wein wird nicht gesucht, sondern sein Etikett wird gelesen.
/// Das klappt auch mit Weinen, die in keinem Katalog stehen. Preise kommen aus dem Internet,
/// und der Server behält nur Preise, die er auf der Shop-Seite selber wiedergefunden hat.
enum VinelloAPI {
    static let baseURL = URL(string: "https://vinello-api.vercel.app")!

    struct LabelResult: Decodable {
        var isWineLabel: Bool
        var name: String
        var producer: String
        var vintage: String
        var region: String
        var grape: String
        var type: String

        var wineType: WineType { WineType(rawValue: type) ?? .rot }
    }

    struct PriceSource: Decodable, Hashable {
        var shop: String
        var url: String
        var price: Double
        var currency: String
        var priceCHF: Double
    }

    struct PriceResult: Decodable {
        var found: Bool
        var lowCHF: Double?
        var highCHF: Double?
        var typicalCHF: Double?
        var sources: [PriceSource]
    }

    enum Failure: LocalizedError {
        case offline, busy, server(String)

        var errorDescription: String? {
            switch self {
            case .offline:         return "Keine Internetverbindung. Im Keller ohne Empfang geht das nicht — später nochmals versuchen."
            case .busy:            return "Der Dienst ist gerade ausgelastet. In einer Minute nochmals versuchen."
            case .server(let msg): return msg
            }
        }
    }

    /// Etikett-Foto → Felder. Das Bild wird vorher verkleinert (1024 px), das reicht zum Lesen.
    static func readLabel(_ imageData: Data) async throws -> LabelResult {
        guard let image = UIImage(data: imageData),
              let jpeg = shrink(image, maxSide: 1024) else {
            throw Failure.server("Das Foto liess sich nicht lesen.")
        }
        return try await post("api/label", body: ["image": jpeg.base64EncodedString()])
    }

    static func findPrice(name: String, producer: String, vintage: String, region: String) async throws -> PriceResult {
        try await post("api/price", body: ["name": name, "producer": producer, "vintage": vintage, "region": region])
    }

    // MARK: - Netz

    private struct ErrorBody: Decodable { var error: String?; var retryAfter: Double? }

    /// Ist Groq kurz ausgelastet (Gratis-Stufe: Tokens pro Minute), wartet die App die
    /// genannte Zeit und versucht es noch zweimal — der Besitzer merkt davon nur ein paar Sekunden.
    private static func post<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.vinelloAppKey, forHTTPHeaderField: "x-vinello-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        for attempt in 0..<3 {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost,
                                                  .cannotFindHost, .timedOut, .dataNotAllowed].contains(error.code) {
                throw Failure.offline
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return try JSONDecoder().decode(T.self, from: data) }

            let info = try? JSONDecoder().decode(ErrorBody.self, from: data)
            if status == 429 {
                guard attempt < 2 else { throw Failure.busy }
                let wait = min(max(info?.retryAfter ?? 20, 3), 45)
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                continue
            }
            throw Failure.server(info?.error ?? "Der Dienst hat nicht geantwortet (\(status)).")
        }
        throw Failure.busy
    }

    static func shrink(_ image: UIImage, maxSide: CGFloat) -> Data? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.8)
    }
}
