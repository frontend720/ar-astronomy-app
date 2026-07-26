import Foundation

/// One rise-to-set window for a satellite, as seen from a fixed observer.
public struct SatellitePass: Sendable {
    public let riseTime: Date
    public let maxElevationTime: Date
    public let setTime: Date
    public let maxElevationDegrees: Double
}

/// Brute-force pass search: steps through time looking for elevation crossing above the
/// visibility threshold. Precision is bounded by `stepSeconds` (default: within ~30s of the
/// true rise/set time) — adequate for a "visible in ~6 minutes" notification, not for
/// frame-accurate AR tracking (that uses SatellitePosition.snapshot directly, live).
public enum PassPredictor {

    public static func nextPasses(
        for object: TrackedObject,
        observer: ObserverLocation,
        from start: Date = Date(),
        searchWindow: TimeInterval = 24 * 3600,
        stepSeconds: TimeInterval = 30,
        minElevationDegrees: Double = 0,
        maxPasses: Int = 5
    ) -> [SatellitePass] {
        var passes: [SatellitePass] = []
        let end = start.addingTimeInterval(searchWindow)
        var t = start

        var wasAbove = false
        var riseTime: Date?
        var maxElevation = -90.0
        var maxElevationTime = start

        while t < end, passes.count < maxPasses {
            defer { t = t.addingTimeInterval(stepSeconds) }

            guard let snapshot = try? SatellitePosition.snapshot(for: object, observer: observer, at: t) else {
                continue
            }
            let isAbove = snapshot.look.elevationDegrees > minElevationDegrees

            if isAbove, !wasAbove {
                riseTime = t
                maxElevation = snapshot.look.elevationDegrees
                maxElevationTime = t
            } else if isAbove, riseTime != nil, snapshot.look.elevationDegrees > maxElevation {
                maxElevation = snapshot.look.elevationDegrees
                maxElevationTime = t
            } else if !isAbove, wasAbove, let rise = riseTime {
                passes.append(SatellitePass(
                    riseTime: rise,
                    maxElevationTime: maxElevationTime,
                    setTime: t,
                    maxElevationDegrees: maxElevation
                ))
                riseTime = nil
                maxElevation = -90.0
            }

            wasAbove = isAbove
        }

        return passes
    }
}
