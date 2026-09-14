import SwiftUI
import SwiftData

@main
struct WeinkellerApp: App {
    let container: ModelContainer

    @AppStorage("appearance") private var appearanceRaw = Appearance.schwarz.rawValue
    private var appearance: Appearance { Appearance(rawValue: appearanceRaw) ?? .schwarz }

    init() {
        let schema = Schema([Fridge.self, Shelf.self, Wine.self, Bottle.self])

        // Erst mit iCloud versuchen: dann liegt der Keller im Apple-Konto des Besitzers,
        // wird automatisch gesichert und ist auf einem neuen iPhone sofort wieder da.
        // Ohne iCloud-Konto (Simulator, abgemeldetes Gerät) läuft die App lokal weiter,
        // statt beim Start abzustürzen.
        if let cloud = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)) {
            container = cloud
        } else if let local = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)) {
            container = local
        } else {
            fatalError("Datenbank konnte nicht geöffnet werden")
        }
        Self.prepare(container.mainContext)
        BarAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(appearance.scheme)
                .tint(Theme.wine)
        }
        .modelContainer(container)
    }

    /// Beim allerersten Start zwei Kühlschränke anlegen. Regale und Fächer passt der
    /// Besitzer in den Einstellungen an sein Gerät an.
    ///
    /// Das läuft **vor** dem ersten Aufbau der Ansichten. Früher stand es in `.task` der
    /// RootView — dann sah `@Query` beim ersten Start noch die leere Datenbank und der
    /// Bildschirm blieb leer, bis man die App neu startete.
    @MainActor
    private static func prepare(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Fridge>())) ?? []
        guard existing.isEmpty else { return }

        FreshStart.makeDefaultFridges(in: context)
        try? context.save()

        #if DEBUG
        if DebugSeed.isRequested {
            DebugSeed.fill(context, fridges: (try? context.fetch(FetchDescriptor<Fridge>())) ?? [])
        }
        #endif
    }
}
