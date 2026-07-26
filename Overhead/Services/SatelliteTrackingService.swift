import Foundation
import OverheadCore

/// Fetches the MVP catalog (ISS + Starlink) from Celestrak, then re-propagates positions on a
/// short timer so the AR overlay tracks live movement without re-fetching TLEs.
///
/// Two independent tasks run after `start()`:
///   - `positionLoop` — propagates cached objects to current Az/El every 2 s. Never touches the
///     network, so it renders immediately from disk cache and is never blocked by timeouts.
///   - `catalogLoop`  — refreshes TLEs from Celestrak in the background. Takes as long as it
///     needs (including waiting out a 60 s timeout in airplane mode) without stalling positions.
@MainActor
final class SatelliteTrackingService: ObservableObject {
    @Published private(set) var snapshots: [SatelliteSnapshot] = []
    @Published private(set) var lastError: Error?

    // Debug-accessible state
    @Published private(set) var lastCatalogSuccess: Date = .distantPast
    @Published private(set) var consecutiveCatalogFailures = 0
    @Published private(set) var catalogObjectCount = 0

    private let client = CelestrakClient()
    private var positionTask: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?

    private var issObject: TrackedObject?
    private var starlinkObjects: [TrackedObject] = []

    private var lastCatalogAttempt: Date = .distantPast
    private var lastFailureWas403 = false

    private let catalogRefreshInterval: TimeInterval = 6 * 3600
    private let catalogBanBackoff: TimeInterval       = 2 * 3600
    private let catalogTransientBackoff: TimeInterval = 5 * 60
    private let catalogRetryMaxBackoff: TimeInterval  = 2 * 3600
    private let positionRefreshInterval: TimeInterval = 2

    var maxVisibleStarlink: Int = 10

    func start(observer: ObserverLocation) async {
        positionTask?.cancel()
        catalogTask?.cancel()
        loadInitialCache()
        positionTask = Task { [weak self] in await self?.positionLoop(observer: observer) }
        catalogTask  = Task { [weak self] in await self?.catalogLoop() }
    }

    /// Loads ISS + Starlink from disk so positions are available immediately before any
    /// network request is attempted. Also restores `lastCatalogSuccess` from the cache
    /// timestamp so a still-fresh cache doesn't trigger an unnecessary network attempt.
    private func loadInitialCache() {
        if let objects = client.loadCachedCatalog(.stations) {
            issObject = objects.first { $0.id == TrackedObject.issNoradID }
        }
        if let objects = client.loadCachedCatalog(.starlink) {
            starlinkObjects = objects
        }
        catalogObjectCount = (issObject != nil ? 1 : 0) + starlinkObjects.count

        // Restore the refresh clock from the older of the two cache timestamps so the
        // 6-hour refresh interval is respected across launches and fresh cache is reused.
        let issDate      = client.cachedCatalogDate(for: .stations) ?? .distantPast
        let starlinkDate = client.cachedCatalogDate(for: .starlink) ?? .distantPast
        if issObject != nil && !starlinkObjects.isEmpty {
            lastCatalogSuccess = min(issDate, starlinkDate)
        }
    }

    // MARK: - Position loop (network-free)

    private func positionLoop(observer: ObserverLocation) async {
        while !Task.isCancelled {
            let catalog = (issObject.map { [$0] } ?? []) + starlinkObjects
            let allSnapshots = SatellitePosition.snapshots(for: catalog, observer: observer)
            snapshots = Self.limitClutter(allSnapshots, maxStarlink: maxVisibleStarlink)
            try? await Task.sleep(nanoseconds: UInt64(positionRefreshInterval * 1_000_000_000))
        }
    }

    // MARK: - Catalog refresh loop (background, network)

    private func catalogLoop() async {
        while !Task.isCancelled {
            await refreshCatalogIfDue()
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        }
    }

    private var currentRetryBackoff: TimeInterval {
        guard consecutiveCatalogFailures > 0 else { return 0 }
        let base = lastFailureWas403 ? catalogBanBackoff : catalogTransientBackoff
        let exponential = base * pow(2, Double(consecutiveCatalogFailures - 1))
        let capped = min(exponential, catalogRetryMaxBackoff)
        return capped * Double.random(in: 0.8...1.2)
    }

    private func refreshCatalogIfDue() async {
        let now = Date()
        let haveCompleteData = issObject != nil && !starlinkObjects.isEmpty
        let stale = now.timeIntervalSince(lastCatalogSuccess) > catalogRefreshInterval
        guard !haveCompleteData || stale else { return }
        guard now.timeIntervalSince(lastCatalogAttempt) > currentRetryBackoff else { return }
        lastCatalogAttempt = now

        async let issResult: Result<TrackedObject?, Error> = {
            do { return .success(try await client.fetchISS()) } catch { return .failure(error) }
        }()
        async let starlinkResult: Result<[TrackedObject], Error> = {
            do { return .success(try await client.fetchCatalog(.starlink)) } catch { return .failure(error) }
        }()

        var issSucceeded = false
        var starlinkSucceeded = false
        var latestError: Error?
        var any403 = false

        switch await issResult {
        case .success(let iss):
            issObject = iss
            issSucceeded = true
        case .failure(let error):
            latestError = error
            if case CelestrakError.httpError(403, _) = error { any403 = true }
        }

        switch await starlinkResult {
        case .success(let starlink):
            starlinkObjects = starlink
            starlinkSucceeded = true
        case .failure(let error):
            latestError = error
            if case CelestrakError.httpError(403, _) = error { any403 = true }
        }

        if issSucceeded && starlinkSucceeded {
            lastCatalogSuccess = now
            consecutiveCatalogFailures = 0
            lastFailureWas403 = false
            catalogObjectCount = (issObject != nil ? 1 : 0) + starlinkObjects.count
        } else {
            consecutiveCatalogFailures += 1
            lastFailureWas403 = any403
        }
        lastError = latestError
    }

    // MARK: - Clutter limiting

    private static func limitClutter(_ snapshots: [SatelliteSnapshot], maxStarlink: Int) -> [SatelliteSnapshot] {
        let visible = snapshots.filter { $0.look.isAboveHorizon }
        let stations = visible.filter { $0.object.category == .stations }
        let nearestStarlink = visible
            .filter { $0.object.category == .starlink }
            .sorted { $0.look.rangeKm < $1.look.rangeKm }
            .prefix(maxStarlink)
        return stations + nearestStarlink
    }
}
