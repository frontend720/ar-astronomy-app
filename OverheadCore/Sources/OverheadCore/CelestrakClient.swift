import Foundation
import SatelliteKit

public enum CelestrakError: Error, Sendable {
    /// Non-2xx HTTP response. Celestrak returns 403 with a plaintext explanation if the same
    /// GROUP is requested again before its ~2 hour update cycle elapses — this is Celestrak
    /// throttling repeat clients, not a real error, and callers should treat it as "no fresh
    /// data available right now" rather than a hard failure (keep using cached data).
    case httpError(status: Int, body: String)
    case invalidResponse
    case emptyCatalog
}

/// Fetches current TLEs. Hits the Cloudflare proxy (backend/worker.js) when
/// `proxyBaseURL` is set; falls back to Celestrak directly otherwise.
/// Proxy accepts the same query params as Celestrak so no other code changes when switching.
public struct CelestrakClient: Sendable {
    private let session: URLSession
    private let baseURL: URL

    /// Set to your deployed worker URL after running `npm run deploy` in backend/.
    /// Example: URL(string: "https://overhead-tle-proxy.YOUR-SUBDOMAIN.workers.dev")!
    /// Leave nil to hit Celestrak directly (rate-limit risk on shared IPs).
    public static var proxyBaseURL: URL? = nil

    private static let celestrakURL = URL(string: "https://celestrak.org/NORAD/elements/gp.php")!

    public init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = Self.proxyBaseURL ?? Self.celestrakURL
    }

    /// Fetches and parses every TLE in a Celestrak group, tagging each with `category`.
    public func fetchCatalog(_ category: SatelliteCategory) async throws -> [TrackedObject] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "GROUP", value: category.rawValue),
            URLQueryItem(name: "FORMAT", value: "tle"),
        ]
        guard let url = components.url else { throw CelestrakError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Overhead/1.0 (iOS satellite tracker)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CelestrakError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw CelestrakError.httpError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CelestrakError.invalidResponse
        }

        TLECache.save(text: text, for: category)

        let objects = preProcessTLEs(text).compactMap { line0, line1, line2 -> TrackedObject? in
            guard let elements = try? Elements(line0, line1, line2) else { return nil }
            return TrackedObject(name: elements.commonName, category: category, elements: elements)
        }

        guard !objects.isEmpty else { throw CelestrakError.emptyCatalog }
        return objects
    }

    /// The "stations" group includes Tiangong, ISS, and others; MVP scope only labels the ISS.
    public func fetchISS() async throws -> TrackedObject? {
        try await fetchCatalog(.stations).first { $0.id == TrackedObject.issNoradID }
    }

    /// Returns when the on-disk cache for this category was last written, without parsing TLEs.
    public func cachedCatalogDate(for category: SatelliteCategory) -> Date? {
        TLECache.fetchedAt(for: category)
    }

    /// Loads and parses previously cached TLE text from disk. Returns nil if no cache exists.
    public func loadCachedCatalog(_ category: SatelliteCategory) -> [TrackedObject]? {
        guard let text = TLECache.load(for: category) else { return nil }
        let objects = preProcessTLEs(text).compactMap { line0, line1, line2 -> TrackedObject? in
            guard let elements = try? Elements(line0, line1, line2) else { return nil }
            return TrackedObject(name: elements.commonName, category: category, elements: elements)
        }
        return objects.isEmpty ? nil : objects
    }
}
