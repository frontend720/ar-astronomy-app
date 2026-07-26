import Foundation

/// Persists raw TLE text to Application Support between app launches.
/// Application Support survives updates and is never purged by the OS, unlike Caches.
struct TLECache {

    private struct Payload: Codable {
        let text: String
        let fetchedAt: Date
    }

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OverheadTLECache", isDirectory: true)
    }

    static func save(text: String, for category: SatelliteCategory) {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Payload(text: text, fetchedAt: Date())) else { return }
        try? data.write(to: fileURL(for: category), options: .atomic)
    }

    static func load(for category: SatelliteCategory) -> String? {
        guard let data = try? Data(contentsOf: fileURL(for: category)),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        return payload.text
    }

    /// Returns when the cache for this category was last written, without loading the full text.
    static func fetchedAt(for category: SatelliteCategory) -> Date? {
        guard let data = try? Data(contentsOf: fileURL(for: category)),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        return payload.fetchedAt
    }

    private static func fileURL(for category: SatelliteCategory) -> URL {
        directory.appendingPathComponent("\(category.rawValue).json")
    }
}
