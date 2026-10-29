import Foundation

/// The settings file people can export and import. Photos and history stay on the device.
struct ExportPayload: Codable {
    var format = "wakeup-settings"
    var version = 1
    var prefs: Preferences
    var alarm: AlarmConfig
    var items: [HouseholdItem]
    var destinations: [QRDestination]
}

/// Stores everything WakeUp knows in one JSON file in Application Support. Nothing leaves the device.
final class Persistence {
    let directory: URL

    var fileURL: URL { directory.appendingPathComponent("wakeup.json") }
    var photosDirectory: URL { directory.appendingPathComponent("ItemPhotos", isDirectory: true) }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WakeUp", isDirectory: true)
        createDirectories()
    }

    private func createDirectories() {
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
    }

    func load() -> AppData {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(AppData.self, from: data) else { return AppData() }
        return decoded.sanitized()
    }

    func save(_ data: AppData) throws {
        let encoded = try JSONEncoder().encode(data)
        // Readable after first unlock, so an alarm that opens WakeUp on the lock screen can load settings.
        try encoded.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Photos

    func savePhoto(_ jpeg: Data, for id: UUID) throws -> String {
        createDirectories()
        let name = "\(id.uuidString).jpg"
        try jpeg.write(to: photosDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }

    func photoURL(_ name: String) -> URL { photosDirectory.appendingPathComponent(name) }

    func deletePhoto(_ name: String) { try? FileManager.default.removeItem(at: photoURL(name)) }

    /// Removes the settings file, item photos and imported sounds.
    func eraseAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: SoundLibrary.soundsDirectory)
        createDirectories()
    }

    // MARK: Import and export

    enum ImportError: LocalizedError {
        case tooLarge, notWakeUp, newerVersion

        var errorDescription: String? {
            switch self {
            case .tooLarge: "That file is too large to be a WakeUp settings file."
            case .notWakeUp: "That file isn't a WakeUp settings export."
            case .newerVersion: "That file comes from a newer version of WakeUp."
            }
        }
    }

    static func export(_ data: AppData) throws -> Data {
        let items = data.items.map { item -> HouseholdItem in
            var copy = item
            copy.photoFile = nil
            return copy
        }
        let payload = ExportPayload(prefs: data.prefs, alarm: data.alarm, items: items, destinations: data.destinations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Validates an exported file and merges it into the current data. Never executes anything from the file.
    static func importing(_ fileData: Data, into current: AppData) throws -> AppData {
        guard fileData.count < 2_000_000 else { throw ImportError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(ExportPayload.self, from: fileData),
              payload.format == "wakeup-settings" else { throw ImportError.notWakeUp }
        guard payload.version <= 1 else { throw ImportError.newerVersion }

        var merged = current
        merged.prefs = payload.prefs
        merged.alarm = payload.alarm
        // Keep local reference photos for items that still exist.
        let photos = Dictionary(current.items.map { ($0.id, $0.photoFile) }, uniquingKeysWith: { first, _ in first })
        merged.items = payload.items.map { item in
            var copy = item
            copy.photoFile = photos[item.id] ?? nil
            return copy
        }
        merged.destinations = payload.destinations
        return merged.sanitized()
    }
}
